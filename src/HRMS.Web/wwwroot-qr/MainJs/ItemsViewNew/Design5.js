/* ============================================================================
   Design5.js  ·  customer-menu render for Design5 only.
   ----------------------------------------------------------------------------
   Entry point CreateDesign5Menu() is called from BindCategory() ONLY when
   hdnDesignName == "Design5", so Design1-4 never touch this code. It reuses the
   existing endpoints (/ItemsView/GetCategoryList and /ItemsView/GetItemList) and
   the existing OnItemClick() detail flow (same as Design2).
   ============================================================================ */
var d5CupEls = [], d5Items = [], d5Ix = 0, d5SwipeMoved = false, d5SwipeInit = false;
var D5I_R = 340, D5I_STEP = 0.52, D5I_WFRAC = 0.84, D5I_OVERLAP = 40, D5I_HALOPAD = 16;   // phone item arc: radius, gap, hero width fraction, hero overlap over categories, halo top padding(px)
var D5I_W_HERO = 0.62, D5I_HERO_MAX = 600, D5I_STEP_FRAC = 0.78;   // desktop/iPad STRAIGHT cover-flow: hero = min(W*0.62, available height, 600px cap) — BIG centred circle; neighbour centres sit 0.78*hero apart. Tune to taste.
var D5I_TOPGAP_WIDE = 16, D5I_RESERVE_PAD = 10;   // desktop breathing room above the hero; gap between the circle's bottom edge and the price

/* The strip at the bottom of the carousel the item circle must never intrude
   on: the price row (.d5-meta) plus a small gap. MEASURED from the DOM rather
   than hard-coded, because the carousel's height is not fixed — the top bar
   grows when a category's ingredients wrap to a second line, which shrinks the
   carousel, which pushed the hero down over the price on some categories and
   not others. Measuring also keeps it correct if the price font, line-height or
   position is themed. */
function D5BottomReserve(car) {
    var meta = car.querySelector('.d5-meta');
    if (!meta) { return 70 + D5I_RESERVE_PAD; }
    var bottom = 40;
    if (window.getComputedStyle) {
        var b = parseFloat(getComputedStyle(meta).bottom);
        if (!isNaN(b)) { bottom = b; }
    }
    return Math.max(64, Math.ceil(bottom + meta.offsetHeight + D5I_RESERVE_PAD));
}

function d5Lang() { return $('#selectedLang').val() === 'AR' ? 'AR' : 'EN'; }
/* >=768px (iPad + desktop): SAME drag-to-slide engine + animation, but the arc /
   carousel are laid on a STRAIGHT line instead of a circle (see the wide branches
   in D5CatLayout / D5ItemLayout). Transform-based, so no scrollbars. Phones
   (<768px) keep the curved arc. Evaluated live so resize / iPad rotation apply. */
function d5IsWide() { return typeof window.matchMedia === 'function' && window.matchMedia('(min-width: 768px)').matches; }
/* Wrap a signed offset into the shortest way round a ring of n slots. Used by the
   desktop/iPad "continuation" carousels so the strip LOOPS — the last items /
   categories cycle in on the LEFT of the first, so the left edge is never empty. */
function d5Wrap(x, n) { if (n <= 0) { return x; } x = ((x % n) + n) % n; return x > n / 2 ? x - n : x; }
function d5Price(p) {
    try { return (typeof round === 'function' ? round(p, decimalPlace).toFixed(decimalPlace) : p); }
    catch (e) { return p; }
}

/* Called by BindCategory for Design5. `Category` = all categories,
   `selectedCatItems` = the first/selected category's items. */
function CreateDesign5Menu(Category, selectedCatItems, subCategory) {
    D5RenderArc(Category || []);
    D5SyncCatName();
    d5Items = selectedCatItems || [];
    d5Ix = 0;
    D5BuildCups();
    D5UpdateMeta();
    D5AnimateMeta();   // first category is auto-selected on load — play the same reveal
    D5InitSwipe();
}

/* Category carousel on a CIRCLE: the centred category sits at the top of the arc
   and its neighbours curve down to the left and right. Drag/swipe left or right
   and every bubble glides along the arc (never a straight line), snapping to the
   nearest category with a smooth transition. */
