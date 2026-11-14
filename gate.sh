#!/usr/bin/env bash
# Railway gate around dockur/windows. It keeps the service up and its
# /healthcheck green in every state, and says on the service's own domain why
# Windows isn't on screen:
#
#   too small   Windows needs RAM_SIZE plus room for QEMU, and ~30 GB of volume to
#               download the installer and install. Free (0.5 GB RAM, 0.5 GB
#               volume), Trial (1 GB) and Hobby (volumes capped at 5 GB, checked
#               2026-11-14) don't have that, and starting anyway ends in an OOM
#               kill or a failed install. Windows starts by itself once the
#               volume is big enough; a memory change redeploys.
#   shut down   Windows was shut down from inside. QEMU exits, and without this
#               the container would exit with it.
#   failed      QEMU kept dying. It's restarted here twice before giving up, so
#               one bad boot is not a crashed deploy.
set -u

STORAGE=${STORAGE:-/storage}
NEED_DISK_GB=${MIN_VOLUME_GB:-30}
PORT=${WEB_PORT:-8006}
GIB=$((1024 ** 3))

# Upstream compares RAM_SIZE with the cgroup's free memory, which counts the page
# cache left by the installer download: on an 8 GB service it cut a 4 GB guest to
# 2.1 GB for the first boot (2026-11-14). The check below replaces it.
export RAM_CHECK=${RAM_CHECK:-N}

ram=$(numfmt --from=iec "${RAM_SIZE:-4G}" 2>/dev/null || echo $((4 * GIB)))
# QEMU without KVM keeps up to 1 GiB of translated code besides the guest's RAM:
# with a 4 GB guest it peaked at 5458 MiB during install (2026-11-14). 2 GiB
# covers that and the helpers around it.
need_mem=$((ram + ${QEMU_OVERHEAD_MB:-2048} * 1024 * 1024))
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
[[ "$limit" =~ ^[0-9]+$ ]] || limit=$((1 << 62))

# Railway's "8 GB" is 8,000,000,000 bytes, so sizes are shown in decimal GB: a
# limit rounded down and a requirement rounded up, to match what its settings show.
gb_down() { if [ "$1" -ge $((1 << 62)) ]; then echo "no limit"; else echo "$(($1 / 1000000000)) GB"; fi; }
gb_up() { echo "$((($1 + 999999999) / 1000000000)) GB"; }
gb_near() { echo "$((($1 + 500000000) / 1000000000)) GB"; }  # a "5 GB" volume holds 4.9

vol_bytes() { df -B1 --output=size "$STORAGE" 2>/dev/null | tail -1 | tr -d ' '; }

installed() { compgen -G "$STORAGE/data.*" >/dev/null; }

disk_ok() {
  # An existing install keeps running whatever the free space; only a first
  # install needs the room.
  installed && return 0
  local size
  size=$(vol_bytes)
  [ -n "$size" ] && [ "$size" -ge $(((NEED_DISK_GB - 1) * GIB)) ]
}

mem_ok() { [ "$limit" -ge "$need_mem" ]; }

