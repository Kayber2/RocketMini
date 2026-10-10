#!/bin/bash

# ============================================================
#  Sketchbook 0.4 — Port web para dArkOS / ArkOS (RK3326)
#  Jogo: three.js + cannon.js servido por serve.py (porta 8099)
#
#  Runtime em cascata (auto-deteção):
#    1) Chromium/Firefox do sistema + display (X11/Wayland)  -> kiosk
#    2) NW.js + Weston embutidos (runtime/ copiado do MiniDayZ)
#    3) erro claro no log + no TTY
#
#  Sair do jogo: SELECT+START segurados 1.2s (ou Esc)
#  Logs: /roms/ports/sketchbook/log.txt
# ============================================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# ---- PortMaster boilerplate ----
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "$controlfolder/tasksetter" ] && source "$controlfolder/tasksetter"
get_controls

# ---- TTY (mensagens de erro na tela) ----
CUR_TTY=/dev/tty0
$ESUDO chmod 666 "$CUR_TTY" 2>/dev/null
export TERM=linux
printf "\033c" > "$CUR_TTY"

# ---- Paths ----
PORTDIR="/$directory/ports"
GAMEDIR="${PORTDIR}/sketchbook"
URL="http://127.0.0.1:8099/"
PIDFILE="/tmp/sketchbook.pids"
SERVE_LOG="${GAMEDIR}/serve.log"
LOG="${GAMEDIR}/log.txt"

[ -d "$GAMEDIR" ] || GAMEDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/sketchbook"

mkdir -p "$GAMEDIR" >/dev/null 2>&1

# ---- Log (sobrescreve a cada execução) ----
echo "=== Sketchbook Port Session $(date) ===" > "$LOG"
exec >>"$LOG" 2>&1

log() { echo "[Launcher] $*"; }
tty_msg() { echo -e "$*" > "$CUR_TTY"; }

fail() {
  log "[ERROR] $*"
  tty_msg "$1"
  sleep 6
  printf "\033c" > "$CUR_TTY"
  cleanup
  exit 1
}

# ---- Cleanup ----
BROWSER_PID=""
MNT=""
GPTKPID=""
cleanup() {
  log "[Cleanup] iniciando"
  [ -n "$BROWSER_PID" ] && kill "$BROWSER_PID" 2>/dev/null
  [ -n "$GPTKPID" ] && kill "$GPTKPID" 2>/dev/null
  pkill -f "serve.py.*8099" 2>/dev/null
  pkill -f "sketchbook/serve.py" 2>/dev/null
  $ESUDO pkill -f "gptokeyb" 2>/dev/null
  # westonwrap/nw rodam como root (via sudo): kill simples do usuário não
  # alcança - pkill -f com padrão + sudo resolve (padrão MiniDayZ)
  $ESUDO pkill -f "westonwrap.sh" 2>/dev/null
  $ESUDO pkill -f "runtime/nwjs/nw" 2>/dev/null
  $ESUDO pkill -f "run_nw_inner.sh" 2>/dev/null
  # westonwrap tem subcomando cleanup próprio (padrão MiniDayZ)
  if [ -n "$MNT" ] && [ -x "$MNT/westonwrap.sh" ]; then
    $ESUDO "$MNT/westonwrap.sh" cleanup 2>/dev/null
    $ESUDO umount "$MNT" 2>/dev/null
  fi
  rm -f "$PIDFILE" 2>/dev/null
  log "[Cleanup] ok"
}
trap cleanup EXIT

# ---- Sanity ----
log "[Paths] GAMEDIR=$GAMEDIR  directory=$directory"
[ -f "$GAMEDIR/index.html" ] || fail "index.html nao encontrado em $GAMEDIR"
[ -f "$GAMEDIR/build/sketchbook.min.js" ] || fail "build/sketchbook.min.js nao encontrado"
[ -f "$GAMEDIR/build/assets/world.glb" ] || fail "build/assets/world.glb nao encontrado"
[ -f "$GAMEDIR/serve.py" ] || fail "serve.py nao encontrado"
command -v python3 >/dev/null 2>&1 || fail "python3 ausente no sistema"
log "[Sanity] ok"

