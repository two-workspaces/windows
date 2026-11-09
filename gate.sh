#!/usr/bin/env bash
# Railway gate in front of dockur/windows.
#
# Windows needs RAM_SIZE plus ~1 GB for QEMU, and ~30 GB of volume to download the
# installer and install. Free (0.5 GB RAM, 0.5 GB volume), Trial (1 GB) and a
# fresh Hobby volume (5 GB) don't have that, and starting anyway ends in an OOM
# kill or a failed install, which Railway counts as a failed deploy. So when the
# service is too small this serves a page that says what to change, keeps
# /healthcheck green, and starts Windows by itself once the volume is resized
# (Railway resizes volumes live). A memory change redeploys, so it's checked once.
set -u

STORAGE=/storage
NEED_DISK_GB=${MIN_VOLUME_GB:-30}
PORT=${WEB_PORT:-8006}

ram=$(numfmt --from=iec "${RAM_SIZE:-4G}" 2>/dev/null || echo $((4 * 1024 ** 3)))
need_mem=$((ram + 1024 ** 3))
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
[ "$limit" = max ] && limit=$((1 << 62))

gb() { if [ "$1" -ge $((1 << 62)) ]; then echo "no limit"; else echo "$(( ($1 + 1024 ** 3 / 2) / 1024 ** 3 )) GB"; fi; }

disk_ok() {
  # An existing install keeps running whatever the free space; only a first
  # install needs the room.
  compgen -G "$STORAGE/data.*" >/dev/null && return 0
  local size
  size=$(df -B1 --output=size "$STORAGE" 2>/dev/null | tail -1 | tr -d ' ')
  [ -n "$size" ] && [ "$size" -ge $((NEED_DISK_GB * 1024 ** 3 - 1024 ** 3)) ]
}

mem_ok() { [ "$limit" -ge "$need_mem" ]; }

if mem_ok && disk_ok; then
  exec /run/entry.sh
fi

# Too small: say why, on the service's domain.
size=$(df -B1 --output=size "$STORAGE" 2>/dev/null | tail -1 | tr -d ' ')
mkdir -p /run/gate
{
  cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30"><title>Windows: waiting for resources</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem;color:#1b1f24}
code{background:#eef1f4;padding:.1rem .3rem;border-radius:4px}li{margin:.4rem 0}.ok{color:#1a7f37}.no{color:#cf222e}</style>
</head><body><h1>Windows needs a bigger service</h1>
<p>Windows runs in an emulated PC here, so it needs more memory and disk than this service has. Nothing has been installed yet.</p><ul>
HTML
  if mem_ok; then
    echo "<li class=ok>Memory: $(gb "$limit") available, $(gb "$need_mem") needed.</li>"
  else
    echo "<li class=no>Memory: this service is limited to $(gb "$limit"), and Windows needs $(gb "$need_mem") (<code>RAM_SIZE</code> plus 1 GB). Free and Trial plans can't run it. On Hobby or Pro, raise the memory limit in the service's <b>Settings &rarr; Resource limits</b>.</li>"
  fi
  if disk_ok; then
    echo "<li class=ok>Volume: big enough.</li>"
  else
    echo "<li class=no>Volume: $(gb "${size:-0}"), and the first install needs ${NEED_DISK_GB} GB. Resize the volume on <code>/storage</code> (click it on the canvas, then <b>Settings</b>). Railway resizes it live, and this page starts Windows by itself.</li>"
  fi
  cat <<HTML
</ul><p>This page refreshes every 30 seconds.</p></body></html>
HTML
} > /run/gate/index.html

cat > /etc/nginx/sites-enabled/gate.conf <<CONF
server {
  listen $PORT default_server;
  listen [::]:$PORT default_server;
  root /run/gate;
  location = /healthcheck { return 200 "ok"; }
  location / { try_files /index.html =404; }
}
CONF
rm -f /etc/nginx/sites-enabled/default
nginx -e stderr
echo "[windows] Not starting Windows: memory limit $(gb "$limit") (need $(gb "$need_mem")), volume $(gb "${size:-0}") (need $NEED_DISK_GB GB). Serving instructions on :$PORT."

if mem_ok; then
  # Only the volume is short, and it can grow without a redeploy.
  until disk_ok; do sleep 30; done
  echo "[windows] Volume is big enough now; starting Windows."
  nginx -s quit; sleep 2
  rm -f /etc/nginx/sites-enabled/gate.conf
  exec /run/entry.sh
fi
exec sleep infinity
