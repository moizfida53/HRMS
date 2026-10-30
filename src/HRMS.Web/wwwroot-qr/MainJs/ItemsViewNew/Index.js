var CartDetails = [];
var CartComments = [];
var CartExtraItems = [];
var CartChoicesItems = [];

var IsReservationClick = 0;

var selectedCategoryId = 0;
var MainCateHeader = "";
var isbackcounter = 0;


var customerAddresses = null;
var CustomerDetails = null;
var isLoadervisible = 1;

//function launchFullScreen(element) {
//    if (element.requestFullScreen) {
//        element.requestFullScreen();
//    } else if (element.mozRequestFullScreen) {
//        element.mozRequestFullScreen();
//    } else if (element.webkitRequestFullScreen) {
//        element.webkitRequestFullScreen();
//    }
//}


//function toggleFullscreen(elem) {
//    elem = elem || document.documentElement;
//    if (!document.fullscreenElement && !document.mozFullScreenElement &&
//        !document.webkitFullscreenElement && !document.msFullscreenElement) {
//        if (elem.requestFullscreen) {
//            elem.requestFullscreen();
//        } else if (elem.msRequestFullscreen) {
//            elem.msRequestFullscreen();
//        } else if (elem.mozRequestFullScreen) {
//            elem.mozRequestFullScreen();
//        } else if (elem.webkitRequestFullscreen) {
//            elem.webkitRequestFullscreen(Element.ALLOW_KEYBOARD_INPUT);
//        }
//    } else {
//        if (document.exitFullscreen) {
//            document.exitFullscreen();
//        } else if (document.msExitFullscreen) {
//            document.msExitFullscreen();
//        } else if (document.mozCancelFullScreen) {
//            document.mozCancelFullScreen();
//        } else if (document.webkitExitFullscreen) {
//            document.webkitExitFullscreen();
//        }
//    }
//}


//launchFullScreen(document.documentElement); // the whole page
function toggleFullscreen(elem) {
    elem = elem || document.documentElement;
    if (!document.fullscreenElement && !document.mozFullScreenElement &&
        !document.webkitFullscreenElement && !document.msFullscreenElement) {
        if (elem.requestFullscreen) {
            elem.requestFullscreen();
        } else if (elem.msRequestFullscreen) {
            elem.msRequestFullscreen();
        } else if (elem.mozRequestFullScreen) {
            elem.mozRequestFullScreen();
        } else if (elem.webkitRequestFullscreen) {
            elem.webkitRequestFullscreen(Element.ALLOW_KEYBOARD_INPUT);
        }
    } else {
        if (document.exitFullscreen) {
            document.exitFullscreen();
        } else if (document.msExitFullscreen) {
            document.msExitFullscreen();
        } else if (document.mozCancelFullScreen) {
            document.mozCancelFullScreen();
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        }
    }
}

//document.getElementById('btnFullScreen').addEventListener('click', function () {
//    alert("full btn click");
//    //var viewFullScreen = document.documentElement;
//    //if (viewFullScreen.requestFullscreen) {
//    //    viewFullScreen.requestFullscreen();
//    //}
//    toggleFullscreen();
//});