var d5Cats = [], d5CatIx = 0, d5CatDragged = false, d5CatPos = [], d5CatScroll = 0, d5CatStepW = 96;
var D5_R = 260, D5_BASEY = 6, D5_CATGAP = 18, D5_CATBUBBLE = 70;   // circle radius, top offset, spacing gap between categories, bubble size (d5CatStepW = uniform desktop step, set in D5CatMeasure)

function D5RenderArc(Category) {
    var arc = document.getElementById('d5CatArc'); if (!arc) { return; }
    arc.innerHTML = ''; d5Cats = []; d5CatIx = 0; d5CatScroll = 0;
    var ar = (d5Lang() === 'AR');
    var strip = document.createElement('div'); strip.className = 'd5-arc-strip';
    Category.forEach(function (c, i) {
        var name = (ar ? c.CAT_NAME_ARABIC : c.CAT_NAME) || c.CAT_NAME;
        var el = document.createElement('div');
        el.className = 'd5-cat';
        el.innerHTML = '<div class="d5-bubble"><img src="../../ThumbnailImages/' + c.ImageName + '" alt=""></div>' +
                       '<div class="d5-lbl">' + name + '</div>';
        (function (idx, catNum) {
            el.onclick = function () {
                if (d5CatDragged) { return; }            // ignore the click that ends a drag
                D5CatGo(idx); OnCategoryClickDesign5(catNum);
            };
        })(i, c.CAT_NUM);
        strip.appendChild(el);
        d5Cats.push({ el: el, cat: c });
    });
    arc.appendChild(strip);
    D5CatMeasure();
    d5CatScroll = d5CatPos[0] || 0;
    D5CatLayout(); D5CatSetActive();
    if (!arc._d5drag) {
        arc._d5drag = true; D5CatInitDrag(arc);
        window.addEventListener('resize', function () { D5CatMeasure(); d5CatScroll = d5IsWide() ? (d5CatIx * d5CatStepW) : (d5CatPos[d5CatIx] || 0); D5CatLayout(); D5ItemLayout(0); });
    }
}

/* space categories proportionally to their rendered (possibly two-line) label width:
   short names sit closer, long names get more room — so more than 3 can show. */
function D5CatMeasure() {
    var w = [];
    for (var i = 0; i < d5Cats.length; i++) { w.push(Math.max(D5_CATBUBBLE, d5Cats[i].el.offsetWidth) + D5_CATGAP); }
    d5CatStepW = w.length ? Math.max.apply(null, w) : (D5_CATBUBBLE + D5_CATGAP);   // uniform desktop step (widest bubble+label) so looped labels never overlap
    d5CatPos = []; var acc = 0;
    for (var j = 0; j < w.length; j++) {
        if (j === 0) { d5CatPos.push(0); }
        else { acc += (w[j - 1] + w[j]) / 2; d5CatPos.push(acc); }
    }
}

/* Position every category from its arc-length distance to the view centre.
   Phones: on a CIRCLE (bubbles curve down to the sides).
   iPad/desktop: on a STRAIGHT line (flat baseline, linear x); the same drag
   scroll slides them, fading only at the container edges — no scrollbar. */
function D5CatLayout() {
    var arc = document.getElementById('d5CatArc'); if (!arc) { return; }
    var cx = (arc.clientWidth || 360) / 2, wide = d5IsWide();
    for (var i = 0; i < d5Cats.length; i++) {
        var el = d5Cats[i].el, x, y, a;
        if (wide) {
            var step = d5CatStepW, N = d5Cats.length, total = N * step;   // LOOP: uniform step, wrap so the left is never empty
            var t = i * step - d5CatScroll;
            if (total > 0) { t = ((t % total) + total) % total; if (t > total / 2) { t -= total; } }
            x = cx + t; y = D5_BASEY; a = Math.abs(t);
            el.style.transform = 'translate(' + x + 'px,' + y + 'px) translateX(-50%)';
            el.style.opacity = a > cx + 30 ? '0' : (a > cx - 80 ? '0.4' : '1');
            el.style.zIndex = '2';
            el.style.pointerEvents = a > cx + 30 ? 'none' : 'auto';
        } else {
            var ang = (d5CatPos[i] - d5CatScroll) / D5_R;
            x = cx + D5_R * Math.sin(ang);
            y = D5_BASEY + D5_R * (1 - Math.cos(ang));
            a = Math.abs(ang);
            el.style.transform = 'translate(' + x + 'px,' + y + 'px) translateX(-50%)';
            el.style.opacity = a > 1.25 ? '0' : (a > 0.82 ? '0.5' : '1');
            el.style.zIndex = a < 0.2 ? '5' : (a < 0.82 ? '3' : '1');
            el.style.pointerEvents = a > 1.25 ? 'none' : 'auto';
        }
    }
}

