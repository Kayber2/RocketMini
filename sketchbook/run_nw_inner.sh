#!/bin/bash
# run_nw_inner.sh — executa o NW.js DENTRO do westonwrap (caminho B do port).
# Modelo: run_nw_inner.sh do MiniDayZ (comprovado em dArkOS/RK3326 real).
# Recebe os paths via env (passados pelo Sketchbook.sh com `sudo env ...`).
set +e

NW="$SKETCHBOOK_NW"
NWROOT="$SKETCHBOOK_NWROOT"
SHIM="$SKETCHBOOK_SHIM"
NWAPP="$SKETCHBOOK_NWAPP"
NWLOG="/tmp/sketchbook-nw.log"

echo "=== SKETCHBOOK NW INNER ==="
echo "NW=$NW"
echo "NWROOT=$NWROOT"
echo "NWAPP=$NWAPP"
echo "DISPLAY=${DISPLAY:-NONE}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-NONE}"
free -h 2>/dev/null | head -3

[ -x "$NW" ] || { echo "[inner] ERRO: nw nao executavel: $NW"; exit 1; }
[ -f "$NWAPP/package.json" ] || { echo "[inner] ERRO: nwapp sem package.json: $NWAPP"; exit 1; }

# bibliotecas do NW primeiro, depois as do sistema (mesma ordem do MiniDayZ)
LD_LIBRARY_PATH="/lib:/usr/lib:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:${NWROOT}/lib:${NWROOT}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
# shim de compatibilidade gbm (obrigatorio no MiniDayZ; copiado junto)
[ -f "$SHIM" ] && export LD_PRELOAD="$SHIM${LD_PRELOAD:+:$LD_PRELOAD}"

# profile em /tmp (tmpfs - mais rapido e nao suja o SD)
PROFILE=/tmp/sketchbook-profile
CACHE=/tmp/sketchbook-cache
rm -rf "$PROFILE" "$CACHE"
mkdir -p "$PROFILE" "$CACHE"
rm -f "$PROFILE"/SingletonLock "$PROFILE"/SingletonCookie "$PROFILE"/SingletonSocket 2>/dev/null

# GL em 3 modos (toggle por arquivo vazio em $GAMEDIR ou env):
#   default     -> flags mínimas + --ignore-gpu-blocklist (padrão MiniDayZ)
#   angle       -> --use-gl=angle --use-angle=gl (ANGLE sobre Mesa/Panfrost)
#   swiftshader -> software (lento, mas funciona sem GL de hardware)
# Criar, por exemplo:  touch /roms/ports/sketchbook/gl-angle
GAMEDIR="$SKETCHBOOK_GAMEDIR"
GL_MODE="${SKETCHBOOK_GL:-}"
[ -z "$GL_MODE" ] && [ -f "$GAMEDIR/gl-angle" ] && GL_MODE="angle"
[ -z "$GL_MODE" ] && [ -f "$GAMEDIR/gl-swiftshader" ] && GL_MODE="swiftshader"
[ -z "$GL_MODE" ] && GL_MODE="default"

GL_ARGS=()
case "$GL_MODE" in
  angle)
    GL_ARGS=(--use-gl=angle --use-angle=gl --ignore-gpu-blocklist)
    ;;
  swiftshader)
    export VK_ICD_FILENAMES="${NWROOT}/lib/vk_swiftshader_icd.json"
    GL_ARGS=(--use-gl=angle --use-angle=swiftshader --ignore-gpu-blocklist --enable-unsafe-swiftshader)
    ;;
  *)
    # igual ao preset dArkOS do MiniDayZ + ignora blocklist da GPU
    # (Chromium costuma bloquear Mali/Panfrost desconhecidos => WebGL desativado)
    GL_ARGS=(--ignore-gpu-blocklist --enable-unsafe-swiftshader)
    ;;
esac
echo "[inner] GL_MODE=$GL_MODE GL_ARGS=${GL_ARGS[*]:-(nenhuma)}"

rm -f "$NWLOG"

"$NW" \
  --no-sandbox \
  --disable-gpu-sandbox \
  --disable-dev-shm-usage \
  --ozone-platform=x11 \
  "${GL_ARGS[@]}" \
  --user-data-dir="$PROFILE" \
  --disk-cache-dir="$CACHE" \
  --renderer-process-limit=1 \
  --password-store=basic \
  --in-process-gpu \
  --no-zygote \
  "$NWAPP" > "$NWLOG" 2>&1
RC=$?

echo "NW_RC=$RC"
echo "--- NW STDERR/STDOUT ---"
cat "$NWLOG" 2>/dev/null
echo "=== FIM NW INNER ==="
exit "$RC"
