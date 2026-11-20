#!/usr/bin/env bash
# Repro for flutter/flutter#196863: on Wayland a Flutter window that is hidden
# and shown again stays black. Runs the app on a headless KWin, which hides and
# shows its own window, and compares a screenshot before the hide and after
# the show. Exit 0 = window renders again, exit 1 = black window.
#
#   ./check.sh                                   # stock engine
#   ./check.sh path/to/libflutter_linux_gtk.so   # a patched release engine
#
# REPRO_DELAY_MS sets the time between hide and show (default 1000, 0 = show
# directly after hide). REPRO_CYCLES sets the number of hide/show cycles.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)

if [[ ${1:-} != --inner ]]; then
    lib=${1:-}
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    (cd "$here" && flutter build linux --release > "$work/build.log" 2>&1) || { cat "$work/build.log"; exit 1; }

    bundle="$here/build/linux/x64/release/bundle"

    if [[ -n $lib ]]; then
        install -m 0755 "$lib" "$bundle/lib/libflutter_linux_gtk.so"
        echo "engine: $lib"
    else
        echo "engine: stock $(flutter --version --machine | python3 -c 'import json, sys; print(json.load(sys.stdin)["engineRevision"])')"
    fi

    mkdir -m 700 "$work/runtime"

    # The private bus starts no services: a second document portal would unmount the desktop's /run/user/<uid>/doc.
    cat > "$work/bus.conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF

    env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR="$work/runtime" \
        dbus-run-session --config-file="$work/bus.conf" -- bash "$0" --inner "$work" "$bundle/repro_196863" 2> "$work/bus.log"
    status=$?

    [[ $status != 0 && -n ${KEEP_LOGS:-} ]] && cp -r "$work" "$KEEP_LOGS"

    exit "$status"
fi

work=$2
bin=$3
socket=repro-196863-$$

centre() { convert "$1" -format '%[pixel:p{640,360}]' info:; }
shot() { WAYLAND_DISPLAY=$socket QT_QPA_PLATFORM=wayland timeout 20 spectacle -b -n -f -o "$work/$1.png" > /dev/null 2>&1; }
wait_for() { for _ in $(seq 300); do grep -q "$1" "$work/app.log" && return; sleep 0.1; done; }

KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --no-lockscreen --socket "$socket" --width 1280 --height 720 > "$work/kwin.log" 2>&1 &
kwin=$!

for _ in $(seq 50); do [[ -S $XDG_RUNTIME_DIR/$socket ]] && break; sleep 0.2; done

WAYLAND_DISPLAY=$socket GDK_BACKEND=wayland "$bin" > "$work/app.log" 2>&1 &
app=$!

wait_for 'REPRO first frame'
sleep 1
shot before

wait_for 'REPRO done'
sleep 2
shot after

kill "$app" "$kwin" 2>/dev/null
wait "$app" 2>/dev/null

before=$(centre "$work/before.png")
after=$(centre "$work/after.png")

echo "before hide: $before"
echo "after show:  $after"

if [[ $before == "$after" && $before != *"(0,0,0"* ]]; then
    echo "PASS: the window renders after hide/show"
    exit 0
fi

echo "FAIL: the window is black after hide/show"
exit 1