//document.getElementById('exampleImage').addEventListener('click', function () {
//    toggleFullscreen(this);
//});
$(document).ready(function () {
    debugger;
    //$('#btnFullScreen').click();
    //toggleFullscreen();
    //alert("full screen mode");
    //toggleFullscreen();

    //var elem = document.getElementById("divleftsideMenuListView");
    //toggleFullscreenNew();
    if ($('#hdnBrandIsExpired').val() == "1") {
        $("#alertTitle").html("");
        $("#alertMessage").html("PLEASE RENEW YOUR SUBSCRIPTION");
        $("#alertModal").modal();
    }
    else {
        BindLangLabels("EN");

        var flgpaymentRedirect = 0;
        var flgTrackOrderRedirect = 0;
        debugger;

        ///////////Begin Redirect from SMS Link Check Track order ////////////////
        var TrackOrderNo = GetParameterValuesFromQueryString('TrackOrderNo');
        if (TrackOrderNo != "" && TrackOrderNo != undefined) {
            flgTrackOrderRedirect = 1;
            onClickTrackOrder();
            $('#txtTrackorderNumber').val(TrackOrderNo);
            BindTrackorderdataNew();
        }
        ///////////End Redirect from SMS Link Check Track order ////////////////

        ///////////Begin Redirect from Tpayment success then generate order or display order ////////////////
        var tap_id = GetParameterValuesFromQueryString('tap_id');
        if (tap_id != "" && tap_id != undefined) {
            var ckOrderData = accessCookie("TpayOrderConfirm");
            if (ckOrderData != "" && ckOrderData != undefined) {
                flgpaymentRedirect = 1;
                var objdata = JSON.parse(ckOrderData);
                SubmitOrderAjaxcall(objdata);
            }
        }
        ///////////End Redirect from Tpayment success then generate order or display order ////////////////

        if (flgpaymentRedirect == 0 && flgTrackOrderRedirect == 0) {

            ///////////////begin Code for If any advertise file exist in the folder then display Adv. Popup/////////////////
            //var http = new XMLHttpRequest();
            //var url = "../AdvertisementImages/adv1.jpg";
            debugger;
            var url = $('#advisementImage').attr("src");

            if (url != "") {
                $("#advisement").modal('show');
                $('#advisementImage').attr("src", "../AdvertisementImages/" + url)
                //$.ajax({
                //    url:"~/AdvertisementImages/"+ url,
                //    type: 'HEAD',
                //    cache: false,
                //    error: function () {
                //        //alert("File doesn't exists");
                //    },
                //    success: function () {
                //        $("#advisement").modal('show');
                //    }
                //});
            }
            ///////////////End Code for If any advertise file exist in the folder then display Adv. Popup/////////////////

            if ($('#hdnDesignName').val() == "Design3") {
                $('#divleftsideMenuListView').hide();
                //if ($('#hdnbrandId').val() > 0 && $('#hdnBranchId').val() > 0) {
                BindCategory(selectedCategoryId);
                debugger;
                if ($('#hdnToFormRedirect').val() == "Reservation") {
                    ShowDivReservation();
                }
                else {
                    $('#divCategoryList').show();
                    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
                    if ($('#divlandingpage').length) {
                        $('#divlandingpage').show();
                        $("#divlandingpage").css("visibility", "visible");
                        //$("#divlandingpage").removeClass("h-100");
                        $('#divleftsideMenuListView').hide();
                    } else {
                        $('#divleftsideMenuListView').show();
                    }
                    $('#divSectionMenu').hide();
                    $('#btnSectionDivClose').click();
                }
                //}
                //else {
                BindSectionMenu();
                //}
            }
            else {
                BindCategory(selectedCategoryId);
            }

            if ($('#isAddressConfirmView').val() != "1") {
                checkCookie();
            }
            BindAreaDropdown();
            //UpdateCartCountSpan();
            //onClickTrackOrder();
            $(document)
                .ajaxStart(function (evt, request, settings) {
                    //showLoading();
                    if (isLoadervisible == 1) {
                        $('.loading-block').show();
                    }
                });
            $(document).ajaxStop(function (evt, request, settings) {
                //hideLoading();
                if (isLoadervisible == 1) {
                    $('.loading-block').hide();
                }
            });
            $(document).ajaxError(function (evt, request, settings) {
                //hideLoading();
                $('.loading-block').hide();
            });
        }
    }

});

function GetParameterValuesFromQueryString(param) {
    var url = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
    for (var i = 0; i < url.length; i++) {
        var urlparam = url[i].split('=');
        if (urlparam[0] == param) {
            return urlparam[1];
        }
    }
}

function ShowMenuclick() {
    debugger;
    $('#ItemDetails').hide();
    $('#btnMenu').hide();
    $('#cartFooter').hide();
    $('#CartView').hide();
    $('#MenuList').show();
    $('#kt_wizard_v4').hide();
    $('#scrolldiv').show();
    $('#desktopview').show();
    $('.smartcms_ost_map').hide();
    $('#TrackingOrder').hide();

    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        $('#divlandingpage').show();
        $("#divlandingpage").css("visibility", "visible");
        //$("#divlandingpage").removeClass("h-100");
        $('#divleftsideMenuListView').hide();
    } else {
        $('#divleftsideMenuListView').show();
    }

    $('#divSectionMenu').hide();
    $('#divReservation').hide();
    $('#divReservationCustomerInfo').hide();
    $('#divReservationConfirm').hide();
}