function D5CatSetActive() {
    for (var i = 0; i < d5Cats.length; i++) { d5Cats[i].el.classList.toggle('active', i === d5CatIx); }
}

function D5CatGo(idx) {
    d5CatIx = Math.max(0, Math.min(d5Cats.length - 1, idx));
    if (d5IsWide()) {
        var step = d5CatStepW, N = d5Cats.length, total = N * step, target = d5CatIx * step;
        var k = total > 0 ? Math.round((d5CatScroll - target) / total) : 0;   // pick the copy nearest the current scroll → slide the short way
        d5CatScroll = target + k * total;
    } else {
        d5CatScroll = d5CatPos[d5CatIx] || 0;
    }
    D5CatLayout(); D5CatSetActive();
}

function D5CatNearest() {
    if (d5IsWide()) {
        var N = d5Cats.length; if (N <= 0) { return 0; }
        return ((Math.round(d5CatScroll / d5CatStepW) % N) + N) % N;   // nearest looped slot
    }
    var best = 0, bestD = Infinity;
    for (var i = 0; i < d5CatPos.length; i++) { var d = Math.abs(d5CatPos[i] - d5CatScroll); if (d < bestD) { bestD = d; best = i; } }
    return best;
}

function D5CatInitDrag(arc) {
    var startX = null, startScroll = 0;
    arc.addEventListener('pointerdown', function (e) { startX = e.clientX; startScroll = d5CatScroll; d5CatDragged = false; arc.classList.add('d5-dragging'); });
    arc.addEventListener('pointermove', function (e) {
        if (startX === null) { return; }
        var dx = e.clientX - startX; if (Math.abs(dx) > 6) { d5CatDragged = true; }
        d5CatScroll = startScroll - dx;
        D5CatLayout();
    });
    var end = function () {
        if (startX === null) { return; }
        startX = null; arc.classList.remove('d5-dragging');
        var prev = d5CatIx;
        if (d5IsWide()) { d5CatScroll = Math.round(d5CatScroll / d5CatStepW) * d5CatStepW; d5CatIx = D5CatNearest(); }   // snap to nearest looped slot
        else { d5CatIx = D5CatNearest(); d5CatScroll = d5CatPos[d5CatIx] || 0; }
        D5CatLayout(); D5CatSetActive();
        if (d5CatIx !== prev) { OnCategoryClickDesign5(d5Cats[d5CatIx].cat.CAT_NUM); }
    };
    arc.addEventListener('pointerup', end);
    arc.addEventListener('pointercancel', function () { startX = null; arc.classList.remove('d5-dragging'); d5CatScroll = d5IsWide() ? Math.round(d5CatScroll / d5CatStepW) * d5CatStepW : (d5CatPos[d5CatIx] || 0); D5CatLayout(); });
    arc.addEventListener('pointerleave', function () { if (startX !== null) { end(); } });
}

function OnCategoryClickDesign5(cat_num) {
    D5SyncCatName();               // d5CatIx is already on the new category by here
    var track = document.getElementById('d5Track');
    if (track) { track.classList.add('d5-swapping'); }   // fade the old items out while we fetch

    /* The global ajaxStart hook (Index.js) throws up the full-screen "Loading"
       overlay for every request — that is the flash that makes a category tap
       feel like a page refresh. The Design1-4 category handlers all suppress it
       around this same call; Design5's did not. Restored in `complete` so any
       other request still gets the loader. */
    isLoadervisible = 0;
    $.ajax({
        type: 'Post', contentType: 'application/json; charset=utf-8', dataType: 'json', cache: false,
        url: '/ItemsView/GetItemList?Cat_Num=' + cat_num + '&BrandId=' + $('#hdnbrandId').val() + '&Branchid=' + $('#hdnBranchId').val(),
        success: function (result) {
            if (result.Message === 'Success') {
                d5Items = result.dtItems || [];
                d5Ix = 0; D5BuildCups(); D5UpdateMeta(); D5AnimateMeta();
            }
        },
        complete: function () {
            isLoadervisible = 1;
            if (track) { track.classList.remove('d5-swapping'); }   // also un-hides on failure
        }
    });
}

