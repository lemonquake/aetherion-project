#!/usr/bin/env bash
# Sets up (or refreshes) the Aetherion official servers on this VPS. Safe to run again.
#   sudo bash install.sh          (from a folder holding this script and the files next to it)
# Leaves the existing Caddy sites alone: Aetherion's site is /etc/caddy/sites/aetherion.caddy, pulled in by one
# "import /etc/caddy/sites/*.caddy" line at the end of /etc/caddy/Caddyfile. Servers start once a release is active
# (tools/release/publish.py activate).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
DEPLOY_USER=${SUDO_USER:-ubuntu}

id aetherion >/dev/null 2>&1 || useradd --system --home-dir /var/lib/aetherion --shell /usr/sbin/nologin aetherion
install -d -o aetherion -g aetherion -m 0750 /var/lib/aetherion /var/lib/aetherion/data /var/lib/aetherion/stats
install -d -m 0755 /opt/aetherion /opt/aetherion/bin /opt/aetherion/releases /etc/aetherion
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0755 /srv/aetherion /srv/aetherion/site /srv/aetherion/updates \
  /srv/aetherion/updates/chunks /srv/aetherion/downloads
install -m 0755 "$HERE/aetherion-admin" /opt/aetherion/bin/aetherion-admin
install -m 0644 "$HERE/update-public-key.json" /opt/aetherion/update-public-key.json
install -m 0644 "$HERE/aetherion-master.service" "$HERE/aetherion-server@.service" /etc/systemd/system/
install -m 0644 "$HERE/classic.env" "$HERE/deathmatch.env" /etc/aetherion/
for i in classic deathmatch; do
  install -d -m 0755 "/etc/systemd/system/aetherion-server@$i.service.d"
  install -m 0644 "$HERE/$i.conf" "/etc/systemd/system/aetherion-server@$i.service.d/memory.conf"
done

# Swap: a Classic match server holds ~1.9 GB, mostly cold texture pages. 3 GB of swap lets the kernel park them instead
# of running out of memory beside the other services on this VPS. Aetherion units have a high OOMScoreAdjust, so if
# memory ever does run out, they are stopped (and restarted) before anything else.
if ! swapon --show=NAME --noheadings | grep -q .; then
  fallocate -l 3G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

install -d -m 0755 /etc/caddy/sites
install -m 0644 "$HERE/aetherion.caddy" /etc/caddy/sites/aetherion.caddy
if ! grep -q '^import /etc/caddy/sites/\*\.caddy' /etc/caddy/Caddyfile; then
  cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.before-aetherion
  printf '\n# Other sites on this server (Aetherion Project: /etc/caddy/sites/aetherion.caddy)\nimport /etc/caddy/sites/*.caddy\n' >> /etc/caddy/Caddyfile
fi
install -d -o caddy -g caddy -m 0755 /var/log/caddy
[ -f /var/log/caddy/aetherion-access.log ] || install -o caddy -g caddy -m 0640 /dev/null /var/log/caddy/aetherion-access.log
sudo -u caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

ufw allow 27415/udp comment 'Aetherion classic' >/dev/null
ufw allow 27417/udp comment 'Aetherion deathmatch' >/dev/null

systemctl daemon-reload
systemctl enable aetherion-master aetherion-server@classic aetherion-server@deathmatch >/dev/null
systemctl reload caddy
if [ -e /opt/aetherion/current ]; then
  systemctl restart aetherion-master aetherion-server@classic aetherion-server@deathmatch
fi
echo "Aetherion set up. Release: $(readlink /opt/aetherion/current 2>/dev/null || echo none yet)"
