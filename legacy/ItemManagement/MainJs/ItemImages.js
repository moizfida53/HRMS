/* ============================================================================
 * ItemImages.js
 * ----------------------------------------------------------------------------
 * Secondary-image (gallery) handling for the Add/Edit Item modal in
 * /Category/Index.
 *   - The item's main image (#hdnImageFileName) is the PRIMARY image.
 *   - The Secondary Images section stays disabled until a primary image exists.
 *   - Selected images are uploaded to disk (/Category/UploadFile) for preview
 *     and held in memory; the rows are written to tblItemImages only when the
 *     item is saved (SaveItem -> saveSecondaryImages).
 *
 * Loaded after Category.js. Category.js calls into the functions below.
 * ========================================================================== */

var secondaryImages = []; // [{ ImageName, Seq_No }]

function resetSecondaryImages() {
    secondaryImages = [];
    renderSecondaryImages();
    disableSecondaryImages();
    $('#secondaryImageUpload').val('');
    $('#lblSecondaryName').text('Choose images');
}

function enableSecondaryImages() {
    $('#secondaryImageUpload').prop('disabled', false);
    $('#btnSecondaryUpload').prop('disabled', false);
    $('#lblSecondaryHint').text('Add one or more images. They are saved when you click Save.');
}

function disableSecondaryImages() {
    $('#secondaryImageUpload').prop('disabled', true);
    $('#btnSecondaryUpload').prop('disabled', true);
    $('#lblSecondaryHint').text('Upload a primary image first to enable secondary images.');
}

function renderSecondaryImages() {
    var html = '';
    $.each(secondaryImages, function (i, img) {
        html +=
            '<div class="sec-img-thumb" data-name="' + img.ImageName + '" title="Drag to reorder" style="position:relative;width:84px;height:84px;margin:0 10px 10px 0;cursor:move;">' +
                '<img src="../images/' + img.ImageName + '" style="width:84px;height:84px;object-fit:cover;border-radius:8px;border:1px solid #ddd;pointer-events:none;" />' +
                '<button type="button" class="sec-img-remove" data-name="' + img.ImageName + '" title="Remove" ' +
                'style="position:absolute;top:-8px;right:-8px;width:22px;height:22px;border-radius:50%;border:0;background:#e24b4a;color:#fff;font-weight:700;line-height:1;cursor:pointer;">&times;</button>' +
                '<span class="sec-img-seq" style="position:absolute;left:4px;bottom:4px;background:rgba(0,0,0,.6);color:#fff;font-size:10px;font-weight:700;padding:1px 5px;border-radius:6px;">' + (i + 1) + '</span>' +
            '</div>';
    });
    $('#divSecondaryImages').html(html);
    initSecondarySortable();
}

/* Make the gallery drag-sortable; on drop, re-sync the array order. */
function initSecondarySortable() {
    var $grid = $('#divSecondaryImages');
    if (!$grid.length || typeof $grid.sortable !== 'function') { return; }
    if ($grid.hasClass('ui-sortable')) { $grid.sortable('destroy'); }
    $grid.sortable({
        items: '> .sec-img-thumb',
        cancel: '.sec-img-remove',
        tolerance: 'pointer',
        cursor: 'move',
        forcePlaceholderSize: true,
        update: function () { reorderSecondaryFromDom(); }
    });
}

/* Reorder the in-memory array to match the on-screen order, then renumber. */
function reorderSecondaryFromDom() {
    var order = [];
    $('#divSecondaryImages > .sec-img-thumb').each(function () { order.push($(this).attr('data-name')); });
    secondaryImages.sort(function (a, b) {
        return order.indexOf(a.ImageName) - order.indexOf(b.ImageName);
    });
    $('#divSecondaryImages > .sec-img-thumb').each(function (i) {
        $(this).find('.sec-img-seq').text(i + 1);
    });
}

function removeSecondaryImage(name) {
    secondaryImages = $.grep(secondaryImages, function (x) { return x.ImageName !== name; });
    renderSecondaryImages();
}

/* Upload each selected file to disk for preview, then add to the gallery. */
function uploadSecondaryImages() {
    var input = document.getElementById('secondaryImageUpload');
    if ($('#secondaryImageUpload').prop('disabled')) { return; }
    if (!input || !input.files || input.files.length === 0) { return; }

    var files = input.files;
    var pending = files.length;
    if (typeof $('.loading').show === 'function') { $('.loading').show(); }

    for (var i = 0; i < files.length; i++) {
        var fd = new FormData();
        fd.append(files[i].name, files[i]);
        $.ajax({
            type: 'POST',
            url: '/Category/UploadFile',
            contentType: false,
            processData: false,
            data: fd,
            success: function (result) {
                if (result && result.Message === 'Success' && result.FileName) {
                    secondaryImages.push({ ImageName: result.FileName, Seq_No: secondaryImages.length + 1 });
                    renderSecondaryImages();
                }
            },
            complete: function () {
                pending--;
                if (pending <= 0) {
                    $('.loading').hide();
                    $('#secondaryImageUpload').val('');
                    $('#lblSecondaryName').text('Choose images');
                }
            }
        });
    }
}

/* Load existing gallery images for an item (edit mode). */
function loadSecondaryImages(ItemID) {
    secondaryImages = [];
    if (!ItemID || ItemID == 0) { renderSecondaryImages(); return; }
    $.ajax({
        type: 'POST',
        url: '/Category/GetItemImages',
        data: JSON.stringify({ ItemID: ItemID }),
        contentType: 'application/json; charset=utf-8',
        dataType: 'json',
        success: function (result) {
            if (result && result.Message === 'Success' && result.dtImages) {
                var list = JSON.parse(result.dtImages);
                $.each(list, function (i, row) {
                    secondaryImages.push({ ImageName: row.Imagename, Seq_No: row.Seq_No });
                });
            }
            renderSecondaryImages();
        },
        error: function () { renderSecondaryImages(); }
    });
}

/* Write the current gallery to tblItemImages (called on modal Save). */
function saveSecondaryImages(ItemID, callback) {
    if (!ItemID || ItemID == 0) { if (callback) { callback(); } return; }
    $.each(secondaryImages, function (i, img) { img.Seq_No = i + 1; });
    $.ajax({
        type: 'POST',
        url: '/Category/SaveItemImages',
        data: JSON.stringify({ ItemID: ItemID, images: secondaryImages }),
        contentType: 'application/json; charset=utf-8',
        dataType: 'json',
        complete: function () { if (callback) { callback(); } }
    });
}

$(function () {
    $(document).on('click', '#btnSecondaryUpload', function () { uploadSecondaryImages(); });
    $(document).on('change', '#secondaryImageUpload', function () {
        var n = (this.files ? this.files.length : 0);
        $('#lblSecondaryName').text(n > 0 ? (n + ' file(s) selected') : 'Choose images');
    });
    $(document).on('click', '.sec-img-remove', function () {
        removeSecondaryImage($(this).attr('data-name'));
    });
});
