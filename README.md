# Sketchbook 0.4 — Port para dArkOS / ArkOS (RG351MP, RX6H, RK3326)

Port do jogo web **Sketchbook** (three.js + cannon.js) para rodar em tela cheia
no console, com gamepad e saída limpa pro EmulationStation.

## Instalação (SD com dArkOS)

1. Extraia o ZIP **na raiz do partition de ROMs** (`/roms` ou `/roms2`), ficando:

```
/roms/ports/Sketchbook.sh
/roms/ports/sketchbook/            (index.html, build/, serve.py, port-init.js)
/roms/ports/sketchbook/runtime/    (NW.js + Weston embutidos, ~560 MB)
/roms/ports/detect.sh              (opcional, diagnóstico)
```

2. No console: **Options → Ports → Sketchbook**.

> O ZIP é grande (~560 MB) porque o runtime NW.js+Weston já vem embutido
> (copiado do port MiniDayZ, comprovado em dArkOS/RK3326 real).

## Sair do jogo

**SELECT + START segurados por ~1,2 s** (ou tecla Esc).
Isso chama `GET /exit` no `serve.py`, que derruba o browser/weston e volta ao ES.

## Runtime (auto-detectado pelo launcher)

| Cascata | O que procura | Status |
|---|---|---|
| A (leve) | `chromium`/`firefox-esr` + `DISPLAY`/`WAYLAND_DISPLAY` | dArkOS **não tem** browser/X (confirmado no detect) |
| B (padrão) | `sketchbook/runtime/nwjs/nw` + `weston_pkg_*.squashfs` | **embutido no ZIP**, único caminho comprovado |
| Erro | — | instrução no TTY e em `log.txt` |

Caminho B segue o padrão exato do MiniDayZ: `westonwrap.sh drm gl kiosk system`
+ NW.js com `--in-process-gpu --no-zygote` (economia de RAM em 1 GB) e
GL de hardware (Mesa/Panfrost do dArkOS).

## Diagnóstico

```bash
cd /roms/ports
bash detect.sh          # gera detect.txt
cat sketchbook/log.txt  # log da última execução
cat sketchbook/serve.log
```

Envie `detect.txt` + `log.txt` para análise remota.

## Parâmetros de URL (opcionais)

No `index.html` do port, acrescente na URL do jogo:

- `?fxaa=1` — religa FXAA (desligado por padrão no port, performance)
- `?shadows=1` — religa sombras CSM (desligado por padrão no port)
- `?gui=1` — mostra o dat.gui (escondido por padrão, é interface de mouse)

Ex.: `http://127.0.0.1:8099/?shadows=1` (no launcher, variável `URL`).

## O que foi alterado em relação ao jogo original

- `index.html`: fontes Google removidas (offline), `viewport` adicionado,
  `port-init.js` carregado antes do bundle.
- `port-init.js`: pixel ratio travado em 1, FXAA/sombras desligados por default,
  pointer lock desligado, dat.gui escondido, combo de saída SELECT+START.
- `serve.py`: servidor estático com MIME `.glb`, sem cache, `/health` e `/exit`.
- Nenhum arquivo de `src/` ou do `build/` original foi modificado.

## Performance (RK3326 / Mali (Panfrost) / 1 GB RAM)

- zram **já está ativo** no dArkOS (767 Mi, confirmado no detect.txt).
- FXAA e sombras já vêm desligados (port-init.js); religue só com
  `?fxaa=1` / `?shadows=1` se o fps aguentar.
- Se travar com OOM: defina `SKETCHBOOK_SWIFTSHADER=1` antes de lançar
  (troca GL de hardware por SwiftShader - muito mais lento, mas cabe em RAM).
- Logs adicionais do NW: `/tmp/sketchbook-nw.log` (também copiado para o log.txt do port).

## Créditos

- Jogo: [swift502/Sketchbook](https://github.com/swift502/Sketchbook) (MIT)
- Padrão de port: PortMaster + referências dos ports MiniDayZ, Counter-Strike,
  Dead Trigger e Huntdown (pasta `Desktop\Ports`)
