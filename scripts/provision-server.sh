#!/bin/sh
set -eu
umask 077
app=/srv/four-game
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=/srv/four-game-backups/pre-migration-$stamp
mkdir -p "$backup" /etc/four-game /var/www/letsencrypt /srv/four-game-data
chmod 700 "$backup" /etc/four-game /srv/four-game-data
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
chmod 755 /var/www/letsencrypt /var/www/letsencrypt/.well-known /var/www/letsencrypt/.well-known/acme-challenge
tar -czf "$backup/nginx-before.tgz" -C /etc nginx
if [ -f /etc/systemd/system/four-game.service ]; then
    cp /etc/systemd/system/four-game.service "$backup/four-game.service"
fi
if [ -d "$app" ]; then
    tar --exclude=node_modules -czf "$backup/app-before.tgz" -C "$app" .
fi
if ! id fourgame >/dev/null 2>&1; then
    useradd --system --home-dir "$app" --shell /usr/sbin/nologin fourgame
fi
mkdir -p "$app"
tar -xzf /root/four-migration-release.tgz -C "$app"
install -o root -g root -m 600 /root/four-migration-admin.env /etc/four-game/admin.env
install -o root -g root -m 600 /root/four-migration-mail.env /etc/four-game/mail.env
cd "$app"
npm ci --omit=dev --no-audit --no-fund
chown -R fourgame:fourgame "$app" /srv/four-game-data
install -o root -g root -m 644 deploy/four-game.service /etc/systemd/system/four-game.service
systemctl daemon-reload
systemctl enable --now four-game
healthy=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS http://127.0.0.1:3001/health > "$backup/health.json"; then healthy=1; break; fi
    sleep 1
done
[ "$healthy" = 1 ] || { journalctl -u four-game -n 30 --no-pager; exit 1; }
install -o root -g root -m 644 deploy/nginx-domain-http.conf /etc/nginx/sites-available/four-game
ln -sfn /etc/nginx/sites-available/four-game /etc/nginx/sites-enabled/four-game
# The game owns the default HTTP virtual host and redirects it to the domain.
if [ -L /etc/nginx/sites-enabled/default ] && [ "$(readlink /etc/nginx/sites-enabled/default)" = /etc/nginx/sites-available/default ]; then
    unlink /etc/nginx/sites-enabled/default
fi
nginx -t
systemctl enable --now nginx
systemctl reload nginx
(
umask 022
certbot certonly --webroot -w /var/www/letsencrypt --cert-name 4inrow.ru \
    -d 4inrow.ru -d www.4inrow.ru --non-interactive --agree-tos --register-unsafely-without-email
)
install -o root -g root -m 644 deploy/nginx-domain.conf /etc/nginx/sites-available/four-game
nginx -t
systemctl reload nginx
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nnginx -t && systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/four-game-nginx
chmod 700 /etc/letsencrypt/renewal-hooks/deploy/four-game-nginx
systemctl enable --now certbot.timer
cp /root/four-migration-release.tgz "$backup/release.tgz"
find assets deploy e2e public references scripts server src -type f ! -name '*.blend1' -print0 | sort -z | xargs -0 sha256sum > SOURCE-MANIFEST.sha256
sha256sum package-lock.json package.json index.html README.md START-HERE.txt eslint.config.js vite.config.ts playwright.config.ts tsconfig.json >> SOURCE-MANIFEST.sha256
printf 'BACKUP=%s\n' "$backup"
curl -fsS --resolve 4inrow.ru:443:127.0.0.1 https://4inrow.ru/health
printf '\n'
systemctl is-active four-game nginx certbot.timer
openssl x509 -in /etc/letsencrypt/live/4inrow.ru/fullchain.pem -noout -dates -ext subjectAltName
