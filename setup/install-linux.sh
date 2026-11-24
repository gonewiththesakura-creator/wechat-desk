#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --print-architecture | grep -qx amd64
apt-get update
apt-get install -y --no-install-recommends python3-pyatspi python3-pil xclip libpulse0 libxcb-icccm4 libxcb-keysyms1 libxcb-xinerama0 xdotool dbus-daemon gsettings-desktop-schemas libglib2.0-bin
apt-get install -y --no-install-recommends xvfb openbox x11vnc x11-utils xauth dbus-x11 novnc websockify ca-certificates locales fonts-noto-cjk libgtk-3-0t64 libnss3 libgbm1 libasound2t64 libxss1 libxkbcommon-x11-0 libxcb-cursor0 libegl1 libgl1 libgl1-mesa-dri libsecret-1-0 libnotify4 libatspi2.0-0t64 at-spi2-core /mnt/d/WeChatDesk/packages/wechat.deb
if ! id wxdesk >/dev/null 2>&1; then
    useradd -m -s /bin/bash wxdesk
fi
grep -q '^zh_CN.UTF-8 UTF-8' /etc/locale.gen || echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen zh_CN.UTF-8
install -m 755 /mnt/d/WeChatDesk/setup/desktop.sh /usr/local/bin/wechat-desk
install -m 644 /mnt/d/WeChatDesk/setup/reception.py /usr/local/lib/wechat-reception.py
install -d -m 755 /mnt/d/WeChatDesk/control
python3 -c 'import pyatspi'
test -f /usr/share/novnc/vnc.html
command -v wechat >/dev/null || test -x /usr/bin/weixin
