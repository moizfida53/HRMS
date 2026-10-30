(function ($) {

    $.cssloader = {
        settings: {},
        defaults: { container: $('body'), element: 'loadingDiv' },
        element: null,
        init: function (options) {
            $.cssloader.settings = $.extend({}, $.cssloader.defaults, options);
            $.cssloader.settings.container.append('<div id="loadingDiv" class="loaderbouncing"></div >');
            $.cssloader.element = $('#loadingDiv');
        },
        showLoader: function (options) {
            if ($.cssloader.element == null) {
                $.cssloader.init(options);
            }
            $.cssloader.element.show();
        },
        hideLoader: function () {
            if ($.cssloader.element != null) {
                $.cssloader.element.hide();
            }

        }
    }

    showLoading = function (options) {
        $.cssloader.showLoader(options);
    }

    hideLoading = function () {
        $.cssloader.hideLoader();
    }

})(jQuery);