function D5BuildCups() {
    var track = document.getElementById('d5Track'); if (!track) { return; }
    track.innerHTML = ''; d5CupEls = [];
    var ar = (d5Lang() === 'AR');
    d5Items.forEach(function (it, i) {
        var d = document.createElement('div');
        d.className = 'd5-cup';
        // accessible name + hover tooltip (single-label model: no visible per-tile label)
        var nm = ((ar ? it.ITEM_NAME_ARABIC : it.ITEM_NAME) || it.ITEM_NAME || '').replace(/"/g, '&quot;');
        d.innerHTML = '<img src="../../images/' + it.IMAGENAME + '" alt="' + nm + '" title="' + nm + '">';
        /* Staged start: collapsed at the centre and transparent. D5ItemLayout on
           the next frame moves them to their real places, and because the
           elements already exist with a "from" value the .d5-cup CSS transition
           animates — so a new category's items bloom outward instead of snapping
           in. (Item-to-item changes were always smooth because the elements
           persist; a category change rebuilds them, which is why only that felt
           like a refresh.) */
        d.style.opacity = '0';
        d.style.transform = 'translateX(0px) translateY(0px) scale(0.25)';
        (function (idx) {
            d.onclick = function () {
                if (d5SwipeMoved) { d5SwipeMoved = false; return; }
                if (idx === d5Ix) { var cur = d5Items[d5Ix]; if (cur) { OnItemClick(cur.id, cur.HID); } }
                else { D5ItemGo(idx); }
            };
        })(i);
        track.appendChild(d); d5CupEls.push(d);
    });
    D5WriteItemFields();          // the shared item-details flow reads these — see below
    if (window.requestAnimationFrame) {
        // lay out on the NEXT frame so the staged state above is the transition's
        // starting point and the cups animate into place
        requestAnimationFrame(function () {
            D5ItemLayout(0);
            // and once more after that: the flex carousel may not have had its
            // final height yet, so re-size the hero from the settled height.
            requestAnimationFrame(function () { D5ItemLayout(0); });
        });
    } else {
        D5ItemLayout(0);          // no rAF: place them directly, no entrance animation
    }
}

/* ---------------------------------------------------------------------------
   Item-details bridge.
   OnItemClick() (BindCartDetails.js) doesn't take the item as an argument — it
   looks every field up in per-item hidden inputs (#hdnITEM_NAME_<id>,
   #hdnItem_IMAGENAME_<id>, ...) that the Design1-4 item binders emit alongside
   the item cards. Design5 draws its own carousel and never calls those binders,
   so the inputs were missing: OnItemClick() showed #divMainItemDetails and then
   threw on the first `.val().trim()`, leaving the view on the placeholder markup
   from ItemDetailsView.cshtml — which is why the item image never appeared.
   Emitting the same inputs here makes the shared detail flow work unmodified.
   Values are assigned via .value (not interpolated into HTML), so quotes and
   line breaks in names/ingredients can't break the markup.
   --------------------------------------------------------------------------- */
function d5Hidden(id, val) {
    var i = document.createElement('input');
    i.type = 'hidden'; i.id = id;
    i.value = (val === null || val === undefined) ? '' : String(val);
    return i;
}

function D5WriteItemFields() {
    var box = document.getElementById('d5ItemFields');
    if (!box) {
        box = document.createElement('div');
        box.id = 'd5ItemFields'; box.style.display = 'none';
        document.body.appendChild(box);   // outside #d5Track, which D5BuildCups/BindCategory wipe
    }
    box.innerHTML = '';
    var ar = (d5Lang() === 'AR');
    d5Items.forEach(function (it) {
        box.appendChild(d5Hidden('hdnITEM_NAME_' + it.id, (ar ? it.ITEM_NAME_ARABIC : it.ITEM_NAME) || it.ITEM_NAME));
        box.appendChild(d5Hidden('hdnItemINGREDIENT_' + it.id, (ar ? it.INGREDIENT_ARABIC : it.INGREDIENT) || it.INGREDIENT));
        box.appendChild(d5Hidden('hdnItem_IMAGENAME_' + it.id, it.IMAGENAME));
        box.appendChild(d5Hidden('hdnItem_VideoNAME_' + it.id, it.Video));
        box.appendChild(d5Hidden('hdnItem_PRICE_' + it.id, d5Price(it.PRICE)));
    });
}

/* Design5 shows the add-to-cart control on its own line right under the
   ingredients. In the shared ItemDetailsView.cshtml markup that row sits much
   further down, after the choice / extras groups, so move it up here — once, on
   load — anchored at #MainDivitemdetPrice, the price heading that sits directly
   below the ingredients. (That price is hidden by design5.css; it is only the
   anchor.) Reordering the markup instead would move the button for Design1-4
   too, which is why this is done in JS for Design5 only.
   Safe to relocate: OnItemClick() only ever refills it by id
   ($('#btnDetailsViewAdditemContainer').html(...)), so it keeps working from its
   new home. #d5PriceAddRow is laid out in design5.css. */
function D5PairPriceAndAddToCart() {
    if (document.getElementById('d5PriceAddRow')) { return; }        // already paired
    var price = document.getElementById('MainDivitemdetPrice');
    var btn = document.getElementById('btnDetailsViewAdditemContainer');
    if (!price || !btn) { return; }
    var addRow = $(btn).closest('.row')[0];
    if (!addRow) { return; }
    var row = document.createElement('div');
    row.id = 'd5PriceAddRow';
    price.parentNode.insertBefore(row, price);
    row.appendChild(price);      // price first  -> left
    row.appendChild(addRow);     // control next -> right
}

/* ---------------------------------------------------------------------------
   SPLASH SCREEN — tblBrand.BrandHomePageImage, Design5 only.
   Index.cshtml renders the empty #d5Splash overlay inline (opaque from the first
   paint, so the menu never flashes behind it). Here we slice the image into a
   grid, fly every piece in from a random direction so the picture assembles
   itself, hold it, then fade the overlay out and drop it from the DOM.

   The slices are plain background-position/-size on one cached image — no N
   copies of the <img>. The maths reproduces object-fit:CONTAIN: the whole
   picture is shown, scaled to fit and centred, so it is never cropped and never
   stretched. Whatever space is left over top/bottom or left/right stays as the
   splash background.
   --------------------------------------------------------------------------- */
var D5_SPLASH_MS = 3000;    // how long the finished image is held before fading
var D5_SPLASH_FADE = 450;   // fade-out duration — keep in step with design5.css
var D5_SPLASH_COLS = 6;     // grid columns; rows are derived so pieces stay squarish

function D5Splash() {
    var box = document.getElementById('d5Splash'); if (!box) { return; }   // not Design5 / no image
    var src = box.getAttribute('data-src'), done = false;
    var close = function () {
        if (done) { return; }
        done = true;
        box.classList.add('d5-splash-out');
        setTimeout(function () { if (box.parentNode) { box.parentNode.removeChild(box); } }, D5_SPLASH_FADE);
    };
    /* failsafe: whatever happens with the image, never leave the user stuck
       behind a full-screen overlay. close() is idempotent. */
    setTimeout(close, D5_SPLASH_MS + 4000);
    if (!src) { close(); return; }

    var img = new Image();
    img.onerror = close;                       // missing file -> straight to the menu
    img.onload = function () {
        D5SplashBuild(box, src, img.naturalWidth || 1, img.naturalHeight || 1);
        setTimeout(close, D5_SPLASH_MS);
    };
    img.src = src;
}

function D5SplashBuild(box, src, iw, ih) {
    var W = box.clientWidth || window.innerWidth, H = box.clientHeight || window.innerHeight;

    /* object-fit:contain — scale so the WHOLE image fits, then centre it. Never
       cropped, never stretched; any leftover space top/bottom or left/right just
       shows the splash background. (Add `, 1` to this Math.min to also stop a
       small image being enlarged to fit — i.e. object-fit:scale-down.) */
    var scale = Math.min(W / iw, H / ih);
    var bw = iw * scale, bh = ih * scale;
    var ox = (W - bw) / 2, oy = (H - bh) / 2;

    /* the grid covers the IMAGE rect, not the whole screen, so every piece
       carries picture and none fly in blank; rows follow the image's aspect so
       the pieces stay roughly square. */
    var cols = D5_SPLASH_COLS;
    var rows = Math.max(3, Math.min(14, Math.round(cols * (bh / bw))));
    var tw = bw / cols, th = bh / rows;

    var frag = document.createDocumentFragment(), pieces = [];
    for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
            var x = ox + c * tw, y = oy + r * th;
            var el = document.createElement('div');
            el.className = 'd5-splash-piece';
            el.style.left = x + 'px'; el.style.top = y + 'px';
            el.style.width = Math.ceil(tw) + 'px';     // ceil: overlap by <1px rather
            el.style.height = Math.ceil(th) + 'px';    // than leave hairline seams
            el.style.backgroundImage = 'url("' + src + '")';
            el.style.backgroundSize = bw + 'px ' + bh + 'px';
            el.style.backgroundPosition = (ox - x) + 'px ' + (oy - y) + 'px';
            // scattered start: random direction, distance, spin and shrink
            var ang = Math.random() * Math.PI * 2, dist = 200 + Math.random() * 420;
            el.style.transform = 'translate(' + (Math.cos(ang) * dist).toFixed(1) + 'px,' +
                                 (Math.sin(ang) * dist).toFixed(1) + 'px) rotate(' +
                                 (Math.random() * 100 - 50).toFixed(1) + 'deg) scale(' +
                                 (0.25 + Math.random() * 0.5).toFixed(2) + ')';
            el.style.transitionDelay = (Math.random() * 0.35).toFixed(2) + 's';   // stagger
            frag.appendChild(el); pieces.push(el);
        }
    }
    box.appendChild(frag);

    // next frame: release every piece to its real slot -> the picture assembles
    var go = function () {
        for (var i = 0; i < pieces.length; i++) {
            pieces[i].style.transform = 'translate(0,0) rotate(0deg) scale(1)';
            pieces[i].style.opacity = '1';
        }
    };
    if (window.requestAnimationFrame) { requestAnimationFrame(function () { requestAnimationFrame(go); }); }
    else { setTimeout(go, 30); }
}