# ---- Diagnóstico de ambiente ----
log "[Env] date=$(date)"
[ -f /etc/os-release ] && source /etc/os-release && log "[Env] OS=$PRETTY_NAME"
log "[Env] arch=$(uname -m) kernel=$(uname -r)"
log "[Env] user=$USER home=$HOME"
free -h 2>/dev/null | head -4
swapon --show 2>/dev/null
log "[Env] DISPLAY=${DISPLAY:-none} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-none}"
for b in chromium chromium-browser google-chrome-stable firefox-esr Xorg Xwayland weston startx nw; do
  p=$(command -v "$b" 2>/dev/null) && log "[Env] bin $b -> $p"
done
ls -d /usr/lib/chromium* /opt/google 2>/dev/null
log "[Env] NW runtime: $(ls -la "$GAMEDIR/runtime" 2>/dev/null || echo 'ausente')"

# ---- 1) Sobe o servidor HTTP local ----
log "[Serve] iniciando serve.py na porta 8099"
python3 "$GAMEDIR/serve.py" --root "$GAMEDIR" --port 8099 --pidfile "$PIDFILE" \
  > "$SERVE_LOG" 2>&1 &
SERVE_PID=$!
echo "$SERVE_PID" >> "$PIDFILE"

# espera readiness (max 10s)
READY=0
for i in $(seq 1 50); do
  if python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('$URL/health', timeout=1).status==200 else 1)" 2>/dev/null; then
    READY=1; break
  fi
  kill -0 "$SERVE_PID" 2>/dev/null || break
  sleep 0.2
done
[ "$READY" = "1" ] || fail "serve.py nao subiu. Veja serve.log"
log "[Serve] ok (pid $SERVE_PID)"

# ---- 2) Detecta runtime ----
BROWSER_BIN=""
NW_BIN=""
for b in chromium chromium-browser google-chrome-stable firefox-esr; do
  if command -v "$b" >/dev/null 2>&1; then BROWSER_BIN="$b"; break; fi
done
[ -x "$GAMEDIR/runtime/nwjs/nw" ] && NW_BIN="$GAMEDIR/runtime/nwjs/nw"
[ -z "$NW_BIN" ] && command -v nw >/dev/null 2>&1 && NW_BIN="$(command -v nw)"
WESTON_SQUASH="$(ls "$GAMEDIR"/runtime/weston_pkg_*.squashfs 2>/dev/null | head -n1)"

# ---- Caminho A: browser do sistema + display ----
start_system_browser() {
  local GL_ARGS=()
  # no dArkOS (Mesa/Panfrost) GL default funciona; swiftshader só se pedido
  [ "${SKETCHBOOK_SWIFTSHADER:-0}" = "1" ] && GL_ARGS=(--use-gl=angle --use-angle=swiftshader)

  # ---- Firefox: flags diferentes do Chromium ----
  case "$BROWSER_BIN" in
    firefox*)
      log "[A] firefox kiosk: $BROWSER_BIN"
      mkdir -p /tmp/sketchbook-profile
      "$BROWSER_BIN" --kiosk --profile /tmp/sketchbook-profile "$URL" &
      BROWSER_PID=$!
      echo "$BROWSER_PID" >> "$PIDFILE"
      log "[A] browser pid=$BROWSER_PID"
      return 0
      ;;
  esac

  if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_SESSION_TYPE" -a "$XDG_SESSION_TYPE" = "wayland" ]; then
    log "[A] browser wayland: $BROWSER_BIN"
    "$BROWSER_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage \
      --ozone-platform=wayland "${GL_ARGS[@]}" \
      --user-data-dir=/tmp/sketchbook-profile --disk-cache-dir=/tmp/sketchbook-cache \
      --renderer-process-limit=1 --in-process-gpu --no-zygote \
      --no-first-run --disable-session-crashed-bubble \
      --autoplay-policy=no-user-gesture-required \
      --kiosk --fullscreen --start-fullscreen "$URL" &
  elif [ -n "$DISPLAY" ]; then
    log "[A] browser x11: $BROWSER_BIN DISPLAY=$DISPLAY"
    "$BROWSER_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage \
      --ozone-platform=x11 "${GL_ARGS[@]}" \
      --user-data-dir=/tmp/sketchbook-profile --disk-cache-dir=/tmp/sketchbook-cache \
      --renderer-process-limit=1 --in-process-gpu --no-zygote \
      --no-first-run --disable-session-crashed-bubble \
      --autoplay-policy=no-user-gesture-required \
      --kiosk --fullscreen --start-fullscreen "$URL" &
  else
    return 1
  fi
  BROWSER_PID=$!
  echo "$BROWSER_PID" >> "$PIDFILE"
  log "[A] browser pid=$BROWSER_PID"
  return 0
}

