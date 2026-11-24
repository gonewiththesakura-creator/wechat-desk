#!/bin/bash
set -eu
runtime="/tmp/wxdesk-$(id -u)"
install -m 700 -d "$runtime"
exec 8>"$runtime/keeper.lock"
flock -n 8 || exit 0
while true; do
    # Wait without disturbing a desktop that is already logged in.
    flock "$runtime/desktop.lock" true
    /usr/local/bin/wechat-desk 8>&- || true
    sleep 4
done