/* Design5.js is loaded on every design, so gate the DOM surgery on the body
   class the same way design5.css gates its rules. */
$(function () {
    if (document.body.classList.contains('design5')) { D5PairPriceAndAddToCart(); }
    D5Splash();   // no-op unless #d5Splash exists (Design5 + a brand home-page image)
});

/* OnItemClick() titles the details view from #divCatename — the Design1-4
   item-list heading, which Design5 leaves empty. Keep it on the selected
   category so that header isn't blank. */
function D5SyncCatName() {
    var c = d5Cats[d5CatIx] && d5Cats[d5CatIx].cat; if (!c) { return; }
    var ar = (d5Lang() === 'AR');
    $('#divCatename').text((ar ? c.CAT_NAME_ARABIC : c.CAT_NAME) || c.CAT_NAME || '');
}

/* Desktop/iPad only. `avail` = the vertical band the item circle may occupy:
   the carousel height minus the reserved price/dots strip at the bottom and the
   gap at the top. The hero is the largest circle that fits that band (and the
   width / hard cap). Both D5ItemLayout and the drag step in D5InitSwipe read
   these, so the geometry can never drift apart between the two. */
function D5WideAvail(ch, reserve) { return Math.max(120, ch - reserve - D5I_TOPGAP_WIDE); }
function D5WideHero(W, ch, reserve) { return Math.min(W * D5I_W_HERO, D5WideAvail(ch, reserve), D5I_HERO_MAX); }