# ---- Caminho B: NW.js + Weston embutidos (padrão EXATO do MiniDayZ) ----
# westonwrap.sh (do squashfs) sobe weston em kiosk (drm+gl) e executa o
# runner dentro do compositor - único caminho comprovado em dArkOS real.
start_nw_weston() {
  [ -n "$WESTON_SQUASH" ] || return 1
  [ -n "$NW_BIN" ] || return 1
  local RUNNER="$GAMEDIR/run_nw_inner.sh"
  local SHIM="$GAMEDIR/runtime/libgbm_compat.aarch64.so"
  local NWAPP="$GAMEDIR/runtime/nwapp"
  [ -f "$RUNNER" ] || { log "[B] run_nw_inner.sh ausente"; return 1; }
  chmod +x "$RUNNER" 2>/dev/null
  [ -x "$RUNNER" ] || { log "[B] run_nw_inner.sh nao executavel"; return 1; }
  [ -f "$SHIM" ] || { log "[B] shim libgbm_compat ausente"; return 1; }
  [ -f "$NWAPP/package.json" ] || { log "[B] nwapp/package.json ausente"; return 1; }

  log "[B] weston squashfs: $WESTON_SQUASH"
  MNT="/tmp/sketchbook-weston"
  $ESUDO mkdir -p "$MNT"
  $ESUDO umount "$MNT" 2>/dev/null
  $ESUDO mount -o loop,ro "$WESTON_SQUASH" "$MNT" || return 1
  [ -x "$MNT/westonwrap.sh" ] || { log "[B] westonwrap.sh nao encontrado no squashfs"; $ESUDO umount "$MNT" 2>/dev/null; return 1; }

  local NWROOT
  NWROOT="$(dirname "$NW_BIN")"
  chmod +x "$RUNNER" "$NW_BIN" 2>/dev/null

  # gptokeyb2: padrão PortMaster/dArkOS de saída. Lê o gamepad no evdev
  # (independe do Gamepad API do Chromium) e no SELECT+START segurado
  # manda SIGTERM no processo "nw" - mesmo mecanismo do MiniDayZ.
  local GPTK="$GAMEDIR/sketchbook.gptk.ini"
  if [ -n "${GPTOKEYB2:-}" ] && [ -f "$GPTK" ]; then
    log "[B] gptokeyb2 (exit select+start -> SIGTERM em 'nw')"
    $GPTOKEYB2 "nw" -c "$GPTK" &
    GPTKPID=$!
  elif [ -x "$controlfolder/gptokeyb2" ] && [ -f "$GPTK" ]; then
    log "[B] gptokeyb2 direto (exit select+start -> SIGTERM em 'nw')"
    $ESUDO "$controlfolder/gptokeyb2" "nw" -c "$GPTK" &
    GPTKPID=$!
  else
    log "[B] AVISO: gptokeyb2 indisponivel - saida so via JS (SELECT+START 1.2s)"
  fi

  # runtime state do weston (MiniDayZ usa /tmp/weston_runtime)
  $ESUDO rm -rf /tmp/weston_runtime 2>/dev/null
  $ESUDO install -d -m 0700 -o root -g root /tmp/weston_runtime 2>/dev/null

  # dArkOS => GL hardware (preset *arkos* do run_nw_inner do MiniDayZ);
  # SKETCHBOOK_SWIFTSHADER=1 força software (variável passada adiante)
  log "[B] westonwrap drm gl kiosk system"
  $ESUDO env \
    SKETCHBOOK_GAMEDIR="$GAMEDIR" \
    SKETCHBOOK_NW="$NW_BIN" \
    SKETCHBOOK_NWROOT="$NWROOT" \
    SKETCHBOOK_SHIM="$SHIM" \
    SKETCHBOOK_NWAPP="$NWAPP" \
    SKETCHBOOK_GL="${SKETCHBOOK_GL:-}" \
    WRAPPED_LIBRARY_PATH="$NWROOT/lib:$NWROOT:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}" \
    "$MNT/westonwrap.sh" drm gl kiosk system WAYLAND_DISPLAY= "$RUNNER"
  WRAPRC=$?
  log "[B] westonwrap rc=$WRAPRC"
  # westonwrap é síncrono (espera o runner terminar)
  BROWSER_PID=""
  return 0
}

