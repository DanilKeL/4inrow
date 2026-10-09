#!/usr/bin/env python3
"""Enter a dedicated WebDAV app password on the server, never in command history."""
import configparser
import getpass
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run with sudo")
    os.umask(0o077)
    login = input("Yandex login: ").strip()
    password = getpass.getpass("WebDAV app password (hidden): ").strip()
    if not login or not password or any(c in login + password for c in "\r\n\x00"):
        raise SystemExit("Login and app password are required")
    encoded = subprocess.run(["/usr/bin/rclone", "obscure", "-"], input=password,
                             text=True, capture_output=True, check=True).stdout.strip()
    config = configparser.ConfigParser(interpolation=None)
    config["yandex"] = {"type": "webdav", "url": "https://webdav.yandex.ru",
                        "vendor": "other", "user": login, "pass": encoded}
    directory = Path("/etc/four-game")
    directory.mkdir(mode=0o700, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".yandex-", dir=directory)
    path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w") as stream:
            config.write(stream)
        # Check access without displaying the user's files or credentials.
        result = subprocess.run(["/usr/bin/rclone", "--config", str(path),
                                 "--contimeout", "15s", "--timeout", "30s",
                                 "--retries", "1", "lsf", "yandex:", "--max-depth", "1"],
                                capture_output=True, timeout=90)
        if result.returncode:
            raise SystemExit("Could not connect to Yandex Disk. Check login and WebDAV app password.")
        os.replace(path, directory / "yandex-rclone.conf")
    finally:
        path.unlink(missing_ok=True)
    subprocess.run(["systemctl", "start", "four-game-backup.service"], check=True)
    subprocess.run(["systemctl", "enable", "--now", "four-game-backup.timer"], check=True)
    print("First backup verified. Hourly backups enabled; keeping the latest 24 copies.")


if __name__ == "__main__":
    main()
