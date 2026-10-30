/* ============================================================================
 * ItemImageSlider.js
 * ----------------------------------------------------------------------------
 * Instagram-style image slider for the customer Item Details view.
 *   - Slide 1 is the item's primary (main) image, followed by the secondary
 *     images from tblItemImages (ordered by Seq_No).
 *   - Swipe / drag to move between images (native CSS scroll-snap).
 *   - Dots below show the current position; a counter (e.g. 2/5) sits on the
 *     top-right of the image.
 *   - With only one image, the original single <img> is shown (no slider).
 *
 * Loaded after BindCartDetails.js; OnItemClick() calls loadItemImageSlider().
 * ========================================================================== */

function loadItemImageSlider(itemid, primaryImage) {
    var images = [];
    if (primaryImage) { images.push(primaryImage); }

    $.ajax({
        type: 'POST',
        url: '/ItemsViewNew/GetItemImages',
        data: JSON.stringify({ ItemId: itemid }),
        contentType: 'application/json; charset=utf-8',
        dataType: 'json',
        success: function (result) {
            if (result && result.Message === 'Success' && result.dtImages) {
                try {
                    var list = JSON.parse(result.dtImages);
                    $.each(list, function (i, row) {
                        var nm = row.Imagename;
                        if (nm && $.inArray(nm, images) === -1) { images.push(nm); }
                    });
                } catch (e) { }
            }
            renderItemImageSlider(images);
        },
        error: function () { renderItemImageSlider(images); }
    });
}

function renderItemImageSlider(images) {
    var $car = $('#itemImageCarousel');
    var single = document.getElementById('itemDetailsItemImage');
    if (!$car.length) { return; }

    /* 0 or 1 image -> show the single image only (no slider, no counter) */
    if (!images || images.length <= 1) {
        $car.hide().empty();
        if (single) { single.style.removeProperty('display'); }   // let the .d-block class show it
        return;
    }

    /* more than one image -> hide the single image and show the slider only.
       Use !important so it overrides the Bootstrap .d-block class on the <img>. */
    if (single) { single.style.setProperty('display', 'none', 'important'); }

    var slides = '', dots = '';
    $.each(images, function (i, name) {
        slides += '<div class="item-img-slide"><div class="imgwrap"><img src="../../images/' + name + '" alt="" /></div></div>';
        dots += '<span class="dot' + (i === 0 ? ' active' : '') + '" data-i="' + i + '"></span>';
    });

    var html =
        '<span id="itemImageCounter" class="item-img-counter">1/' + images.length + '</span>' +
        '<div id="itemImageTrack" class="item-img-track">' + slides + '</div>' +
        '<div id="itemImageDots" class="item-img-dots">' + dots + '</div>';
    $car.html(html).show();

    var track = document.getElementById('itemImageTrack');
    if (!track) { return; }

    function update() {
        var w = track.clientWidth || 1;
        var idx = Math.round(track.scrollLeft / w);
        if (idx < 0) { idx = 0; }
        if (idx > images.length - 1) { idx = images.length - 1; }
        $('#itemImageCounter').text((idx + 1) + '/' + images.length);
        $('#itemImageDots .dot').removeClass('active').eq(idx).addClass('active');
    }

    track.onscroll = function () { window.requestAnimationFrame(update); };

    $('#itemImageDots .dot').on('click', function () {
        var i = parseInt($(this).attr('data-i'), 10) || 0;
        var left = i * (track.clientWidth || 0);
        if (track.scrollTo) { track.scrollTo({ left: left, behavior: 'smooth' }); }
        else { track.scrollLeft = left; }
    });

    track.scrollLeft = 0;
    update();
}

function hideItemImageSlider() {
    $('#itemImageCarousel').hide().empty();
}