STARTED=0
STARTED_PATH=""
if [ -n "$BROWSER_BIN" ] && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
  if start_system_browser; then STARTED=1; STARTED_PATH="A"; fi
fi
if [ "$STARTED" = "0" ] && [ -n "$NW_BIN" ] && [ -n "$WESTON_SQUASH" ]; then
  # westonwrap é síncrono: roda em background e o watcher/`wait` cuidam do resto
  # MNT definido AQUI (não dentro da função) para o cleanup do trap enxergar
  MNT="/tmp/sketchbook-weston"
  start_nw_weston &
  STARTED=1; STARTED_PATH="B"
  BROWSER_PID=$!
  echo "$BROWSER_PID" >> "$PIDFILE"
  log "[B] westonwrap (bg) pid=$BROWSER_PID"
fi

if [ "$STARTED" = "0" ]; then
  fail "Nenhum runtime disponivel.\nRuntime embutido ausente? Confira:\n$GAMEDIR/runtime/nwjs/nw\n$GAMEDIR/runtime/weston_pkg_*.squashfs\nOu: apt install chromium (caminho A)\nVeja detect.sh e log.txt"
fi
log "[Run] caminho de runtime: $STARTED_PATH"

# ---- 3) Espera o jogo/servidor encerrar ----
log "[Run] aguardando saída (SELECT+START 1.2s no gamepad)"
tty_msg "Sketchbook em execucao\n\nSELECT+START (segurar) = sair"

# watcher: se o serve.py morrer (ex.: /exit chamado), derruba o browser
(
  while kill -0 "$SERVE_PID" 2>/dev/null; do sleep 0.5; done
  log "[Watcher] serve.py saiu; encerrando browser"
  [ -n "$BROWSER_PID" ] && kill "$BROWSER_PID" 2>/dev/null
) &
WATCH_PID=$!

wait "$BROWSER_PID" 2>/dev/null
BROWSER_RC=$?
log "[Run] browser terminou rc=$BROWSER_RC"

kill "$WATCH_PID" 2>/dev/null
[ -n "$BROWSER_PID" ] && kill "$BROWSER_PID" 2>/dev/null
kill "$SERVE_PID" 2>/dev/null
$ESUDO umount /tmp/sketchbook-weston 2>/dev/null

printf "\033c" > "$CUR_TTY"
log "[Done] fim"
exit 0
