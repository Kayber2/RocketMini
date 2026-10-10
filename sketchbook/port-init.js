/**
 * port-init.js — adaptador do Sketchbook para console (dArkOS / RK3326)
 *
 * Carregado ANTES de build/sketchbook.min.js no index.html do port.
 * Faz, sem mexer no código-fonte do jogo:
 *
 *  1. trava devicePixelRatio em 1 (o jogo chama setPixelRatio(window.devicePixelRatio))
 *  2. depois do World existir: desliga FXAA/sombras (perf), pointer lock (não há mouse)
 *  3. esconde o dat.gui (é interface de mouse) — reexpor com ?gui=1
 *  4. saída do jogo: SELECT+START segurados por 1.2s  ->  GET /exit no serve.py
 *     (também aceita a tecla Esc, caso exista teclado/mapeador)
 *  5. log simples em console (aparece no stderr do NW/Chromium no log.txt do port)
 *
 * Query params aceitos:
 *   ?fxaa=1     religa FXAA
 *   ?shadows=1  religa sombras
 *   ?gui=1      mostra o dat.gui
 */
(function () {
    'use strict';

    var qs = new URLSearchParams(window.location.search);
    var CFG = {
        fxaa: qs.get('fxaa') === '1',
        shadows: qs.get('shadows') === '1',
        gui: qs.get('gui') === '1'
    };

    // ---- 1. pixel ratio fixo em 1 -----------------------------------------
    try {
        Object.defineProperty(window, 'devicePixelRatio', { get: function () { return 1; } });
    } catch (e) { /* ja definido sem permissao de configuracao: ignora */ }

    function log(msg) { console.log('[port] ' + msg); }

    // ---- 4. saída: SELECT+START segurados ---------------------------------
    var EXIT_HOLD_MS = 1200;
    var holdStart = 0;
    var exiting = false;

    function requestExit(reason) {
        if (exiting) { return; }
        exiting = true;
        log('exit requested: ' + reason);
        // o serve.py mata browser/weston e responde 'bye'
        fetch('/exit').catch(function () {
            // fallback: fecha a propria janela (funciona em NW.js app)
            try { window.close(); } catch (e) { }
            setTimeout(function () { location.reload(); }, 3000);
        });
    }

    function pollExit() {
        var pads = navigator.getGamepads ? navigator.getGamepads() : [];
        var combo = false;
        for (var i = 0; i < pads.length; i++) {
            var p = pads[i];
            if (!p || !p.buttons) { continue; }
            var back = p.buttons[8] && p.buttons[8].pressed;
            var start = p.buttons[9] && p.buttons[9].pressed;
            if (back && start) { combo = true; break; }
        }
        var now = performance.now();
        if (combo) {
            if (!holdStart) { holdStart = now; }
            else if (now - holdStart >= EXIT_HOLD_MS) { requestExit('select+start hold'); }
        } else {
            holdStart = 0;
        }
        requestAnimationFrame(pollExit);
    }
    requestAnimationFrame(pollExit);

    document.addEventListener('keydown', function (e) {
        if (e.code === 'Escape') { requestExit('esc'); }
    }, false);

    // ---- 2/3. patches pós-World -------------------------------------------
    var patched = false;
    function tryPatch() {
        if (patched) { return true; }
        var w;
        try { w = (typeof world !== 'undefined') ? world : null; } catch (e) { w = null; }
        if (!w || !w.params || !w.renderer || !w.inputManager) { return false; }

        w.params.FXAA = CFG.fxaa;
        w.params.Shadows = CFG.shadows;
        w.params.Pointer_Lock = false;
        w.inputManager.setPointerLock(false);

        if (!CFG.shadows && w.sky && w.sky.csm && w.sky.csm.lights) {
            w.sky.csm.lights.forEach(function (light) { light.castShadow = false; });
        }
        if (!CFG.shadows && w.renderer) {
            w.renderer.shadowMap.enabled = false;
        }

        if (!CFG.gui) {
            // dat.gui monta .dg dentro de body
            Array.prototype.forEach.call(document.querySelectorAll('.dg'), function (el) {
                el.style.display = 'none';
            });
        }

        patched = true;
        log('patched: fxaa=' + w.params.FXAA + ' shadows=' + w.params.Shadows +
            ' gui=' + CFG.gui + ' pointerLock=false');
        return true;
    }

    var tries = 0;
    var timer = setInterval(function () {
        tries++;
        if (tryPatch() || tries > 400) { clearInterval(timer); } // ~20s max
    }, 50);

    // dat.gui e criado junto do World; garante escondida desde o cedo
    if (!CFG.gui) {
        var style = document.createElement('style');
        style.textContent = '.dg.ac { display: none !important; }';
        document.head.appendChild(style);
    }

    log('init ok (fxaa=' + CFG.fxaa + ' shadows=' + CFG.shadows + ')');
})();
