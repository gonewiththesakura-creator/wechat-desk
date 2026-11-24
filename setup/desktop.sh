#!/bin/bash
set -euo pipefail
umask 077
export DISPLAY=:83
unset WAYLAND_DISPLAY WAYLAND_SOCKET SESSION_MANAGER
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR="/tmp/wxdesk-$(id -u)"
install -m 700 -d "$XDG_RUNTIME_DIR"
export XAUTHORITY="$XDG_RUNTIME_DIR/xauth"
export LANG=zh_CN.UTF-8
export GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1
export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
exec 9>"$XDG_RUNTIME_DIR/desktop.lock"
flock -n 9 || exit 0
keyfile="$XDG_RUNTIME_DIR/viewer-key"
passfile="$XDG_RUNTIME_DIR/vnc-pass"
children=()
cleanup() {
    for pid in "${children[@]}"; do kill "$pid" 2>/dev/null || true; done
    rm -f "$keyfile" "$passfile" "$XAUTHORITY"
}
trap cleanup EXIT
trap 'exit 0' TERM INT
touch "$XAUTHORITY"
xauth -f "$XAUTHORITY" add "$DISPLAY" . "$(mcookie)"
Xvfb "$DISPLAY" -screen 0 1100x740x24 -nolisten tcp -auth "$XAUTHORITY" &
children+=("$!")
for attempt in {1..50}; do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
xdpyinfo >/dev/null
python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(8)))' > "$keyfile"
x11vnc -storepasswd "$(cat "$keyfile")" "$passfile" >/dev/null 2>&1
x11vnc -display "$DISPLAY" -auth "$XAUTHORITY" -rfbport 15983 -rfbauth "$passfile" -listen 127.0.0.1 -no6 -forever -shared -nosel -noxdamage >/dev/null 2>&1 &
children+=("$!")
websockify --web /usr/share/novnc 127.0.0.1:16883 127.0.0.1:15983 >/dev/null 2>&1 &
children+=("$!")
dbus-run-session -- bash -c '
    set -eu
    gsettings set org.gnome.desktop.interface toolkit-accessibility true
    openbox >/dev/null 2>&1 & wm=$!
    /usr/bin/python3 /usr/local/lib/wechat-reception.py & worker=$!
    client=$(command -v wechat || command -v weixin)
    "$client" & client_pid=$!
    trap "kill $wm $worker $client_pid 2>/dev/null || true" EXIT
    wait -n "$worker" "$client_pid"
' &
children+=("$!")
wait -n "${children[@]}"
