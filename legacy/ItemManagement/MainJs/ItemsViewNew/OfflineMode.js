/*=============================================================================
  OfflineMode.js - "Offline" / "Online" switch for the customer landing page

  UI (Views/ItemsViewNew/Header.cshtml)
    #liOfflineMode     side-menu link. Reads "Offline" while online; once
                       offline mode is on it reads "Online" (click = go back).
    #btnOfflineSync    sync icon next to the cart, visible ONLY in offline mode.

  Cookies (path=/, 1 year)
    QRMenuOfflineMode  "1" = offline mode on, "0"/absent = normal online menu.
    QRMenuOfflineSync  t=<epoch ms>&b=<brand>&r=<branch>&c=<categories>&i=<items>&m=<media>
                       written after every successful sync (last-synced info).
    The menu DATA itself lives in the Cache Storage of /offline-sw.js - a
    cookie holds ~4 KB, a menu with photos and videos holds megabytes.

  Flow
    Offline click -> cookie=1 -> register /offline-sw.js -> SYNC_BEGIN ->
    reload (every request of the fresh page is written to the new cache) ->
    crawl every category, item, extra/choice list, image gallery, photo,
    video, allergen icon, css background and font -> SYNC_COMMIT -> sync
    cookie updated. The Sync icon repeats the same from SYNC_BEGIN.
    Online click -> cookie=0 -> caches deleted -> worker unregistered -> reload.

  Needs HTTPS (or localhost): browsers only allow service workers there.
=============================================================================*/
var OfflineMode = (function (window, document, $) {
    'use strict';

    var COOKIE_MODE = 'QRMenuOfflineMode';
    var COOKIE_SYNC = 'QRMenuOfflineSync';
    var PENDING_KEY = 'qrmenu-offline-sync-pending';
    var REPAIR_KEY = 'qrmenu-offline-repair';
    var CACHE_PREFIX = 'qrmenu-offline-';
    var INSTALLED_KEY = 'TMMAppInstalled';    // cookie + localStorage flag
    var cfg = window.OfflineModeConfig || {};
    var SW_URL = cfg.swUrl || '/offline-sw.js';
    var CONCURRENCY = 6;
    var MEDIA_RX = /\.(png|jpe?g|gif|webp|svg|bmp|avif|ico|mp4|webm|ogg|ogv|mov|m4v)(\?.*)?$/i;

    var busy = false;

    /* ------------------------------------------------------------ text -- */
    var TEXT = {
        EN: {
            offline: 'Offline',
            online: 'Online',
            syncTitle: 'Sync latest menu',
            lastSynced: 'Last synced',
            never: 'never',
            enableTitle: 'Switch to Offline Mode?',
            enableMsg: 'The whole menu - categories, items, photos, videos and theme - will be downloaded to this device so it keeps working without internet. This can take a minute on large menus.',
            disableTitle: 'Switch back to Online?',
            disableMsg: 'The offline copy of the menu will be removed from this device and the live menu will load.',
            disableNoNet: 'This device seems to have no internet connection. If you switch to Online now the menu will not load until the connection is back. Continue?',
            yes: 'Yes', cancel: 'Cancel', ok: 'OK',
            preparing: 'Preparing offline menu',
            preparingMsg: 'Getting the latest menu from the server...',
            downloading: 'Saving menu for offline use',
            downloadingMsg: 'Please keep this page open.',
            menuData: 'Menu data',
            media: 'Photos & videos',
            done: 'Menu is ready offline',
            synced: 'Menu synced',
            failed: 'Could not save the menu for offline use. Please check the connection and try again.',
            partial: 'Some photos or videos could not be downloaded',
            noNet: 'No internet connection. Showing the saved menu - try syncing again once you are online.',
            unsupported: 'Offline Mode is not available on this browser or connection. It needs a modern browser and a secure (https) address.',
            switchingOnline: 'Switching to the live menu...',
            installTitle: 'Install the TMM app?',
            installMsg: 'Add TMM to this device as an app. It opens straight into this menu, full screen, and works offline - ideal for Guided Access.',
            installBtn: 'Install',
            later: 'Not now',
            iosInstallMsg: 'To add TMM as an app: tap the Share button in Safari, then "Add to Home Screen". Open the menu from the new TMM icon and switch Offline Mode on there too.'
        },
        AR: {
            offline: 'غير متصل',
            online: 'متصل',
            syncTitle: 'مزامنة أحدث قائمة',
            lastSynced: 'آخر مزامنة',
            never: 'أبداً',
            enableTitle: 'التبديل إلى الوضع غير المتصل؟',
            enableMsg: 'سيتم تنزيل القائمة كاملة - الأقسام والأصناف والصور والفيديوهات والتصميم - على هذا الجهاز لتعمل بدون إنترنت. قد يستغرق ذلك دقيقة للقوائم الكبيرة.',
            disableTitle: 'العودة إلى الوضع المتصل؟',
            disableMsg: 'سيتم حذف النسخة المحفوظة من القائمة على هذا الجهاز وتحميل القائمة المباشرة.',
            disableNoNet: 'يبدو أن الجهاز غير متصل بالإنترنت. إذا انتقلت إلى الوضع المتصل الآن فلن تظهر القائمة حتى يعود الاتصال. هل تريد المتابعة؟',
            yes: 'نعم', cancel: 'إلغاء', ok: 'حسناً',
            preparing: 'تجهيز القائمة للعمل بدون إنترنت',
            preparingMsg: 'جاري جلب أحدث قائمة من الخادم...',
            downloading: 'حفظ القائمة للعمل بدون إنترنت',
            downloadingMsg: 'يرجى إبقاء هذه الصفحة مفتوحة.',
            menuData: 'بيانات القائمة',
            media: 'الصور والفيديوهات',
            done: 'القائمة جاهزة بدون إنترنت',
            synced: 'تمت مزامنة القائمة',
            failed: 'تعذر حفظ القائمة للعمل بدون إنترنت. يرجى التحقق من الاتصال والمحاولة مرة أخرى.',
            partial: 'تعذر تنزيل بعض الصور أو الفيديوهات',
            noNet: 'لا يوجد اتصال بالإنترنت. يتم عرض القائمة المحفوظة - حاول المزامنة مرة أخرى عند الاتصال.',
            unsupported: 'الوضع غير المتصل غير متاح على هذا المتصفح أو الاتصال. يتطلب متصفحاً حديثاً وعنواناً آمناً (https).',
            switchingOnline: 'جاري التبديل إلى القائمة المباشرة...',
            installTitle: 'تثبيت تطبيق TMM؟',
            installMsg: 'أضف TMM إلى هذا الجهاز كتطبيق. يفتح مباشرة على هذه القائمة بملء الشاشة ويعمل بدون إنترنت - مثالي لوضع الوصول الموجّه.',
            installBtn: 'تثبيت',
            later: 'ليس الآن',
            iosInstallMsg: 'لإضافة TMM كتطبيق: اضغط زر المشاركة في Safari ثم "إضافة إلى الشاشة الرئيسية". افتح القائمة من أيقونة TMM الجديدة وفعّل الوضع غير المتصل هناك أيضاً.'
        }
    };

    function lang() { return $('#selectedLang').val() === 'AR' ? 'AR' : 'EN'; }
    function t(key) { return TEXT[lang()][key] || TEXT.EN[key] || key; }

    /* --------------------------------------------------------- cookies -- */
    function setCookie(name, value, days) {
        var c = name + '=' + encodeURIComponent(value) + '; path=/; SameSite=Lax';
        if (days) { c += '; max-age=' + Math.round(days * 86400); }
        if (location.protocol === 'https:') { c += '; Secure'; }
        document.cookie = c;
    }
    function getCookie(name) {
        var m = document.cookie.match(new RegExp('(?:^|;\\s*)' + name.replace(/[.$?*|{}()[\]\\/+^]/g, '\\$&') + '=([^;]*)'));
        return m ? decodeURIComponent(m[1]) : null;
    }
    function deleteCookie(name) {
        document.cookie = name + '=; path=/; max-age=0; SameSite=Lax';
    }
    function parseSyncCookie() {
        var raw = getCookie(COOKIE_SYNC), out = {};
        if (!raw) { return null; }
        raw.split('&').forEach(function (p) {
            var kv = p.split('=');
            out[kv[0]] = decodeURIComponent(kv[1] || '');
        });
        return out;
    }

    function isOn() { return getCookie(COOKIE_MODE) === '1'; }

    function supported() {
        return 'serviceWorker' in navigator && 'caches' in window &&
            window.isSecureContext !== false && !!window.fetch && !!window.Promise;
    }

    /* -------------------------------------------------------------- UI -- */
    function applyUi() {
        var on = isOn();
        $('body').toggleClass('qr-offline-mode', on);
        $('#menu_OfflineLabel').text(on ? t('online') : t('offline'));
        $('#liOfflineMode a')
            .attr('title', on ? t('online') : t('offline'))
            .find('i.fa').toggleClass('fa-globe', on).toggleClass('fa-cloud-download', !on);

        var $sync = $('#btnOfflineSync');
        $sync.toggleClass('d-none', !on);
        var info = parseSyncCookie();
        var when = info && info.t ? new Date(parseInt(info.t, 10)).toLocaleString() : t('never');
        $sync.attr('title', t('syncTitle') + ' - ' + t('lastSynced') + ': ' + when)
            .attr('aria-label', t('syncTitle'));
        updateConnectivity();
    }

    function updateConnectivity() {
        $('#btnOfflineSync').toggleClass('is-disconnected', navigator.onLine === false);
    }

    function setSpinning(on) {
        $('#btnOfflineSync').toggleClass('is-syncing', on).find('.fa').toggleClass('fa-spin', on);
    }

    function overlay(title, msg) {
        var $o = $('#qrOfflineOverlay');
        if (!$o.length) {
            $o = $(
                '<div id="qrOfflineOverlay" class="qr-offline-overlay" role="dialog" aria-modal="true" aria-live="polite">' +
                '  <div class="qr-offline-card">' +
                '    <div class="qr-offline-icon"><i class="fa fa-cloud-download" aria-hidden="true"></i></div>' +
                '    <h5 class="qr-offline-title"></h5>' +
                '    <p class="qr-offline-msg"></p>' +
                '    <div class="qr-offline-step"><span class="qr-offline-step-label"></span><span class="qr-offline-count"></span></div>' +
                '    <div class="progress qr-offline-progress">' +
                '      <div class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width:100%"></div>' +
                '    </div>' +
                '  </div>' +
                '</div>');
            $('body').append($o);
        }
        $o.find('.qr-offline-title').text(title);
        $o.find('.qr-offline-msg').text(msg || '');
        $o.find('.qr-offline-step-label, .qr-offline-count').text('');
        $o.find('.progress-bar').css('width', '100%');
        $('body').addClass('qr-offline-busy');
        $o.addClass('show');
    }

    function overlayProgress(label, done, total) {
        var $o = $('#qrOfflineOverlay');
        $o.find('.qr-offline-step-label').text(label);
        $o.find('.qr-offline-count').text(total ? (done + ' / ' + total) : (done ? String(done) : ''));
        $o.find('.progress-bar').css('width', total ? Math.round(done * 100 / total) + '%' : '100%');
    }

    function hideOverlay() {
        $('#qrOfflineOverlay').removeClass('show');
        $('body').removeClass('qr-offline-busy');
    }

    function toast(message, kind) {
        var $t = $('<div class="qr-offline-toast" role="status"></div>')
            .addClass('qr-offline-toast-' + (kind || 'info'))
            .append($('<i class="fa" aria-hidden="true"></i>').addClass(
                kind === 'success' ? 'fa-check-circle' : kind === 'error' ? 'fa-exclamation-circle' : 'fa-info-circle'))
            .append($('<span></span>').text(message));
        $('body').append($t);
        setTimeout(function () { $t.addClass('show'); }, 20);
        setTimeout(function () {
            $t.removeClass('show');
            setTimeout(function () { $t.remove(); }, 400);
        }, kind === 'error' ? 6000 : 4000);
    }

    function confirmBox(title, msg, onYes) {
        if ($.confirm) {
            $.confirm({
                title: title, content: msg, rtl: lang() === 'AR', backgroundDismiss: true,
                buttons: {
                    yes: { text: t('yes'), btnClass: 'btn-primary', action: onYes },
                    cancel: { text: t('cancel') }
                }
            });
        } else if (window.confirm(title + '\n\n' + msg)) {
            onYes();
        }
    }

    function alertBox(msg) {
        if ($.alert) { $.alert({ title: '', content: msg, rtl: lang() === 'AR' }); }
        else { window.alert(msg); }
    }

    /* -------------------------------------------------- service worker -- */
    function register() {
        return navigator.serviceWorker.register(SW_URL, { scope: '/' })
            .then(function () { return navigator.serviceWorker.ready; });
    }

    function ourRegistration() {
        if (!('serviceWorker' in navigator)) { return Promise.resolve(null); }
        return navigator.serviceWorker.getRegistrations().then(function (regs) {
            for (var i = 0; i < regs.length; i++) {
                var w = regs[i].active || regs[i].waiting || regs[i].installing;
                if (w && w.scriptURL.indexOf('offline-sw.js') !== -1) { return regs[i]; }
            }
            return null;
        }).catch(function () { return null; });
    }

    function send(type) {
        return navigator.serviceWorker.ready.then(function (reg) {
            var sw = navigator.serviceWorker.controller || reg.active;
            if (!sw) { throw new Error('No active service worker'); }
            return new Promise(function (resolve, reject) {
                var ch = new MessageChannel();
                var timer = setTimeout(function () { reject(new Error('Service worker timeout')); }, 20000);
                ch.port1.onmessage = function (e) {
                    clearTimeout(timer);
                    if (e.data && e.data.ok) { resolve(e.data.result); }
                    else { reject(new Error((e.data && e.data.error) || 'Service worker error')); }
                };
                sw.postMessage({ type: type }, [ch.port2]);
            });
        });
    }

    function clearAndUnregister() {
        var clear = ('caches' in window) ? caches.keys().then(function (keys) {
            return Promise.all(keys.filter(function (k) { return k.indexOf(CACHE_PREFIX) === 0; })
                .map(function (k) { return caches.delete(k); }));
        }) : Promise.resolve();
        return clear.catch(function () { }).then(ourRegistration).then(function (reg) {
            return reg ? reg.unregister() : false;
        }).catch(function () { });
    }

    function startSyncAndReload() {
        return send('SYNC_BEGIN').then(function () {
            try { sessionStorage.setItem(PENDING_KEY, '1'); } catch (e) { }
            location.reload();
        });
    }

    /* ---------------------------------------------------- install offer -- */
    // The install prompt is offered ONLY as part of switching Offline Mode on:
    // Index.cshtml emits the manifest only while the cookie is set and cancels
    // the browser's own banner (window.__tmmInstallPrompt keeps the event).
    function isStandalone() {
        return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
            (window.matchMedia && window.matchMedia('(display-mode: fullscreen)').matches) ||
            window.navigator.standalone === true;
    }

    function isIos() {
        return /iPad|iPhone|iPod/.test(navigator.userAgent) ||
            (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    }

    /*  "Installed" flag - once the TMM app is installed on this device the
        offer never shows again. Kept in BOTH a cookie and localStorage; either
        one is enough, so the offer only comes back after the browser's
        cookies/site data are cleared and the menu is opened again.        */
    function isInstalledFlag() {
        if (getCookie(INSTALLED_KEY) === '1') { return true; }
        try { return localStorage.getItem(INSTALLED_KEY) === '1'; } catch (e) { return false; }
    }

    function markInstalled() {
        setCookie(INSTALLED_KEY, '1', 3650);
        try { localStorage.setItem(INSTALLED_KEY, '1'); } catch (e) { }
    }

    function offerInstall() {
        if (!isOn() || isStandalone() || isInstalledFlag()) { return; }
        var ask = function () {
            var evt = window.__tmmInstallPrompt;
            if (!evt) { return false; }
            confirmBox(t('installTitle'), t('installMsg'), function () {
                window.__tmmInstallPrompt = null;
                evt.prompt();
                if (evt.userChoice) {
                    evt.userChoice.then(function (choice) {
                        if (choice && choice.outcome === 'accepted') { markInstalled(); }
                    }).catch(function () { });
                }
            });
            return true;
        };
        if (ask()) { return; }
        if (isIos()) {
            // Safari has no install API and cannot tell whether "Add to Home
            // Screen" was used, so the instructions are shown once and flagged.
            if ($.alert) { $.alert({ title: t('installTitle'), content: t('iosInstallMsg'), rtl: lang() === 'AR' }); }
            markInstalled();
            return;
        }
        // Chrome may still be evaluating the manifest - offer when it is ready.
        $(document).one('tmm:installable', function () { ask(); });
    }

    /* ---------------------------------------------------------- actions -- */
    function toggle() {
        if (busy) { return; }
        if (isOn()) { goOnline(); } else { goOffline(); }
    }

    function goOffline() {
        if (!supported()) { alertBox(t('unsupported')); return; }
        if (navigator.onLine === false) { alertBox(t('noNet')); return; }
        confirmBox(t('enableTitle'), t('enableMsg'), function () {
            busy = true;
            overlay(t('preparing'), t('preparingMsg'));
            setCookie(COOKIE_MODE, '1', 365);
            if (navigator.storage && navigator.storage.persist) {
                navigator.storage.persist().catch(function () { });
            }
            register().then(startSyncAndReload).catch(function (err) {
                if (window.console) { console.error('[OfflineMode] enable failed', err); }
                setCookie(COOKIE_MODE, '0', 365);
                clearAndUnregister();
                busy = false;
                hideOverlay();
                applyUi();
                alertBox(t('failed'));
            });
        });
    }

    function goOnline() {
        var proceed = function () {
            busy = true;
            overlay(t('switchingOnline'), '');
            setCookie(COOKIE_MODE, '0', 365);
            deleteCookie(COOKIE_SYNC);
            clearAndUnregister().then(function () { location.reload(); });
        };
        if (navigator.onLine === false) { confirmBox(t('disableTitle'), t('disableNoNet'), proceed); }
        else { confirmBox(t('disableTitle'), t('disableMsg'), proceed); }
    }

    function sync() {
        if (busy || !isOn()) { return; }
        if (!supported()) { alertBox(t('unsupported')); return; }
        if (navigator.onLine === false) { toast(t('noNet'), 'error'); return; }
        busy = true;
        setSpinning(true);
        overlay(t('preparing'), t('preparingMsg'));
        ourRegistration().then(function (reg) {
            return reg ? navigator.serviceWorker.ready : register();
        }).then(startSyncAndReload).catch(function (err) {
            if (window.console) { console.error('[OfflineMode] sync failed', err); }
            busy = false;
            setSpinning(false);
            hideOverlay();
            alertBox(t('failed'));
        });
    }

    /* ---------------------------------------------------- warm-up crawl -- */

    // The page's own first calls (categories, labels, landing items) have
    // already been cached by the reload; wait until they are finished.
    function waitForPageIdle() {
        return new Promise(function (resolve) {
            var start = Date.now(), quietSince = 0;
            (function tick() {
                var active = ($.active || 0) > 0 || document.readyState !== 'complete';
                if (!active) {
                    quietSince = quietSince || Date.now();
                    if (Date.now() - quietSince >= 800) { resolve(); return; }
                } else {
                    quietSince = 0;
                }
                if (Date.now() - start > 20000) { resolve(); return; }
                setTimeout(tick, 200);
            })();
        });
    }

    function postJson(url, body) {
        return fetch(url, {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Requested-With': 'XMLHttpRequest' },
            body: body === undefined ? undefined : JSON.stringify(body)
        }).then(function (r) { return r.json(); });
    }

    function asArray(v) {
        if (Array.isArray(v)) { return v; }
        if (typeof v === 'string' && v.length && (v.charAt(0) === '[' || v.charAt(0) === '{')) {
            try { var p = JSON.parse(v); return Array.isArray(p) ? p : [p]; } catch (e) { }
        }
        return [];
    }

    function folderFor(key) {
        switch (key) {
            case 'IMAGENAME': case 'ImageName': case 'Imagename': case 'imageName':
                return ['/images/', '/ThumbnailImages/'];
            case 'Video': case 'VideoName': case 'VIDEONAME': case 'video':
                return ['/Video/'];
            case 'image':
                return ['/allergenImages/'];
            case 'branchImg':
                return ['/Images/', '/ThumbnailImages/'];
        }
        if (/image|img|logo|banner|photo/i.test(key)) { return ['/images/', '/ThumbnailImages/']; }
        if (/video/i.test(key)) { return ['/Video/']; }
        return null;
    }

    // Walk any API payload and turn file names into the exact URLs the menu
    // markup builds ("../../ThumbnailImages/" + name resolves to /ThumbnailImages/name).
    function collectMedia(obj, media, depth) {
        depth = depth || 0;
        if (!obj || depth > 6) { return; }
        if (Array.isArray(obj)) {
            obj.forEach(function (x) { collectMedia(x, media, depth + 1); });
            return;
        }
        if (typeof obj !== 'object') { return; }
        Object.keys(obj).forEach(function (k) {
            var v = obj[k];
            if (typeof v === 'string') {
                var name = v.trim();
                if (!name || !MEDIA_RX.test(name)) {
                    if (name.charAt(0) === '[') { collectMedia(asArray(name), media, depth + 1); }
                    return;
                }
                if (/^(https?:)?\/\//i.test(name) || name.charAt(0) === '/') {
                    addUrl(media, name);
                    return;
                }
                var folders = folderFor(k);
                if (folders) { folders.forEach(function (f) { addUrl(media, f + name); }); }
            } else if (v && typeof v === 'object') {
                collectMedia(v, media, depth + 1);
            }
        });
    }

    function addUrl(set, url, base) {
        if (!url || /^(data|blob|javascript|about):/i.test(url)) { return; }
        try { set[new URL(url, base || location.href).href] = true; } catch (e) { }
    }

    // Everything the rendered page/theme references that is not loaded yet:
    // other-language stylesheets, css background images, fonts, banners.
    function collectFromDocument(media) {
        $('img[src], video[src], video[poster], source[src], link[rel~="icon"][href], input[type="image"][src]').each(function () {
            addUrl(media, this.getAttribute('src') || this.getAttribute('href'));
            if (this.getAttribute('poster')) { addUrl(media, this.getAttribute('poster')); }
        });
        $('img[srcset]').each(function () {
            this.getAttribute('srcset').split(',').forEach(function (s) { addUrl(media, s.trim().split(/\s+/)[0]); });
        });
        $('[style*="url("]').each(function () { addCssUrls(media, this.getAttribute('style'), location.href); });
        if (window.AssetUrls) {
            Object.keys(window.AssetUrls).forEach(function (k) { addUrl(media, window.AssetUrls[k]); });
        }
        addUrl(media, '/allergenImages/assign_allergen.png');

        var walk = function (rules, base) {
            for (var i = 0; rules && i < rules.length; i++) {
                var r = rules[i];
                if (r.cssRules) { walk(r.cssRules, base); }
                if (r.styleSheet) { try { walk(r.styleSheet.cssRules, r.styleSheet.href || base); } catch (e) { } }
                if (r.cssText && r.cssText.indexOf('url(') !== -1) { addCssUrls(media, r.cssText, base); }
            }
        };
        for (var s = 0; s < document.styleSheets.length; s++) {
            var sheet = document.styleSheets[s];
            try { walk(sheet.cssRules, sheet.href || location.href); } catch (e) { /* cross-origin sheet */ }
        }
    }

    function addCssUrls(media, text, base) {
        var rx = /url\(\s*(['"]?)([^'")]+)\1\s*\)/g, m;
        while ((m = rx.exec(text || ''))) {
            if (m[2].charAt(0) !== '#') { addUrl(media, m[2], base); }
        }
    }

    function runPool(items, worker, onProgress) {
        var i = 0, done = 0, failed = 0;
        return new Promise(function (resolve) {
            if (!items.length) { resolve({ done: 0, failed: 0 }); return; }
            var next = function () {
                if (i >= items.length) { return; }
                var item = items[i++];
                Promise.resolve().then(function () { return worker(item); }).then(function (ok) {
                    if (ok === false) { failed++; }
                }, function () { failed++; }).then(function () {
                    done++;
                    if (onProgress) { onProgress(done, items.length); }
                    if (done === items.length) { resolve({ done: done, failed: failed }); }
                    else { next(); }
                });
            };
            for (var k = 0; k < Math.min(CONCURRENCY, items.length); k++) { next(); }
        });
    }

    function crawl() {
        var brandId = $('#hdnbrandId').val() || '0';
        var branchId = $('#hdnBranchId').val() || '0';
        var media = {};
        var catsSeen = {}, catQueue = [];
        var items = {};
        var calls = 0;

        var tick = function () { calls++; overlayProgress(t('menuData'), calls, 0); };
        var queueCats = function (list) {
            asArray(list).forEach(function (c) {
                var id = c && (c.CAT_NUM != null ? c.CAT_NUM : c.Cat_Num);
                if (id != null && !catsSeen[id]) { catsSeen[id] = true; catQueue.push(id); }
            });
        };
        var queueItems = function (list) {
            asArray(list).forEach(function (it) {
                var id = it && (it.id != null ? it.id : it.ITEM_ID);
                if (id != null) { items[id] = true; }
            });
        };
        var take = function (res) {
            tick();
            if (res && typeof res === 'object') {
                collectMedia(res, media);
                queueCats(res.dtCategory);
                queueCats(res.dtSubCategory);
                queueItems(res.dtItems);
            }
            return res;
        };

        overlay(t('downloading'), t('downloadingMsg'));

        // 1. Labels for both languages, branches/sections.
        var base = Promise.all([
            postJson('/ItemsView/GetLangLabels', { selectedLang: 'EN' }).then(take).catch(tick),
            postJson('/ItemsView/GetLangLabels', { selectedLang: 'AR' }).then(take).catch(tick),
            postJson('/ItemsView/GetBranchAndSectionList', { BrandId: brandId }).then(take).catch(tick)
        ]);

        // 2. Root category list - this one MUST work, otherwise there is no menu.
        var root = base.then(function () {
            return Promise.all([
                postJson('/ItemsView/GetCategoryList', { BrandId: brandId, Branchid: branchId }).then(take),
                postJson('/ItemsView/GetCategoryList', { BrandId: brandId, Branchid: branchId, CategoryId: 0 }).then(take).catch(tick)
            ]);
        }).then(function (r) {
            if (!r[0] || r[0].Message !== 'Success') { throw new Error('Category list unavailable'); }
        });

        // 3. Every category and sub-category: its sub list + its items.
        var walkCats = function () {
            if (!catQueue.length) { return Promise.resolve(); }
            var batch = catQueue.splice(0, catQueue.length);
            return runPool(batch, function (id) {
                return Promise.all([
                    postJson('/ItemsView/GetCategoryList', { BrandId: brandId, Branchid: branchId, CategoryId: id }).then(take),
                    postJson('/ItemsView/GetItemList?Cat_Num=' + encodeURIComponent(id) +
                        '&BrandId=' + encodeURIComponent(brandId) + '&Branchid=' + encodeURIComponent(branchId)).then(take)
                ]).then(function () { return true; }, function () { tick(); return false; });
            }).then(walkCats);   // sub-categories found in this round
        };

        // 4. Every item: extras/choices/comments + image gallery.
        var walkItems = function () {
            var ids = Object.keys(items);
            return runPool(ids, function (id) {
                return Promise.all([
                    postJson('/ItemsView/BindItemExtraItemsAndComments?itemid=' + encodeURIComponent(id) +
                        '&Branchid=' + encodeURIComponent(branchId)).then(take),
                    postJson('/ItemsViewNew/GetItemImages', { ItemId: id }).then(take)
                ]).then(function () { return true; }, function () { tick(); return false; });
            });
        };

        // 5. Photos, videos, icons, fonts, backgrounds - downloaded whole.
        var fetchMedia = function () {
            collectFromDocument(media);
            var urls = Object.keys(media);
            overlayProgress(t('media'), 0, urls.length);
            return runPool(urls, function (url) {
                var sameOrigin = url.indexOf(location.origin) === 0;
                return fetch(url, sameOrigin ? { credentials: 'same-origin' } : { mode: 'no-cors' }).then(function (r) {
                    if (r.body && r.body.cancel) { r.body.cancel().catch(function () { }); }
                    return r.ok || r.type === 'opaque';
                });
            }, function (done, total) { overlayProgress(t('media'), done, total); });
        };

        return root.then(walkCats).then(walkItems).then(fetchMedia).then(function (m) {
            return {
                categories: Object.keys(catsSeen).length,
                items: Object.keys(items).length,
                media: m.done - m.failed,
                mediaFailed: m.failed
            };
        });
    }

    function finishPendingSync() {
        busy = true;
        setSpinning(true);
        overlay(t('downloading'), t('downloadingMsg'));
        return waitForPageIdle().then(crawl).then(function (stats) {
            return send('SYNC_COMMIT').then(function () { return stats; });
        }).then(function (stats) {
            var firstTime = !parseSyncCookie();
            setCookie(COOKIE_SYNC,
                't=' + Date.now() +
                '&b=' + ($('#hdnbrandId').val() || '') +
                '&r=' + ($('#hdnBranchId').val() || '') +
                '&c=' + stats.categories + '&i=' + stats.items + '&m=' + stats.media, 365);
            busy = false;
            setSpinning(false);
            hideOverlay();
            applyUi();
            toast(t(firstTime ? 'done' : 'synced') + ' (' + stats.categories + ' / ' + stats.items + ' / ' + stats.media + ')', 'success');
            if (stats.mediaFailed) { setTimeout(function () { toast(t('partial') + ' (' + stats.mediaFailed + ')', 'error'); }, 900); }
            if (firstTime) { setTimeout(offerInstall, 1200); }
        }).catch(function (err) {
            if (window.console) { console.error('[OfflineMode] sync failed', err); }
            return send('SYNC_ABORT').catch(function () { }).then(function () {
                busy = false;
                setSpinning(false);
                hideOverlay();
                alertBox(t('failed'));
            });
        });
    }

    /* ------------------------------------------------------------- init -- */
    function hookLanguageSwitch() {
        if (typeof window.selectLanguage !== 'function' || window.selectLanguage.__offlineHooked) { return; }
        var original = window.selectLanguage;
        var wrapped = function () {
            var r = original.apply(this, arguments);
            setTimeout(applyUi, 0);
            return r;
        };
        wrapped.__offlineHooked = true;
        window.selectLanguage = wrapped;
    }

    function init() {
        hookLanguageSwitch();

        // Installed from the browser menu/address bar, or opened as the app.
        window.addEventListener('appinstalled', markInstalled);
        if (isStandalone()) { markInstalled(); }

        applyUi();
        $(window).on('online offline', updateConnectivity);

        var pending = false;
        try { pending = sessionStorage.getItem(PENDING_KEY) === '1'; sessionStorage.removeItem(PENDING_KEY); } catch (e) { }

        if (!supported()) { return; }

        if (!isOn()) {
            // Switched to Online (maybe in another tab) - make sure nothing is left behind.
            ourRegistration().then(function (reg) { if (reg) { clearAndUnregister(); } });
            return;
        }

        if (pending && navigator.serviceWorker.controller) {
            finishPendingSync();
            return;
        }

        ourRegistration().then(function (reg) {
            if (!reg) {
                // Cookie says offline but the worker is gone (browser cleanup, new
                // browser profile...). Rebuild once per session when online.
                var repaired = false;
                try { repaired = sessionStorage.getItem(REPAIR_KEY) === '1'; sessionStorage.setItem(REPAIR_KEY, '1'); } catch (e) { }
                if (!repaired && navigator.onLine !== false) {
                    busy = true;
                    overlay(t('preparing'), t('preparingMsg'));
                    register().then(startSyncAndReload).catch(function () { busy = false; hideOverlay(); });
                }
                return;
            }
            if (!navigator.serviceWorker.controller) {
                return;   // first load after install; next navigation is controlled
            }
            // A sync that was interrupted (tab closed mid-way) - roll it back.
            send('GET_STATE').then(function (info) {
                if (info && info.state && info.state.syncing) { return send('SYNC_ABORT'); }
            }).catch(function () { });
        });
    }

    $(init);

    return { toggle: toggle, sync: sync, isOn: isOn, refresh: applyUi };

})(window, document, jQuery);