/* The centred item is the big CIRCULAR hero; its neighbours are smaller on each
   side. Phones: they ride a CIRCLE (neighbours curve down into the bottom
   corners). iPad/desktop: they ride a STRAIGHT line (neighbours stay on the
   hero's baseline, just smaller) and slide left/right — a flat cover-flow with
   the same easing animation, no scrollbar. frac = fractional drag offset (items).
   Desktop geometry is driven by D5I_W_HERO/HERO_MAX/STEP_FRAC/RESERVE_WIDE below. */
function D5ItemLayout(frac) {
    var car = document.querySelector('.d5-carousel'); if (!car) { return; }
    var W = car.clientWidth || 360, ch = car.clientHeight || 440, wide = d5IsWide();
    var reserve = D5BottomReserve(car);        // bottom strip the circle must stay clear of
    var heroD, heroLift, stepX;
    if (wide) {
        var avail = D5WideAvail(ch, reserve);                              // height left once the price row and the top gap are reserved
        heroD = D5WideHero(W, ch, reserve);                                // big centred circle, capped so it fits `avail`
        heroLift = reserve + Math.max(0, (avail - heroD) / 2);             // centre it in `avail` — the bottom edge never drops below `reserve`, so it clears the price
        stepX = heroD * D5I_STEP_FRAC;                                     // straight horizontal gap between item centres
    } else {
        heroD = Math.min(W * D5I_WFRAC, ch + D5I_OVERLAP - reserve);       // big hero; bottom never drops below the price row
        heroLift = Math.max(reserve, ch + D5I_OVERLAP - heroD);            // lift so the circle's top rides OVERLAP px over the category row
    }
    var big = heroD / 180;                                                // 180 = base .d5-cup px
    var halo = car.querySelector('.d5-halo');                             // keep the backing circle centred on the hero, complete (uncut)
    if (halo) {
        var hd = heroD + 22;
        halo.style.width = hd + 'px'; halo.style.height = hd + 'px';
        halo.style.left = '50%'; halo.style.marginLeft = (-hd / 2) + 'px'; halo.style.top = 'auto';
        halo.style.bottom = (heroLift + heroD / 2 - hd / 2 + D5I_HALOPAD) + 'px';
    }
    var halfW = W / 2;
    for (var i = 0; i < d5CupEls.length; i++) {
        var el = d5CupEls[i], dx, lift, s, a;
        if (wide) {
            var off = d5Wrap(i - d5Ix - frac, d5CupEls.length); a = Math.abs(off);   // LOOP: neighbours wrap in on the left, so it's never empty
            dx = off * stepX;
            lift = heroLift;                                              // flat baseline — the STRAIGHT part
            s = big * Math.max(0.44, 1 - a * 0.24);                       // hero big, neighbours gently smaller
            var ad = Math.abs(dx);
            el.style.transform = 'translateX(' + dx + 'px) translateY(' + (-lift) + 'px) scale(' + s + ')';
            el.style.opacity = ad > halfW ? '0' : (ad > halfW - 130 ? '0.5' : '1');   // fade out at the container edges
            el.style.zIndex = String(Math.max(0, 8 - Math.round(a)));     // hero on top, neighbours tuck behind
            el.style.pointerEvents = ad > halfW ? 'none' : 'auto';
        } else {
            var ang = (i - d5Ix - frac) * D5I_STEP;
            dx = D5I_R * Math.sin(ang);
            lift = heroLift - D5I_R * (1 - Math.cos(ang));               // neighbours drop toward the bottom corners
            a = Math.abs(ang);
            s = big * Math.max(0.36, 1 - a * 1.12);                      // hero full-size, neighbours smaller
            el.style.transform = 'translateX(' + dx + 'px) translateY(' + (-lift) + 'px) scale(' + s + ')';
            el.style.opacity = a > 0.82 ? '0' : (a > 0.55 ? '0.9' : '1');
            el.style.zIndex = a < 0.23 ? '6' : (a < 0.7 ? '3' : '1');
            el.style.pointerEvents = a > 0.82 ? 'none' : 'auto';
        }
    }
}