function ShowMenuclickRedirect() {
    debugger;
    var url = "/ItemsViewNew/Index?id=" + $('#hdnbrandId').val() + "," + $('#hdnBranchId').val();
    window.location.href = url;
}

function displaycartview() {
    debugger;
    selectedCategoryId = 0;
    selectedItemid = 0;
    selectedHID = 0;

    $('#hdnisCartSelected').val("1")
    $('#divCategoryList').hide();
    $('#divMainItemList').hide();
    $('#divMainItemDetails').hide();
    $('#divCartView').show();
    //$('#divleftsideMenuListView').show();
    //if ($('#divlandingpage').length) {
    //    //$("#divlandingpage").css("visibility", "collapse");
    //    $("#divlandingpage").hide();
    //}
    //$('.banner').height(0);
    if ($('.banner').hasClass('d-block')) {
        $('.banner').removeClass('d-block').addClass('d-none');
    }

    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        $("#divlandingpage").css("visibility", "collapse");
        $("#divlandingpage").hide();
        //$("#divlandingpage").removeClass("h-100");
        //$('#divleftsideMenuListView').hide();
        $('#divleftsideMenuListView').show();
    } else {
        $('#divleftsideMenuListView').show();
    }

    $('#divSectionMenu').hide();
    $('#divReservation').hide();
    $('#divReservationCustomerInfo').hide();
    $('#divReservationConfirm').hide();

    //showLoading();
    var _cartdetails = CartDetails;
    var _cartComments = CartComments;
    var _cartExtraItems = CartExtraItems;
    var _cartChoiceItems = CartChoicesItems;
    debugger;
    BindCart(_cartdetails, _cartComments, _cartChoiceItems, _cartExtraItems, false, false);
}

