#!/usr/bin/env python3
"""Consistent online snapshots and verified, bounded Yandex Disk backups."""
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

REMOTE = "yandex:4inrow-backups/database"
KEEP = 24
BACKUP_NAME = re.compile(r"four-game-db-\d{8}T\d{6}Z\.tar\.gz\Z")


class BackupError(Exception):
    pass


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def managed_name(name):
    if not isinstance(name, str) or not BACKUP_NAME.fullmatch(name):
        return False
    try:
        datetime.strptime(name, "four-game-db-%Y%m%dT%H%M%SZ.tar.gz")
        return True
    except ValueError:
        return False


def obsolete(names):
    return sorted({name for name in names if managed_name(name)}, reverse=True)[KEEP:]


def snapshot(data, target):
    """The app atomically replaces accounts.json. Retry if it changes during SQL backup."""
    auth = data / "accounts.json"
    database = data / "statistics.sqlite"
    if not auth.is_file() or not database.is_file():
        raise BackupError("Required production database files are missing")
    for _ in range(3):
        accounts = auth.read_bytes()
        parsed = json.loads(accounts)
        if not isinstance(parsed.get("accounts"), dict) or not isinstance(parsed.get("sessions"), dict):
            raise BackupError("Invalid accounts database")
        copied = target / "statistics.sqlite"
        copied.unlink(missing_ok=True)
        deadline = time.monotonic() + 120

        def progress(_status, _remaining, _total):
            if time.monotonic() > deadline:
                raise BackupError("SQLite snapshot timed out")

        with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as source:
            with sqlite3.connect(copied) as destination:
                source.backup(destination, pages=256, progress=progress)
                destination.execute("PRAGMA journal_mode=DELETE")
                if destination.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise BackupError("SQLite snapshot failed integrity check")
        if accounts == auth.read_bytes():
            (target / "accounts.json").write_bytes(accounts)
            return
    raise BackupError("Accounts changed repeatedly during snapshot; retry on next run")


def archive(data, state, stamp):
    name = f"four-game-db-{stamp}.tar.gz"
    if not managed_name(name):
        raise BackupError("Invalid backup timestamp")
    backups = state / "archives"
    backups.mkdir(mode=0o700, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="snapshot-", dir=state) as directory:
        root = Path(directory)
        snapshot(data, root)
        files = ("accounts.json", "statistics.sqlite")
        manifest = {
            "version": 1, "site": "https://4inrow.ru", "createdAt": stamp,
            "files": {name: {"sha256": digest(root / name), "bytes": (root / name).stat().st_size}
                      for name in files},
        }
        (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        temporary = root / "backup.tar.gz"
        with tarfile.open(temporary, "w:gz") as output:
            for file in (*files, "manifest.json"):
                output.add(root / file, arcname=file)
        with tarfile.open(temporary, "r:gz") as packed:
            for file in files:
                stream = packed.extractfile(file)
                if stream is None or hashlib.file_digest(stream, "sha256").hexdigest() != manifest["files"][file]["sha256"]:
                    raise BackupError("Archive verification failed")
        final = backups / name
        os.replace(temporary, final)
        for old in obsolete(path.name for path in backups.iterdir() if path.is_file() and not path.is_symlink()):
            (backups / old).unlink()
        return final


class Disk:
    def __init__(self, config):
        self.base = ["/usr/bin/rclone", "--config", str(config), "--log-level", "ERROR",
                     "--retries", "3", "--low-level-retries", "3",
                     "--contimeout", "15s", "--timeout", "60s"]

    def run(self, *args):
        try:
            result = subprocess.run([*self.base, *args], capture_output=True, timeout=180)
        except subprocess.TimeoutExpired:
            raise BackupError(f"Yandex Disk {args[0]} timed out") from None
        if result.returncode:
            # Do not put credentials, paths with user data or HTTP headers in logs.
            raise BackupError(f"Yandex Disk {args[0]} failed (rclone exit {result.returncode})")
        return result.stdout

    def verify(self, local, remote):
        # Plain WebDAV has no dependable SHA-256; read back the actual uploaded bytes.
        expected = digest(local)
        process = subprocess.Popen([*self.base, "cat", remote], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL)
        # rclone's inactivity timeout bounds reads; systemd also bounds the whole job.
        try:
            actual = hashlib.file_digest(process.stdout, "sha256").hexdigest()
            result = process.wait(timeout=180)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
        if result or actual != expected:
            raise BackupError("Uploaded backup failed SHA-256 verification")

    def publish(self, local):
        self.run("mkdir", REMOTE)
        pending = f"{REMOTE}/.{local.name}.upload"
        final = f"{REMOTE}/{local.name}"
        moved = False
        try:
            self.run("copyto", str(local), pending)
            self.verify(local, pending)
            self.run("moveto", pending, final)
            moved = True
            self.verify(local, final)
        except Exception:
            # Only this job's staged file is removed; older complete backups are untouched.
            try:
                self.run("deletefile", final if moved else pending)
            except BackupError:
                pass
            raise

    def prune(self, current):
        entries = json.loads(self.run("lsjson", REMOTE, "--files-only", "--max-depth", "1"))
        names = [entry["Path"] for entry in entries if not entry.get("IsDir") and managed_name(entry.get("Path"))]
        if current not in names:
            raise BackupError("New backup not visible in listing; old backups retained")
        for name in obsolete(names):
            self.run("deletefile", f"{REMOTE}/{name}")


def upload(local, disk):
    disk.publish(local)
    disk.prune(local.name)


def status(state, value):
    temporary = state / "status.json.tmp"
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, state / "status.json")


def main(snapshot_only=False):
    import fcntl
    os.umask(0o077)
    state = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/four-game-backup"))
    data = Path("/srv/four-game-data")
    config = Path(os.environ.get("CREDENTIALS_DIRECTORY", "/etc/four-game")) / "yandex-rclone.conf"
    state.mkdir(mode=0o700, exist_ok=True)
    with (state / "backup.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise BackupError("Another backup is already running") from None
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        previous = {}
        if (state / "status.json").exists():
            previous = json.loads((state / "status.json").read_text())
        try:
            local = archive(data, state, stamp)
            if snapshot_only:
                print(f"Local snapshot verified: {local.name}; SHA256={digest(local)}", flush=True)
                return
            upload(local, Disk(config))
            status(state, {"lastAttempt": stamp, "lastSuccess": stamp, "backup": local.name,
                           "sha256": digest(local), "remote": REMOTE, "retention": KEEP, "ok": True})
            print(f"Verified backup {local.name}; retaining the latest {KEEP} copies", flush=True)
        except Exception as error:
            message = str(error) if isinstance(error, BackupError) else type(error).__name__
            status(state, {**previous, "lastAttempt": stamp, "ok": False, "error": message})
            raise BackupError(message) from None


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot-only", action="store_true", help="Verify a local snapshot without cloud access")
    options = parser.parse_args()
    try:
        main(snapshot_only=options.snapshot_only)
    except BackupError as error:
        print(f"Backup failed: {error}", flush=True)
        raise SystemExit(1)
