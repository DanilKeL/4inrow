import importlib.util
import io
import json
import sqlite3
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("backup", Path(__file__).with_name("backup-database.py"))
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class Backups(unittest.TestCase):
    def test_snapshot_contains_committed_wal_data_and_verified_accounts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data, state = root / "data", root / "state"
            data.mkdir()
            state.mkdir()
            accounts = {"accounts": {"Alice": {"username": "Alice"}}, "sessions": {}}
            (data / "accounts.json").write_text(json.dumps(accounts))
            with sqlite3.connect(data / "statistics.sqlite") as live:
                live.execute("PRAGMA journal_mode=WAL")
                live.execute("CREATE TABLE ratings (owner TEXT, points INTEGER)")
                live.execute("INSERT INTO ratings VALUES ('Alice', 1200)")
                live.commit()
                self.assertTrue((data / "statistics.sqlite-wal").is_file())
                result = backup.archive(data, state, "20261009T110000Z")
                with tarfile.open(result) as packed:
                    self.assertEqual(set(packed.getnames()), {"accounts.json", "statistics.sqlite", "manifest.json"})
                    self.assertEqual(json.load(packed.extractfile("accounts.json")), accounts)
                    sql = root / "restored.sqlite"
                    sql.write_bytes(packed.extractfile("statistics.sqlite").read())
                    with sqlite3.connect(sql) as restored:
                        self.assertEqual(restored.execute("SELECT * FROM ratings").fetchall(), [("Alice", 1200)])
                        self.assertEqual(restored.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
                    manifest = json.load(packed.extractfile("manifest.json"))
                    self.assertEqual(manifest["files"]["statistics.sqlite"]["sha256"], backup.digest(sql))

    def test_retention_keeps_24_newest_and_never_includes_other_files(self):
        names = [f"four-game-db-202610{i:02}T110000Z.tar.gz" for i in range(1, 31)]
        others = ["personal.tar.gz", "../four-game-db-20261001T110000Z.tar.gz", ".upload",
                  "four-game-db-20269999T110000Z.tar.gz", "four-game-db-20261001T110000Z.tar.gz/child"]
        self.assertEqual(backup.obsolete(names + others), list(reversed(names[:6])))

    def test_failed_upload_never_prunes_existing_backups(self):
        disk = Mock()
        disk.publish.side_effect = backup.BackupError("Verification failed")
        with self.assertRaises(backup.BackupError):
            backup.upload(Path("four-game-db-20261009T110000Z.tar.gz"), disk)
        disk.prune.assert_not_called()

    def test_verified_upload_precedes_pruning(self):
        disk = Mock()
        local = Path("four-game-db-20261009T110000Z.tar.gz")
        backup.upload(local, disk)
        self.assertEqual([call[0] for call in disk.mock_calls], ["publish", "prune"])
        disk.prune.assert_called_once_with(local.name)

    def test_incomplete_listing_never_deletes_older_copies(self):
        disk = backup.Disk(Path("not-a-secret"))
        disk.run = Mock(return_value=json.dumps([{"Path": "other.tar.gz", "IsDir": False}]).encode())
        with self.assertRaises(backup.BackupError):
            disk.prune("four-game-db-20261009T110000Z.tar.gz")
        self.assertEqual(disk.run.call_count, 1)

    def test_remote_retention_deletes_only_exact_owned_paths(self):
        disk = backup.Disk(Path("not-a-secret"))
        names = [f"four-game-db-202610{i:02}T110000Z.tar.gz" for i in range(1, 26)]
        listing = [{"Path": name, "IsDir": False} for name in names + ["important.txt"]]
        listing.append({"Path": names[0], "IsDir": True})
        disk.run = Mock(return_value=json.dumps(listing).encode())
        disk.prune(names[-1])
        self.assertEqual(disk.run.call_args_list[-1].args, ("deletefile", f"{backup.REMOTE}/{names[0]}"))
        self.assertEqual(disk.run.call_count, 2)

    def test_corrupted_download_fails_verification(self):
        with tempfile.TemporaryDirectory() as folder:
            local = Path(folder) / "archive.tar.gz"
            local.write_bytes(b"correct backup bytes")
            process = Mock(stdout=io.BytesIO(b"corrupted bytes"))
            process.wait.return_value = 0
            process.poll.return_value = 0
            with patch.object(backup.subprocess, "Popen", return_value=process):
                with self.assertRaises(backup.BackupError):
                    backup.Disk(Path("not-a-secret")).verify(local, "yandex:staged-file")

    def test_verification_failure_cleans_only_this_runs_staged_file(self):
        disk = backup.Disk(Path("not-a-secret"))
        disk.run = Mock()
        disk.verify = Mock(side_effect=backup.BackupError("Corrupted"))
        local = Path("four-game-db-20261009T110000Z.tar.gz")
        with self.assertRaises(backup.BackupError):
            disk.publish(local)
        self.assertEqual(disk.run.call_args_list[-1].args,
                         ("deletefile", f"{backup.REMOTE}/.{local.name}.upload"))
        self.assertFalse(any(call.args[0] == "moveto" for call in disk.run.call_args_list))


if __name__ == "__main__":
    unittest.main()