//$(window).load(function(){
$('.btnGenerateOrder').click(function () {
    debugger;
    /*$.each( CartDetails, function(i, obj) {
       obj.Comments=$('#comments_'+ obj.ItemId).val();
   });*/
    if (CartDetails.length > 0) {
        //set items data in objects
        //var tempCartDetails = CartDetails;
        //$.each(tempCartDetails, function (i, obj) {
        //    var cmt = $('#comments_' + obj.I + '_' + obj.UID+'').val();
        //    obj.C = cmt;
        //});
        //debugger;
        //CartDetails = tempCartDetails;

        //var qrstr = "";
        //$.each(CartDetails, function (i, objItems) {
        //    debugger;
        //    qrstr = qrstr + objItems.I + "~" + objItems.Q + "~";

        //    //start ExtraItems string
        //    qrstr = qrstr + "'";
        //    var ctnExtra = 0;
        //    $.each(CartExtraItems, function (i, objExtra) {
        //        if (objExtra.MainItemId == objItems.I) {
        //            if (ctnExtra == 0) {
        //                qrstr = qrstr + objExtra.ExtraItemId;
        //            }
        //            else {
        //                qrstr = qrstr + "," + objExtra.ExtraItemId;
        //            }
        //            ctnExtra++;
        //        }
        //    });

        //    qrstr = qrstr + "'~";
        //    //End ExtraItems string

        //    //start Comments string
        //    qrstr = qrstr + "'";
        //    var ctnComment = 0;
        //    $.each(CartComments, function (i, objComment) {
        //        if (objComment.MainItemId == objItems.I) {
        //            if (ctnComment == 0) {
        //                qrstr = qrstr + objComment.CommentId;
        //            }
        //            else {
        //                qrstr = qrstr + "," + objComment.CommentId;
        //            }
        //            ctnComment++;
        //        }
        //    });
        //    //End Comments string

        //    //Item textboxComments
        //    qrstr = qrstr + "'~'" + objItems.C + "'~*";
        //});
        qrstr = "1!" + JSON.stringify(CartDetails) + "1!";

        if (CartExtraItems.length > 0) {
            var tempCartExtraItems = [];
            $.each(CartExtraItems, function (i, objExtra) {
                var item = {}
                item["UID"] = objExtra.UID;
                item["MI"] = objExtra.MainItemId;
                item["ExId"] = objExtra.ExtraItemId;
                item["GId"] = objExtra.GroupId;
                tempCartExtraItems.push(item);
            });
            qrstr += "2!" + JSON.stringify(tempCartExtraItems) + "2!";
        }
        if (CartChoicesItems.length > 0) {
            var tempCartChoicesItems = [];
            $.each(CartChoicesItems, function (i, objchoice) {
                var item = {}
                item["UID"] = objchoice.UID;
                item["MI"] = objchoice.MainItemId;
                item["ChId"] = objchoice.ChoiceItemId;
                item["GId"] = objchoice.GroupId;
                tempCartChoicesItems.push(item);
            });
            qrstr += "3!" + JSON.stringify(tempCartChoicesItems) + "3!";
        }
        if (CartComments.length > 0) {
            //qrstr += "~~CartComments~~:4!" + JSON.stringify(CartComments) + "4!";
            var tempCartComments = [];
            $.each(CartComments, function (i, objchoice) {
                var item = {}
                item["UID"] = objchoice.UID;
                item["MI"] = objchoice.MainItemId;
                item["CmId"] = objchoice.CommentId;
                item["cm"] = objchoice.Comment;
                tempCartComments.push(item);
            });
            qrstr += "4!" + JSON.stringify(tempCartComments) + "4!";
        }


        debugger;
        //var val = JSON.stringify({ i: CartDetails, c: tempCartComments, e: tempCartExtraItems });
        var val = qrstr;
        if (val) {

            //function en(c) { var x = 'charCodeAt', b, e = {}, f = c.split(""), d = [], a = f[0], g = 256; for (b = 1; b < f.length; b++)c = f[b], null != e[a + c] ? a += c : (d.push(1 < a.length ? e[a] : a[x](0)), e[a + c] = g, g++, a = c); d.push(1 < a.length ? e[a] : a[x](0)); for (b = 0; b < d.length; b++)d[b] = String.fromCharCode(d[b]); return d.join("") }
            //function de(b) { var a, e = {}, d = b.split(""), c = f = d[0], g = [c], h = o = 256; for (b = 1; b < d.length; b++)a = d[b].charCodeAt(0), a = h > a ? d[b] : e[a] ? e[a] : f + c, g.push(a), c = a.charAt(0), e[o] = f + c, o++, f = a; return g.join("") }
            //var compressed = en(val);
            var compressed = val;
            //var decompressed = de(compressed);
            //$('#alert').html('<hr>' + compressed + '<hr><h1>' + compressed.length + ' characters versus original ' + decompressed.length + ' characters.</h1><hr>' + decompressed + '<hr>');

            $('#divqr').html("");
            $('#btnbackFromQccode').show();
            $('#divQRCodeMain').show();
            /*$('#CartView').hide();
            $('#btnMenu').hide();
            $('#cartFooter').hide();
            $('#MenuList').hide();
            $('#TrackingOrder').hide();*/
            $('#divqr').qrcode(compressed);

            $('#divMainItemList').hide();
            $('#divCategoryList').hide()
            $('#divCartView').hide();
            $('#divMainItemDetails').hide();
        }
    }
    else {
        alert("Please select at least one item.");
        //$('#snackbar').html("Please select item.");
        //var x = document.getElementById("snackbar");
        //// Add the "show" class to DIV
        //x.className = "show";
        //// After 3 seconds, remove the show class from DIV
        //setTimeout(function(){ x.className = x.className.replace("show", ""); }, 3000);
    }
});

$('.btnCheckOut').click(function () {
    debugger;
    if (CartDetails.length > 0) {
        debugger;
        //var url = "/ItemsViewNew/UserInfoAndOrderConfirm?BrandId=" + $('#hdnbrandId').val() + "&BranchId=" + $('#hdnBranchId').val();
        //window.location.href = url;

        $('#divCategoryList').hide();
        $('#divMainItemDetails').hide();
        $('#divCartView').hide();
        $('#divQRCodeMain').hide();
        $('#TrackingOrder').hide();
        $('#divReservation').hide();
        $('#divReservationConfirm').hide();

        //checkout views list
        $('#divCustomerInfo').show();
        $('#divDeliveryAddress').hide();
        $('#divDeliveryService').hide();
        $('#divPaymentView').hide();
        $('#divOrderConfirmView').hide();

        //bind from cookies
        BindCustomerAddressFromCookies();
    }
    else {
        //alert("Please select at least one item.");
        $('#snackbar').html("Please select item.");
        var x = document.getElementById("snackbar");
        // Add the "show" class to DIV
        x.className = "show";
        // After 3 seconds, remove the show class from DIV
        setTimeout(function () { x.className = x.className.replace("show", ""); }, 3000);
    }
});
//});