function D5ItemGo(idx) {
    d5Ix = Math.max(0, Math.min(d5Items.length - 1, idx));
    D5ItemLayout(0); D5UpdateMeta();
}

function D5UpdateMeta() {
    if (!d5Items.length) { return; }
    var it = d5Items[d5Ix], ar = (d5Lang() === 'AR');
    var name = (ar ? it.ITEM_NAME_ARABIC : it.ITEM_NAME) || it.ITEM_NAME || '';
    var desc = (ar ? it.INGREDIENT_ARABIC : it.INGREDIENT) || it.INGREDIENT || '';
    var cur = ar ? $('#hdnCurrencyArab').val() : $('#hdnCurrencyENG').val();
    $('#d5ItemName, #d5ItemNameSide').text(name);   // topbar copy (mobile/tablet) + right-panel copy (desktop)
    $('#d5ItemDesc, #d5ItemDescSide').text(desc);
    $('#d5ItemPrice').text((cur ? cur + '. ' : '') + d5Price(it.PRICE));
    var dots = document.getElementById('d5Dots');
    if (dots) {
        dots.innerHTML = '';
        d5Items.forEach(function (_, i) { var s = document.createElement('i'); if (i === d5Ix) { s.className = 'on'; } dots.appendChild(s); });
    }
}

