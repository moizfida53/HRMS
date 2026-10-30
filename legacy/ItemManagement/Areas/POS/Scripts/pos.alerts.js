/*==============================================================================
  Areas/POS/Scripts/pos.alerts.js

  New-order alerts: a stacked toast top-right plus a ~6 second alarm.

  THE SOUND FILE
  --------------
      Areas/POS/Sounds/neworder.mp3

  Drop your own file there under that exact name and it plays instead - nothing
  else needs changing. Any format the browser supports works if you keep the
  .mp3 name, but mp3 is the safe choice across Chrome/Edge/Firefox/Safari.
  If the file is missing or will not decode, a synthesised chime is used so the
  counter is never left silent.

  Length rule: if your file is shorter than POS.sound.seconds it loops until
  that many seconds have passed; if it is longer it plays through once in full.

  Behaviour
  ---------
    * One toast per order, newest at the top, stacking downwards.
    * The alarm plays ONCE per order, never again for that invoice - a status
      change on the same order does not re-sound it.
    * Dismiss removes that toast and cuts the sound instantly.
    * Toasts that are not dismissed stay on screen indefinitely, silently.

  Background tabs
  ---------------
  A cashier will not always be looking at this tab. Two separate things have to
  be true for the alarm to fire while the tab is in the background:

    1. The poll has to keep running. Browsers throttle setInterval in hidden
       tabs to roughly once a minute, which would delay an order alert by up to
       a minute. pos.orders.js drives its poll from a Web Worker instead, whose
       timer is not throttled that way.

    2. The audio has to be allowed to start. It is - audio in a hidden tab is
       fine once the page has been interacted with at least once.

  keepAlive (POS.sound.keepAlive, default true) plays an inaudible tone so the
  tab counts as "playing audio", which exempts it from background throttling
  entirely. Cost: a speaker icon on the tab, and the machine will not idle-sleep
  while the POS is open. Set it false in the layout if that is not wanted.
==============================================================================*/
(function () {
    'use strict';

    var CFG = $.extend({
        url:           '/Areas/POS/Sounds/neworder.mp3',
        seconds:       6,
        keepAlive:     true,
        desktopNotify: false      // asks for browser permission the first time
    }, window.POS && window.POS.sound);

    var announced    = {};        // InvoiceNo -> true, so each order sounds once
    var audioBlocked = false;
    var unlocked     = false;

    // ------------------------------------------------------------- file audio
    var el = null, stopTimer = null, fadeTimer = null, fileBroken = false;

    function element() {
        if (el) return el;
        el = new Audio(CFG.url);
        el.preload = 'auto';
        // Two independent failure paths: the request 404s, or the bytes arrive
        // but will not decode. Either way fall through to the synth chime.
        el.addEventListener('error', function () { fileBroken = true; });
        return el;
    }
    // Warm the cache now so the first order is not delayed by a download.
    try { element().load(); } catch (e) { }

    function stopFile() {
        if (fadeTimer) { clearInterval(fadeTimer); fadeTimer = null; }
        if (!el) return;
        try { el.pause(); el.currentTime = 0; el.volume = 1; } catch (e) { }
    }

    function fadeOutFile() {
        // A hard pause mid-tone clicks through counter speakers.
        if (!el) return;
        if (fadeTimer) clearInterval(fadeTimer);
        fadeTimer = setInterval(function () {
            var v = el.volume - 0.15;
            if (v <= 0.02) { stopFile(); return; }
            try { el.volume = v; } catch (e) { stopFile(); }
        }, 25);
    }

    function playFile() {
        if (fileBroken) return false;
        var a = element();

        try {
            a.loop = true;                 // corrected below once duration known
            a.volume = 1;
            a.currentTime = 0;
        } catch (e) { }

        var p = a.play();
        if (p && p['catch']) {
            p['catch'](function () {
                // Autoplay refused, or the file will not decode. The synth path
                // is what raises the "sound is blocked" toast.
                audioBlocked = true;
                playSynth();
            });
        }

        // A file longer than the alarm window plays through once in full
        // rather than being cut off mid-phrase.
        var arm = function () {
            var full = a.duration && isFinite(a.duration) && a.duration >= CFG.seconds;
            a.loop = !full;
            var ms = (full ? a.duration : CFG.seconds) * 1000;
            if (stopTimer) clearTimeout(stopTimer);
            stopTimer = setTimeout(fadeOutFile, ms);
        };
        if (a.duration && isFinite(a.duration)) { arm(); }
        else {
            $(a).one('loadedmetadata', arm);
            stopTimer = setTimeout(fadeOutFile, CFG.seconds * 1000);   // safety
        }
        return true;
    }

    // ---------------------------------------------------- synthesised fallback
    var ctx = null, nodes = [], masterGain = null, synthTimer = null, keepNode = null;

    function getCtx() {
        if (ctx) return ctx;
        var C = window.AudioContext || window.webkitAudioContext;
        if (!C) return null;
        try { ctx = new C(); } catch (e) { return null; }
        return ctx;
    }

    function stopSynth() {
        if (synthTimer) { clearTimeout(synthTimer); synthTimer = null; }
        if (masterGain && ctx) {
            try {
                masterGain.gain.cancelScheduledValues(ctx.currentTime);
                masterGain.gain.setValueAtTime(masterGain.gain.value, ctx.currentTime);
                masterGain.gain.linearRampToValueAtTime(0.0001, ctx.currentTime + 0.03);
            } catch (e) { }
        }
        for (var i = 0; i < nodes.length; i++) {
            try { nodes[i].stop(ctx ? ctx.currentTime + 0.05 : 0); } catch (e) { }
            try { nodes[i].disconnect(); } catch (e) { }
        }
        nodes = [];
        masterGain = null;
    }

    function playSynth() {
        var c = getCtx();
        if (!c) { audioBlocked = true; return; }
        if (c.state === 'suspended') {
            c.resume()['catch'](function () { });
            if (c.state === 'suspended') { audioBlocked = true; return; }
        }

        stopSynth();
        masterGain = c.createGain();
        masterGain.gain.value = 0.0001;
        masterGain.connect(c.destination);

        var t0 = c.currentTime, pattern = [880, 1174.7], step = 0.8, note = 0.22;
        for (var t = 0; t < CFG.seconds; t += step) {
            for (var n = 0; n < pattern.length; n++) {
                var start = t0 + t + (n * note * 0.75);
                var osc = c.createOscillator(), g = c.createGain();
                osc.type = 'sine';
                osc.frequency.value = pattern[n];
                g.gain.setValueAtTime(0.0001, start);
                g.gain.exponentialRampToValueAtTime(0.9, start + 0.02);
                g.gain.exponentialRampToValueAtTime(0.0001, start + note);
                osc.connect(g); g.connect(masterGain);
                osc.start(start); osc.stop(start + note + 0.02);
                nodes.push(osc);
            }
        }
        masterGain.gain.setValueAtTime(0.28, t0);
        synthTimer = setTimeout(stopSynth, (CFG.seconds + 0.4) * 1000);
    }

    // --------------------------------------------------------------- keepAlive
    // An inaudible tone keeps the tab flagged as playing audio, and a tab
    // playing audio is never subjected to background timer throttling.
    function startKeepAlive() {
        if (!CFG.keepAlive || keepNode) return;
        var c = getCtx();
        if (!c || c.state === 'suspended') return;
        try {
            var osc = c.createOscillator(), g = c.createGain();
            osc.frequency.value = 30;
            g.gain.value = 0.0009;          // nonzero (so it counts) but unhearable
            osc.connect(g); g.connect(c.destination);
            osc.start();
            keepNode = osc;
        } catch (e) { }
    }

    // ----------------------------------------------------------------- unlock
    function unlock() {
        if (unlocked) return;
        unlocked = true;
        var c = getCtx();
        if (c && c.state === 'suspended') {
            c.resume().then(function () { startKeepAlive(); })['catch'](function () { });
        } else {
            startKeepAlive();
        }
        // Priming the element inside the gesture is what buys us playback in a
        // background tab later on.
        try {
            var a = element();
            a.muted = true;
            var p = a.play();
            if (p && p.then) {
                p.then(function () { a.pause(); a.currentTime = 0; a.muted = false; })
                 ['catch'](function () { a.muted = false; });
            } else { a.pause(); a.muted = false; }
        } catch (e) { }
        audioBlocked = false;
        $('.pa-blocked').remove();

        if (CFG.desktopNotify && window.Notification && Notification.permission === 'default') {
            try { Notification.requestPermission(); } catch (e) { }
        }
    }
    $(document).on('click keydown touchstart', unlock);

    // -------------------------------------------------------- alarm front door
    function stopSound() {
        if (stopTimer) { clearTimeout(stopTimer); stopTimer = null; }
        stopFile();
        stopSynth();
    }

    function playAlarm() {
        stopSound();
        if (!playFile()) { playSynth(); }
    }

    // -------------------------------------------------- attention when hidden
    var baseTitle = document.title, flashTimer = null, pending = 0;

    function startFlash() {
        pending++;
        if (flashTimer) return;
        var on = false;
        flashTimer = setInterval(function () {
            on = !on;
            document.title = on ? ('(' + pending + ') NEW ORDER') : baseTitle;
        }, 900);
    }

    function stopFlash() {
        pending = 0;
        if (flashTimer) { clearInterval(flashTimer); flashTimer = null; }
        document.title = baseTitle;
    }
    $(document).on('visibilitychange', function () { if (!document.hidden) stopFlash(); });

    function desktopNotify(o) {
        if (!CFG.desktopNotify || !window.Notification) return;
        if (Notification.permission !== 'granted') return;
        try {
            var n = new Notification('New Order #' + o.InvoiceNo, {
                body: (o.CustomerName || '') + '\n' +
                      [o.Mobile, o.AreaName].filter(function (x) { return x; }).join(' - '),
                tag: 'pos-order-' + o.InvoiceNo
            });
            n.onclick = function () { window.focus(); n.close(); };
        } catch (e) { }
    }

    // ----------------------------------------------------------------- toasts
    function esc(s) {
        if (s === null || s === undefined) return '';
        return String(s).replace(/[&<>"']/g, function (ch) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
        });
    }

    function container() {
        var $c = $('#posAlerts');
        if (!$c.length) $c = $('<div id="posAlerts" aria-live="polite"></div>').appendTo('body');
        return $c;
    }

    function addToast(o) {
        var inv    = o.InvoiceNo;
        var name   = o.CustomerName || '-';
        var mobile = o.Mobile || '';
        var area   = o.AreaName || (o.OrderTypeName || '');

        // Mobile and area share a line; keep the separator out when one is
        // missing so a pickup order does not print a stray dash.
        var line3 = [esc(mobile), esc(area)].filter(function (x) { return x; })
                                            .join(' &nbsp;&middot;&nbsp; ');

        var $t = $(
            '<div class="pa-toast" data-inv="' + esc(inv) + '" role="alert">' +
              '<div class="pa-head">' +
                '<span class="pa-title">New Order Arrived</span>' +
                '<span class="pa-inv">#' + esc(inv) + '</span>' +
              '</div>' +
              '<div class="pa-body">' +
                '<div class="pa-name">' + esc(name) + '</div>' +
                (line3 ? '<div class="pa-meta">' + line3 + '</div>' : '') +
              '</div>' +
              '<button type="button" class="pa-dismiss">Dismiss</button>' +
            '</div>');

        // Newest first: the order a cashier needs is the one that just landed.
        container().prepend($t);

        $t.on('click', function (e) {
            if ($(e.target).closest('.pa-dismiss').length) return;
            if (window.POS && typeof POS.openDrawer === 'function') POS.openDrawer(inv);
        });

        $t.find('.pa-dismiss').on('click', function (e) {
            e.stopPropagation();
            stopSound();                    // instantly, as required
            $t.addClass('pa-out');
            setTimeout(function () { $t.remove(); }, 160);
        });

        if (audioBlocked && !$('.pa-blocked').length) {
            container().prepend(
                '<div class="pa-toast pa-blocked">' +
                  '<div class="pa-body">Sound is blocked by the browser. ' +
                  'Click anywhere on this page once to enable it.</div>' +
                '</div>');
        }
    }

    // ------------------------------------------------------------------- API
    window.POSAlerts = {
        /**
         * Announce new orders. Rows already announced are ignored, so the
         * alarm sounds once per order however many times the poll returns it.
         */
        notify: function (orders) {
            if (!orders || !orders.length) return;

            var fresh = [];
            for (var i = 0; i < orders.length; i++) {
                var o = orders[i];
                if (!o || !o.IsNewOrder) continue;
                var key = String(o.InvoiceNo);
                if (announced[key]) continue;
                announced[key] = true;
                fresh.push(o);
            }
            if (!fresh.length) return;

            for (var j = 0; j < fresh.length; j++) {
                addToast(fresh[j]);
                if (document.hidden) { startFlash(); desktopNotify(fresh[j]); }
            }

            // One alarm for the batch. Two orders landing together should not
            // stack two overlapping sounds.
            playAlarm();
        },

        // Console helper: POSAlerts.test() - proves the file plays and the
        // toast renders without waiting for a real order.
        test: function () {
            playAlarm();
            addToast({ InvoiceNo: 'TEST', CustomerName: 'Test Customer',
                       Mobile: '99000000', AreaName: 'Salmiya' });
        },

        stopSound: stopSound,

        dismissAll: function () {
            stopSound();
            stopFlash();
            $('#posAlerts').empty();
        }
    };
})();