function BindCustomerAddressFromCookies() {
    debugger;
    if (CustomerDetails == null) {
        createCustomerDetailsObject();
    }
    else {
        $('#txtCustomerFullname').val(CustomerDetails["CustomerFullName"]);
        $('#txtCustomerPhoneNumber').val(CustomerDetails["PhoneNumber"]);
        $('#txtCustomerEmailnew').val(CustomerDetails["EmailId"]);
        $('#txtCustomerCivilID').val(CustomerDetails["CivilID"]);
    }
}

/*=============================================================================
  Cookies: one path, one copy.

  These used to be written with no path attribute at all. A cookie written that
  way belongs to the DIRECTORY of the page that set it - /ItemsViewNew/Index for
  a page at /ItemsViewNew/Index/abc, but /ItemsViewNew/Index/abc for a page at
  /ItemsViewNew/Index/abc/AR. The menu is reached on several such URLs (the
  brand code and the language are path segments), so the browser happily kept
  SEVERAL cookies all called OrderCookie, one per path.

  document.cookie then reports them all, and accessCookie() returns whichever
  the browser lists first. Deleting "the" cookie removed one copy and left the
  others, which is why a basket came back after an order was placed: the delete
  worked, on a different cookie than the one that was read back.

  Everything is now written with path=/ - one cookie per name for the whole
  site - and eraseCookie() clears the current path and every ancestor path as
  well, so copies left behind by the old code are cleaned up on the way out.
=============================================================================*/

// Every path a cookie could have been written to from this URL, plus '/'.
// For /ItemsViewNew/Index/abc/AR that is:
//   /ItemsViewNew/Index/abc/AR, /ItemsViewNew/Index/abc,
//   /ItemsViewNew/Index, /ItemsViewNew, /
function cookiePathCandidates() {
    var paths = ['/'];
    var segs = (window.location.pathname || '/').split('/').filter(function (s) { return s.length; });
    var acc = '';
    for (var i = 0; i < segs.length; i++) {
        acc += '/' + segs[i];
        paths.push(acc);
    }
    return paths;
}

// Expire a cookie everywhere it might live. Deleting a cookie requires the
// same path it was written with, and there is no way to ask the browser which
// path a cookie came from - so every candidate is expired.
function eraseCookie(cookieName) {
    var dead = '=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
    var paths = cookiePathCandidates();

    // No path attribute: matches the legacy write, whose path the browser
    // derives from the current URL.
    document.cookie = cookieName + dead;

    for (var i = 0; i < paths.length; i++) {
        document.cookie = cookieName + dead + '; path=' + paths[i];
    }
}

function createCookie(cookieName, cookieValue, daysToExpire) {
    // Clear any older copies first, including ones the previous version of this
    // function left on a deeper path. Without this a stale copy can outrank the
    // new one in document.cookie and be the value that is read back.
    eraseCookie(cookieName);

    var date = new Date();
    date.setTime(date.getTime() + (daysToExpire * 24 * 60 * 60 * 1000));

    cookieValue = cookieValue.replace("&amp;", "&");
    cookieValue = cookieValue.replace("&nbsp;", "");

    document.cookie = cookieName + "=" + cookieValue
                    + "; expires=" + date.toGMTString()
                    + "; path=/";
}

//on Add button cart number div highlight
$('btn btn-primary icon-btn    .card-primary .btn-plus').on('click', function () {
    debugger;
    $(".top-header .cart").addClass('add');
    setTimeout(function () {
        $('.top-header .cart').removeClass('add');
    }, 800);
});


// // On scroll Add Class  // on scroll top category div fixed visible
// // On scroll Add Class
$(".product-details-inner").scroll(function (e) {
    if ($(".product-details-inner").scrollTop() >= 20) {
        $(".product-details-inner").addClass('page-scrolled');
    } else {
        $(".product-details-inner").removeClass('page-scrolled');
    }
});