# page TITLE HEADING BODY_HTML: serve one static page on the web port, with
# /healthcheck answering 200 beside it.
page() {
  mkdir -p /run/gate /etc/nginx/sites-enabled
  cat > /run/gate/index.html <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30"><title>$1</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem;color:#1b1f24}
code{background:#eef1f4;padding:.1rem .3rem;border-radius:4px}li{margin:.4rem 0}.ok{color:#1a7f37}.no{color:#cf222e}</style>
</head><body><h1>$2</h1>
$3
<p>This page refreshes every 30 seconds.</p></body></html>
HTML
  cat > /etc/nginx/sites-enabled/gate.conf <<CONF
server {
  listen $PORT default_server;
  listen [::]:$PORT default_server;
  root /run/gate;
  add_header Cache-Control "no-store" always;
  location = /healthcheck { return 200 "ok"; }
  location / { try_files /index.html =404; }
}
CONF
  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/web.conf
  if [ -s /run/nginx.pid ] && kill -0 "$(cat /run/nginx.pid)" 2>/dev/null; then
    nginx -s reload
  else
    nginx -e stderr
  fi
}

unpage() {
  [ -f /etc/nginx/sites-enabled/gate.conf ] || return 0
  rm -f /etc/nginx/sites-enabled/gate.conf
  if [ -s /run/nginx.pid ]; then
    nginx -s quit 2>/dev/null
    for _ in $(seq 20); do kill -0 "$(cat /run/nginx.pid 2>/dev/null)" 2>/dev/null || break; sleep 0.5; done
  fi
}

# Hold the container on a page until Railway stops it.
park() {
  trap 'exit 0' TERM INT
  while :; do sleep 3600 & wait $!; done
}

too_small_page() {
  local size items
  size=$(vol_bytes)
  if mem_ok; then
    items="<li class=ok>Memory: $(gb_down "$limit") available, $(gb_up "$need_mem") needed.</li>"
  else
    items="<li class=no>Memory: this service is limited to $(gb_down "$limit"), and Windows needs $(gb_up "$need_mem") (<code>RAM_SIZE</code> plus 2 GB for the emulator). Free and Trial plans can't run it. On Hobby or Pro, raise the memory limit in the service's <b>Settings &rarr; Resource limits</b>.</li>"
  fi
  if disk_ok; then
    items+="<li class=ok>Volume: big enough.</li>"
  else
    items+="<li class=no>Volume: $(gb_near "${size:-0}"), and the first install needs ${NEED_DISK_GB} GB. Hobby volumes can't grow past 5 GB, so Windows needs a Pro plan, where volumes start at 50 GB. On Pro, resize the volume on <code>$STORAGE</code> (click it on the canvas, then <b>Settings</b>). Windows starts by itself once there's room.</li>"
  fi
  page "Windows: waiting for resources" "Windows needs a bigger service" \
    "<p>Windows runs in an emulated PC here, so it needs more memory and disk than this service has. Nothing has been installed yet.</p><ul>$items</ul>"
  echo "[windows] Not starting Windows: memory limit $(gb_down "$limit") (need $(gb_up "$need_mem")), volume $(gb_near "${size:-0}") (need $NEED_DISK_GB GB). Serving instructions on :$PORT."
}

if ! mem_ok || ! disk_ok; then
  too_small_page
  # A memory change redeploys, so only the volume can change under us.
  mem_ok || park
  trap 'exit 0' TERM INT
  until disk_ok; do sleep 30 & wait $!; done
  trap - TERM INT
  echo "[windows] Volume is big enough now; starting Windows."
fi

# The virtual disk is sparse, so a disk larger than the volume lets Windows write
# past the end of it. Unless DISK_SIZE is set, size it to the volume less room
# for the installer (64 GB at most, upstream's default).
if [ -z "${DISK_SIZE:-}" ]; then
  auto=$(vol_bytes)
  auto=$((${auto:-0} / GIB - 8))
  [ "$auto" -gt 64 ] && auto=64
  [ "$auto" -lt 20 ] && auto=20
  export DISK_SIZE="${auto}G"
fi

# Upstream marks an install as finished ($STORAGE/windows.boot) only at the first
# clean shutdown, and without the mark the next start throws the disk away and
# installs again. Railway's Restart kills the container about 10 s after SIGTERM
# whatever the draining time (2026-11-14), far too short for Windows to shut
# down, so a Windows that was never shut down from inside would be reinstalled
# over. Write the mark here instead, once Remote Desktop has answered for ten
# minutes: by then setup is long over.
rdp_up() {
  local b
  b=$(printf '\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00' \
    | timeout 8 nc -w 5 127.0.0.1 3389 2>/dev/null | head -c 1 | od -An -tx1 | tr -d ' ')
  [ "$b" = "03" ]
}

mark_installed() {
  local ok=0
  while [ ! -f "$STORAGE/windows.boot" ]; do
    sleep 30
    if rdp_up; then ok=$((ok + 1)); else ok=0; fi
    if [ "$ok" -ge 20 ] && installed; then
      touch "$STORAGE/windows.boot" && echo "[windows] Windows is installed and answering; marked the install as finished."
    fi
  done
}

# Upstream deletes the installer when it writes the mark itself. With the mark
# written above it never would, so do it before the next boot.
drop_installer() {
  [ -f "$STORAGE/windows.boot" ] || return 0
  [[ "${REMOVE:-}" == [Nn0]* ]] && return 0
  local base
  base=$(cat "$STORAGE/windows.base" 2>/dev/null)
  case "${base,,}" in *.iso) [[ "$base" != */* ]] && rm -f "$STORAGE/$base" ;; esac
  rm -f "$STORAGE/setup.img"
}

# Run Windows as a child, so its exit can be told apart: Railway stopping the
# service (pass the signal on, leave), a shutdown from inside Windows (stay up on
# a page), or QEMU dying (restart it here).
stopping=
child=
on_term() { stopping=1; [ -n "$child" ] && kill -TERM "$child" 2>/dev/null; }
trap on_term TERM INT

fails=0
while :; do
  unpage
  drop_installer
  started=$SECONDS
  /run/entry.sh &
  child=$!
  mark_installed &
  marker=$!
  rc=0
  wait "$child" || rc=$?
  # A trapped signal ends `wait` early; keep waiting for upstream's ACPI shutdown.
  while kill -0 "$child" 2>/dev/null; do rc=0; wait "$child" || rc=$?; done
  child=
  kill "$marker" 2>/dev/null
  [ -n "$stopping" ] && exit "$rc"

  if [ "$rc" -eq 0 ]; then
    echo "[windows] Windows was shut down from inside. The service stays up; restart it to boot Windows again."
    page "Windows is shut down" "Windows is shut down" \
      "<p>Windows was shut down from the Start menu, so the emulated PC is off and this service is using almost no CPU or memory. Your disk is kept on the volume.</p><p>To boot Windows again, open this service in Railway, go to <b>Deployments</b>, and choose <b>Restart</b> from the menu of the active deployment.</p>"
    park
  fi

  # A run that lasted a while was a working Windows: start counting afresh.
  [ $((SECONDS - started)) -ge 900 ] && fails=0
  fails=$((fails + 1))
  if [ "$fails" -ge 3 ]; then
    echo "[windows] Windows stopped with exit code $rc three times in a row; not retrying. See the lines above for the reason."
    page "Windows stopped" "Windows stopped unexpectedly" \
      "<p>The emulated PC exited with code $rc three times in a row, so it isn't being restarted any more. The reason is in this service's <b>Deploy Logs</b> in Railway.</p><ul><li>If the logs mention memory, raise the memory limit or lower <code>RAM_SIZE</code>.</li><li>If they mention disk space, resize the volume on <code>$STORAGE</code>.</li></ul><p>After changing a setting, or to try again as it is, restart the deployment.</p>"
    park
  fi
  echo "[windows] Windows stopped with exit code $rc; starting it again (attempt $((fails + 1)) of 3)."
  sleep 5
done