/* Slide-in reveal played on every category change: the item NAME comes in from
   the LEFT, the INGREDIENTS from the RIGHT, both landing in their normal spot.
   The classes carry the CSS keyframes (design5.css); removing them, forcing a
   reflow and re-adding restarts the animation, otherwise the browser would only
   ever play it once. Handles both copies of the text: the top bar (mobile/iPad)
   and the right-hand panel (>=992px desktop). */
function D5AnimateMeta() {
    var targets = [
        { id: 'd5ItemName', cls: 'd5-anim-left' },       // name  -> from the left
        { id: 'd5ItemNameSide', cls: 'd5-anim-left' },
        { id: 'd5ItemDesc', cls: 'd5-anim-right' },      // ingredients -> from the right
        { id: 'd5ItemDescSide', cls: 'd5-anim-right' }
    ];
    targets.forEach(function (t) {
        var el = document.getElementById(t.id); if (!el) { return; }
        el.classList.remove(t.cls);
        void el.offsetWidth;                              // force reflow so the animation replays
        el.classList.add(t.cls);
    });
}

function D5InitSwipe() {
    var car = document.querySelector('.d5-carousel'); if (!car || car._d5drag) { return; }
    car._d5drag = true; d5SwipeInit = true;
    var sx = null;
    // px of drag per item: on the straight desktop/iPad cover-flow this is the
    // hero step so the drag tracks the tiles 1:1; on phones it's the arc feel.
    var cw = function () {
        var W = car.clientWidth || 360;
        if (d5IsWide()) { return D5WideHero(W, car.clientHeight || 440, D5BottomReserve(car)) * D5I_STEP_FRAC; }
        return W / 2.6;
    };
    car.addEventListener('pointerdown', function (e) { sx = e.clientX; d5SwipeMoved = false; car.classList.add('d5-dragging'); });
    car.addEventListener('pointermove', function (e) {
        if (sx === null) { return; }
        var dx = e.clientX - sx; if (Math.abs(dx) > 6) { d5SwipeMoved = true; }
        D5ItemLayout(-dx / cw());
    });
    var end = function (e) {
        if (sx === null) { return; }
        var dx = (e && e.clientX != null ? e.clientX : sx) - sx; sx = null;
        car.classList.remove('d5-dragging');
        var prev = d5Ix, moved = Math.round(-dx / cw()), N = d5Items.length;
        if (d5IsWide()) { d5Ix = N > 0 ? (((d5Ix + moved) % N) + N) % N : 0; }   // LOOP round the ends
        else { d5Ix = Math.max(0, Math.min(N - 1, d5Ix + moved)); }
        D5ItemLayout(0); if (d5Ix !== prev) { D5UpdateMeta(); }
    };
    car.addEventListener('pointerup', end);
    car.addEventListener('pointercancel', function () { sx = null; car.classList.remove('d5-dragging'); D5ItemLayout(0); });
    car.addEventListener('pointerleave', function (e) { if (sx !== null) { end(e); } });
}