function BackToCategoryList() {
    debugger;
    //if (isbackcounter == 2) {
    //    $("#divSubCategoryList").show();
    //}
    //else {
    //    selectedMainCategoryId = 0;
    //    $('#selectedSubCategoryId').val("0");
    //    $("#divCategoryList").show();
    //    $("#divSubCategoryList").hide();
    //}

    selectedCategoryId = 0;
    selectedItemid = 0;
    selectedHID = 0;
    $('#hdnisCartSelected').val("0")
    //$('.banner').height(220);
    if ($('.banner').hasClass('d-none')) {
        $('.banner').removeClass('d-none').addClass('d-block');
    }
    $('#divCartView').hide();
    $('#divQRCodeMain').hide();

    $('#divCategoryList').show()
    $('#divMainItemList').hide();
    $('#divMainItemDetails').hide();
    $('#QRScanView').hide();

    debugger //2
    if (isbackcounter != 0) {
        isbackcounter = isbackcounter - 1;
    }

    if ($("#categoryList > div").length == 1) {
        BackToSectionList();
    }
}

function backtoItemList() {
    debugger;
    selectedItemid = 0;
    $('#hdnisCartSelected').val("0")
    $('#divQRCodeMain').hide();
    $('#divCartView').hide();
    $('#divCategoryList').hide();
    $('#divMainItemList').show();
    $('#divMainItemDetails').hide();
    $('#itemVideoImage').trigger('pause');
}


function BackToSectionList() {
    debugger;
    if (isbackcounter == 2 && $('#hdnIsSubCategoryProject').val() == "true") {
        BindCategory(selectedCategoryId);
    }
    else if (isbackcounter == 1 && $('#hdnIsSubCategoryProject').val() == "true") {
        selectedCategoryId = 0;
        //$('#divBranchName').html($('#Cat_' + cat_num).attr("data-val"));
        $('#divBranchName').html(MainCateHeader);
        BindCategory(selectedCategoryId);
    }
    else {
        selectedCategoryId = 0;
        selectedItemid = 0;
        selectedHID = 0;
        $('#hdnisCartSelected').val("0");
        $('#divCartView').hide();
        $('#divQRCodeMain').hide();

        $('#divCategoryList').hide();
        $('#divMainItemList').hide();
        $('#divMainItemDetails').hide();

        //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
        if ($('#divlandingpage').length) {
            $('#divlandingpage').show();
            $("#divlandingpage").css("visibility", "visible");
            //if (!$("#divlandingpage").hasClass("h-100")) {
            //    $("#divlandingpage").css("visibility", "visible");
            //    $("#divlandingpage").addClass("h-100");
            //}
            $('#divleftsideMenuListView').hide();
        } else {
            $('#divleftsideMenuListView').show();
        }

        $('#divSectionMenu').show();
        $('#divReservation').hide();
        $('#divReservationCustomerInfo').hide();
        $('#divReservationConfirm').hide();
    }
    debugger //2
    if (isbackcounter != 0) {
        isbackcounter = isbackcounter - 1;
    }

    if ($("#hdnDesignName").val() == "Design2") {
        $('#divBranchnameandBackToSection').hide();
    }
    else {
        $('#divBranchnameandBackToSection').show();
    }
}


function btnSectionBranchMenuclick() {
    debugger;
    if (parseInt($('#hdndefaultOneBrandId').val()) > 0
        && parseInt($('#hdndefaultOneBranchId').val()) > 0
    ) {
        $('#divCategoryList').show();

        //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
        if ($('#divlandingpage').length) {
            $('#divlandingpage').show();
            $("#divlandingpage").css("visibility", "visible");
            //$("#divlandingpage").removeClass("h-100");
            $('#divleftsideMenuListView').hide();
        } else {
            $('#divleftsideMenuListView').show();
        }
        $('#divSectionMenu').hide();
        $('#btncart').show();
    }
    IsReservationClick = 0;
}

//function btnSectionReservationclick() {
//    debugger;
//    IsReservationClick = 1;
//    if (parseInt($('#hdndefaultOneBrandId').val()) > 0
//        && parseInt($('#hdndefaultOneBranchId').val()) > 0
//    ) {
//        //onsectionBranchClick(brandId, Branchid, objbtn);
//    }

