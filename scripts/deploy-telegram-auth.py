"""Install a verified release on the existing FOUR server, with rollback."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request


def run(*args):
    subprocess.run(args, check=True)


def main():
    if os.getuid() != 0:
        raise RuntimeError('Run on the server as root')
    os.umask(0o077)
    archive = Path(sys.argv[1]).resolve()
    expected = sys.argv[2]
    if archive.parent != Path('/srv/four-game-releases'):
        raise RuntimeError('Release must be in the release directory')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Release checksum mismatch')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/srv/four-game-backups') / ('pre-telegram-auth-' + stamp)
    backup.mkdir(mode=0o700)
    app = Path('/srv/four-game')
    service = Path('/etc/systemd/system/four-game.service')
    credential = Path('/etc/four-game/telegram.env')
    shutil.copy2(service, backup / 'four-game.service')
    shutil.copy2(credential, backup / 'telegram.env')
    bot_active = subprocess.run(['systemctl', 'is-active', '--quiet', 'four-telegram-bot']).returncode == 0
    cloud = None if '--local-backup' in sys.argv[3:] else subprocess.run(['systemctl', 'start', 'four-game-backup.service'])
    if cloud is None or cloud.returncode:
        # A remote upload outage must not prevent a release with a verified local
        # rollback snapshot. The snapshot below is mandatory before swapping.
        print('Cloud upload unavailable; a verified local database snapshot is required for this release.', flush=True)
    stage = archive.parent / ('telegram-auth-' + stamp)
    stage.mkdir(mode=0o700)
    with tarfile.open(archive) as release:
        release.extractall(stage, filter='data')
    fresh = stage / 'four-game'
    # Existing tabs may still request chunks from the preceding frontend build.
    previous_assets = app / 'dist/assets'
    if previous_assets.exists():
        for old_file in previous_assets.rglob('*'):
            if old_file.is_file():
                destination = fresh / 'dist/assets' / old_file.relative_to(previous_assets)
                if not destination.exists():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(old_file, destination)
    run('npm', 'ci', '--omit=dev', '--prefix', str(fresh))
    run('chown', '-R', 'fourgame:fourgame', str(fresh))
    swapped = False
    stopped = False
    try:
        if bot_active:
            run('systemctl', 'stop', 'four-telegram-bot')
        run('systemctl', 'stop', 'four-game')
        stopped = True
        run('python3', '/usr/local/lib/four-game/backup-database.py', '--snapshot-only')
        snapshots = sorted(Path('/var/lib/four-game-backup/archives').glob('*.tar.gz'))
        if not snapshots:
            raise RuntimeError('Database snapshot is missing')
        shutil.copy2(snapshots[-1], backup / 'database.tar.gz')
        values = dict(line.split('=', 1) for line in credential.read_text().splitlines() if '=' in line)
        if not values.get('TELEGRAM_BOT_TOKEN', '').startswith('8834741855:'):
            raise RuntimeError('Telegram bot does not match the configured login client')
        lines = [line for line in credential.read_text().splitlines() if not line.startswith('TELEGRAM_LOGIN_CLIENT_ID=')]
        lines.append('TELEGRAM_LOGIN_CLIENT_ID=8834741855')
        credential.write_text('\n'.join(lines) + '\n')
        credential.chmod(0o600)
        shutil.copy2(fresh / 'deploy/four-game.service', service)
        service.chmod(0o644)
        os.rename(app, backup / 'app')
        os.rename(fresh, app)
        swapped = True
        run('systemctl', 'daemon-reload')
        run('systemctl', 'start', 'four-game')
        for attempt in range(25):
            try:
                with urllib.request.urlopen('http://127.0.0.1:3001/health', timeout=2) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(1)
        else:
            raise RuntimeError('Updated service failed its health check')
        if bot_active:
            run('systemctl', 'start', 'four-telegram-bot')
            run('systemctl', 'is-active', '--quiet', 'four-telegram-bot')
    except Exception:
        if bot_active:
            run('systemctl', 'stop', 'four-telegram-bot')
        if stopped:
            run('systemctl', 'stop', 'four-game')
        if swapped:
            os.rename(app, stage / 'failed-app')
            os.rename(backup / 'app', app)
        elif (backup / 'app').exists() and not app.exists():
            os.rename(backup / 'app', app)
        shutil.copy2(backup / 'four-game.service', service)
        shutil.copy2(backup / 'telegram.env', credential)
        run('systemctl', 'daemon-reload')
        run('systemctl', 'start', 'four-game')
        if bot_active:
            run('systemctl', 'start', 'four-telegram-bot')
        raise
    print('BACKUP=' + str(backup))
    print('RELEASE_SHA256=' + expected)
    print('Telegram authentication release is healthy')


if __name__ == '__main__':
    main()
