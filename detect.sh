#!/bin/bash
# detect.sh — diagnóstico rápido do console (roda no SD, devolve log.txt)
# Copie junto do Sketchbook.sh; rode:  bash detect.sh
# Ou copie só isto pro console e rode por lá.

OUT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/detect.txt"
echo "=== detect.sh $(date) ===" > "$OUT"

p() { echo "$*" >> "$OUT"; }

p "--- Sistema ---"
[ -f /etc/os-release ] && . /etc/os-release && p "OS: $PRETTY_NAME"
p "arch: $(uname -m) / kernel: $(uname -r)"
p "user: $USER / home: $HOME"

p "--- Memoria ---"
free -h >> "$OUT" 2>&1
p "swap:"; swapon --show >> "$OUT" 2>&1
for z in /sys/block/zram*; do
  [ -d "$z" ] && p "zram $(basename $z) disksize=$(cat $z/disksize 2>/dev/null)"
done

p "--- Displays ---"
p "DISPLAY=${DISPLAY:-none} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-none} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-none}"

p "--- Browsers / runtimes ---"
for b in chromium chromium-browser google-chrome-stable firefox-esr Xorg Xwayland weston westonwrap.sh startx xinit nw node python3 apt; do
  loc=$(command -v "$b" 2>/dev/null)
  if [ -n "$loc" ]; then p "OK   $b -> $loc"; else p "MISS $b"; fi
done

p "--- PortMaster ---"
for d in /opt/system/Tools/PortMaster /opt/tools/PortMaster "$HOME/.local/share/PortMaster" /roms/ports/PortMaster /roms2/ports/PortMaster; do
  [ -d "$d" ] && p "OK   $d"
done

p "--- /dev/video* e DRM ---"
ls -la /dev/dri /dev/video* 2>> "$OUT"

p "--- GPU/GL (se houver) ---"
command -v glxinfo >/dev/null && glxinfo 2>> "$OUT" | grep -i "renderer\|vendor" >> "$OUT"
command -v es2_info >/dev/null && es2_info >> "$OUT" 2>&1 | head -20
ls /usr/lib/aarch64-linux-gnu/libmali* /usr/lib/libmali* /usr/lib/aarch64-linux-gnu/dri 2>> "$OUT"

p "--- Ports existentes ---"
ls -d /roms/ports/*/ /roms2/ports/*/ 2>> "$OUT" | head -30

echo "OK - log em $OUT"
cat "$OUT"