//}
function ShowDivReservation() {
    $('#ItemDetails').hide();
    $('#btnMenu').hide();
    $('#cartFooter').hide();
    $('#CartView').hide();
    $('#MenuList').hide();
    $('#kt_wizard_v4').hide();
    $('#scrolldiv').hide();
    $('#desktopview').hide();
    $('.smartcms_ost_map').hide();
    $('#TrackingOrder').hide();

    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        //$('#divlandingpage').show();
        //$("#divlandingpage").css("visibility", "visible");
        ////$("#divlandingpage").removeClass("h-100");
        //$('#divleftsideMenuListView').hide();

        //Changes on 29-Nov-2025, For Reservation click and select branch and then reservation form should visible
        $('#divlandingpage').hide();
        $('#divCategoryList').hide();
        $('#divleftsideMenuListView').show();
    } else {
        $('#divleftsideMenuListView').show();
    }
    $('#divSectionMenu').hide();
    $('#divReservation').show();
    $('#divReservationCustomerInfo').hide();
    $('#divReservationConfirm').hide();
    //$('#divIsavailable').hide();
    $('#btncart').hide();


    //clear reservation selection data
    $('#divDatepickerMain').hide();
    $('#divAreaAndTimeslot').hide();
    $('#btnReservationConfirm').hide();
    $('.table-icon').each(function (val, ind) {
        $(this).removeClass("active");
    })

    //clear reservation customer data
    $('#txtCustomerName').val("");
    $('#txtCustomerMobile').val("");
    $('#txtCustomerEmail').val("");
    $('#txtComments').val("");
}



function ShowDivReservationCustomerInfo() {
    $('#ItemDetails').hide();
    $('#btnMenu').hide();
    $('#cartFooter').hide();
    $('#CartView').hide();
    $('#MenuList').hide();
    $('#kt_wizard_v4').hide();
    $('#scrolldiv').hide();
    $('#desktopview').hide();
    $('.smartcms_ost_map').hide();
    $('#TrackingOrder').hide();

    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        //$('#divlandingpage').show();
        //$("#divlandingpage").css("visibility", "visible");
        ////$("#divlandingpage").removeClass("h-100");
        //$('#divleftsideMenuListView').hide();

        //Changes on 29-Nov-2025, For Reservation click and select branch and then reservation form should visible
        $('#divlandingpage').hide();
        $('#divCategoryList').hide();
        $('#divleftsideMenuListView').show();

    } else {
        $('#divleftsideMenuListView').show();
    }
    $('#divSectionMenu').hide();
    $('#divReservation').hide();
    $('#divReservationCustomerInfo').show();
    $('#divReservationConfirm').hide();
    $('#btncart').hide();
}

function ShowDivReservationConfirm() {
    $('#ItemDetails').hide();
    $('#btnMenu').hide();
    $('#cartFooter').hide();
    $('#CartView').hide();
    $('#MenuList').hide();
    $('#kt_wizard_v4').hide();
    $('#scrolldiv').hide();
    $('#desktopview').hide();
    $('.smartcms_ost_map').hide();
    $('#TrackingOrder').hide();


    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        //$('#divlandingpage').show();
        //$("#divlandingpage").css("visibility", "visible");
        ////$("#divlandingpage").removeClass("h-100");
        //$('#divleftsideMenuListView').hide();

        //Changes on 29-Nov-2025, For Reservation click and select branch and then reservation form should visible
        $('#divlandingpage').hide();
        $('#divCategoryList').hide();
        $('#divleftsideMenuListView').show();
    } else {
        $('#divleftsideMenuListView').show();
    }
    $('#divSectionMenu').hide();
    $('#divReservation').hide();
    $('#divReservationCustomerInfo').hide();
    $('#divReservationConfirm').show();
    $('#btncart').hide();
}


//for numeric textbox set
$("input[class*='onlyNumeric']").keydown(function (event) {
    debugger;
    if (event.shiftKey == true) {
        event.preventDefault();
    }

    if ((event.keyCode >= 48 && event.keyCode <= 57) ||
        (event.keyCode >= 96 && event.keyCode <= 105) ||
        event.keyCode == 8 || event.keyCode == 9 || event.keyCode == 37 ||
        event.keyCode == 39 || event.keyCode == 46 || event.keyCode == 190 || event.keyCode == 110) {
        $('#hdnCustomDiscountSet').val(1);
        $('#lblIspercOrAmount').text("KD");
        $("input:radio[class='DiscountType']").each(function (i) {
            //this.checked = false;
            $(this).prop('checked', false);
        });
    } else {
        event.preventDefault();
    }
    if (
        //$(this).val().indexOf('.') != -1 &&
        (event.keyCode == 190 || event.keyCode == 110)) {
        event.preventDefault();
    }
    //if a decimal has been added, disable the "."-button
});


var validate_email = function (email) {
    var pattern = /^([a-zA-A0-9_.-])+@([a-zA-Z0-9_.-])+([a-zA-Z])+/;
    var is_email_valid = false;
    if (email.match(pattern) != null) {
        is_email_valid = true;
    }
    return is_email_valid;
}

$(document).on("keyup", "#txtCustomerEmail", function (event) {
    var keypressed = event.which;
    var input_val = $(this).val();
    var is_success = true;
    if (keypressed == 9) {
        is_success = validate_email(input_val);
        if (!is_success) {
            $(this).focus();
        }
    }
});

$(document).on("focusout", "#txtCustomerEmail", function () {
    var input_val = $(this).val();
    var is_success = validate_email(input_val);

    if (!is_success) {
        $("#txtCustomerEmail").focus();
        $("#alertTitle").html("");
        $("#alertMessage").html(msginsertValidEmail);
        $("#alertModal").modal();
    }
});

$(window).scroll(function () {
    if ($(this).scrollTop() > 600) {
        $('#scrollpage').fadeIn();
    }
    else {
        $('#scrollpage').fadeOut();
    }
})


function onClickTrackOrder() {
    debugger;
    //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
    if ($('#divlandingpage').length) {
        $('#divlandingpage').show();
        $("#divlandingpage").css("visibility", "visible");
        //$("#divlandingpage").removeClass("h-100");
        $('#divleftsideMenuListView').hide();
    } else {
        $('#divleftsideMenuListView').show();
    }

    $('#divSectionMenu').hide();
    $('#btnSectionDivClose').click();
    $('#btncart').show();

    $('#MenuList').hide();
    $('#CartView').hide();
    $('#divQRCodeMain').hide();
    $('#desktopview').hide();
    $('.smartcms_ost_timeline').hide();
    $('.smartcms_ost_map').hide();

    $('#divCategoryList').hide();
    $('#divSubCategoryList').hide();
    $('#divMainItemList').hide();
    $('#divMainItemDetails').hide();
    $('#divCartView').hide();
    $('#divQRCodeMain').hide();

    $('#TrackingOrder').show();
    $('#txtTrackorderNumber').val("");
    $('#mapid').val("");



}



function createCustomerDetailsObject() {
    debugger;
    CustomerDetails = {};
    CustomerDetails["CustomerFullName"] = "";
    CustomerDetails["PhoneNumber"] = "";
    CustomerDetails["EmailId"] = "";
    CustomerDetails["CivilID"] = "";
    CustomerDetails["IsPickup"] = "";
    CustomerDetails["ISDeliveryDateToday"] = "1";
    CustomerDetails["DeliveryDate"] = "";
    CustomerDetails["DeliveryTime"] = "";
    CustomerDetails["BranchId"] = "";//(when IsPickup true)
    CustomerDetails["SelectedAddressIndex"] = 0;
    CustomerDetails["AreaId"] = "";
    CustomerDetails["Lat"] = "";
    CustomerDetails["Long"] = "";
    CustomerDetails["DeliveryType"] = "Delivery";//(Delivery, Pickup)
    CustomerDetails["DeliveryAddressType"] = "";//(1 - Home, 2 - Apartment, 3 - Office)
    CustomerDetails["Block"] = "";//(home, Apartment, Office)
    CustomerDetails["Street"] = "";//(home, Apartment, Office)
    CustomerDetails["Building"] = "";//(Apartment, Office)
    CustomerDetails["Floor"] = "";//(Apartment, Office)
    CustomerDetails["Flat"] = "";//(home, Apartment(FlatNo), Office(FlatNo))
    CustomerDetails["AddressRemarks"] = "";//(home, Apartment, Office)
    CustomerDetails["Latitude"] = "";
    CustomerDetails["Longitude"] = "";
    CustomerDetails["PaymentType"] = "";//("Case", KNet, "Card")
    CustomerDetails["BillAmount"] = "";
    CustomerDetails["DeliveryCharge"] = "";
    CustomerDetails["Discount"] = "";
    CustomerDetails["BranchID"] = 0;
    CustomerDetails["AreaID"] = 1;

    var val = JSON.stringify(CustomerDetails);
    createCookie("CustomerDetailsCookie", val, 365);
}

function BrandAlertClose() {
    $('#divBrandAlert').remove();
}