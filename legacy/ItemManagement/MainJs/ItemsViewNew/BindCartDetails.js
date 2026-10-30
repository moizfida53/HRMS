var selectedCategoryId = 0;
var selectedItemid = 0;
var selectedHID = 0;
var selectedCurrency = "KD"
var selectedMainCategoryId = 0;


///////////////////Start code for model view////////////////////////////
var modal = document.getElementById("myModal");

// Get the button that opens the modal
var btn = document.getElementById("myBtn");

// Get the <span> element that closes the modal
var span = document.getElementsByClassName("close")[0];
var isfromWaiterTemp = false;
// When the user clicks the button, open the modal 
/*btn.onclick = function() {
  modal.style.display = "block";
}*/

var SectionsArraylist = [];
var BranchArrayList = [];
var ItemAllergenslst = []
var validationPopup = "Sorry, looks like there are some errors detected, please try again.";
var ValconfirmButtonText = "Ok, got it!";
var validationlblFirstName = 'First name is required';
var validationlblLastName = 'Last Name is required';
var validationlblPhone = 'Phone is required';
var validationlblPhoneMin = 'Minimum 8 numbers';
var validationlblPhoneReq = 'Phone is not valid';
var validationlblEmail = 'Email is required';
var validationlblEmailNotValid = 'The value is not a valid email address';
var validationlblOrderType = 'OrderType is required';
var validationlblArea = 'Area is required';
var validationlblBlock = 'Block is required';
var validationlblStreet = 'Street is required';
var validationlblBuilding = 'Building is required';
var validationlblFlat = 'Flat is required';
var validationlblFloor = 'Floor is required';
var validationlblPaymentType = 'PaymentType is required';
var msgerrorval = "Please Contact your Administrator.";
var msgPleaseSelectValidSlot = "Please select valid slot."
var msgSectionBranchSelection = 'Please Select Branch First.';
var msgInsertCustomerName = 'Please Insert Customer Name';
var msgInsertCustomerMobile = 'Please Insert Customer Mobile';
var msgInsertCustomerEmail = 'Please Insert Customer Email';
var msginsertValidEmail = "Please insert valid email address.";
var msgBranchNotSelected = "Branch Not selected.";


var textlblUnitPrice = "Unit Price";
var textlblExtraprice = "Extra Price";
var textlblTotalprice = "Total Price";

var btnPaymentProcessOrder = "Process Order";
var btnPaymentProceedtoPayment = "Proceed to Payment";
// When the user clicks on <span> (x), close the modal
//span.onclick = function () {
//    modal.style.display = "none";
//}

// When the user clicks anywhere outside of the modal, close it
//window.onclick = function (event) {
//    if (event.target == modal) {
//        modal.style.display = "none";
//    }
//}


///////////////////End code for model view////////////////////////////
$.getJSON("https://api.ipify.org/?format=json", function (e) {
    $('#hdnIpAddress').val(e.ip);
    var objData = {
        IpAddress: e.ip
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objData),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/SetIpAddress",
        success: function (result) {
            if (result.Message == "Success") {
            }
        }
    });
});
/*=============================================================================
  BindCartCount(objCartDetails)

  The badge counts LINES in the basket, not units. It used to sum obj.Q, so
  adding a quantity of three to one dish showed 3 - the badge tracked how much
  was being bought rather than how many things were in the basket, and it moved
  every time the quantity stepper was touched.

  A line with a quantity of zero is on its way out and is not counted; the
  removal code strips it from the array a moment later.

  This is the only place the badge is written. The add and remove paths used to
  keep their own running totals and paint it themselves, which is how the badge
  and the basket could disagree.
=============================================================================*/
function BindCartCount(objCartDetails) {
    var cartcount = 0;
    $.each(objCartDetails || [], function (i, obj) {
        if (parseInt(obj.Q) > 0) cartcount = cartcount + 1;
    });

    $(".clCartCount").each(function (index) {
        $(this).text(cartcount);
        $(this).show();
    });
    $('#cartCountDesktop').text(cartcount);
    UpdateCartCountSpan();
}
/*
 * Versioned URL for one of the stylesheets that get swapped in and out at
 * runtime. Index.cshtml publishes AssetUrls (file-timestamp cache-busted by
 * Asset.V); the literal path is only a fallback for any page that renders this
 * script without that block, so a missed view degrades to the old behaviour
 * rather than a broken <link>.
 */
function assetUrl(key, fallback) {
    return (window.AssetUrls && window.AssetUrls[key]) ? window.AssetUrls[key] : fallback;
}

/*
 * Matches a stylesheet by file name rather than by exact href. The hrefs now
 * carry a "?v=<timestamp>" cache-buster, so the old exact-match selectors
 * ($('link[href="/cssNew/bootstrap.min.css"]')) would match nothing and the
 * LTR and RTL bootstraps would both stay in the page, fighting each other.
 */
function removeStylesheet(fileName) {
    $('link[rel="stylesheet"]').filter(function () {
        var href = $(this).attr("href") || "";
        return href.split("?")[0].indexOf(fileName) !== -1;
    }).remove();
}

function selectLanguage(btn) {
    debugger;
    var val = "EN"
    var Displayval = "ع"
    $('#menu_LanguageLabel').html("ARABIC");
    if ($('#selectedLang').val() == "EN") {
        val = "AR"
        Displayval = "EN"
        $('#menu_LanguageLabel').html("ENGLISH");

        $("html").attr("lang", "ar");
        $("html").attr("dir", "rtl");
        $("body").addClass("rtl");


        var $head = $("head");
        var $headlinkfirst = $head.find("link[rel='stylesheet']:first");
        var $headlinklast = $head.find("link[rel='stylesheet']:last");
        var linkElement1 = "<link rel='stylesheet' type='text/css' href='"
            + assetUrl("bootstrapRtl", "/cssNew/bootstrap-rtl.min.css") + "'/>";
        var linkElement2 = "<link rel='stylesheet' type='text/css' href='"
            + assetUrl("rtlStyle", "/cssNew/rtl-style.css") + "'/>";
        if ($headlinkfirst.length) {
            $headlinkfirst.before(linkElement1);
            $headlinklast.before(linkElement2);
        }
        else {
            $head.append(linkElement1);
            $head.append(linkElement2);
        }

        //$('head').append('<link href="/cssNew/bootstrap-rtl.min.css" rel="stylesheet" type="text/css"/>');
        //$('head').append('<link href="/cssNew/rtl-style.css" rel="stylesheet" type="text/css"/>');
        removeStylesheet("/cssNew/bootstrap.min.css");
        selectedCurrency = $('#hdnCurrencyENG').val();

        //debugger;
        //item details bottom scroller
        //var $owl = $('.owl-carousel').owlCarousel({
        //    rtl: true
        //});
        //$owl.trigger('refresh.owl.carousel');
    }
    else {
        $("html").removeAttr("lang");
        $("html").removeAttr("dir");
        $("body").removeClass("rtl");

        var $head = $("head");
        var $headlinklast = $head.find("link[rel='stylesheet']:first");
        var linkElement = "<link rel='stylesheet' type='text/css' href='"
            + assetUrl("bootstrap", "/cssNew/bootstrap.min.css") + "'/>";
        if ($headlinklast.length) {
            $headlinklast.before(linkElement);
        }
        else {
            $head.append(linkElement);
        }

        removeStylesheet("/cssNew/rtl-style.css");
        removeStylesheet("/cssNew/bootstrap-rtl.min.css");
        selectedCurrency = $('#hdnCurrencyArab').val();

        //debugger;
        //var $owl = $('.owl-carousel').owlCarousel({
        //    rtl: false
        //});
        //$owl.trigger('refresh.owl.carousel');
    }
    //$('.dropdown-content').hide();
    $('#selectedLang').val(val);


    $(".Btnlang").each(function (index) {
        $(this).html(Displayval);
        $(this).val(Displayval);
    });

    //$("#BtnlangDesktop").each(function (index) {
    //    $(this).html(Displayval);
    //    $(this).val(Displayval);
    //});
    BindLangLabels(val);
    if (($('#hdnDesignName').val() == "Design3") && parseInt($('#hdnBranchId').val()) == 0) {
        BindSectionMenu();
    }
    else if ($("#hdnDesignName").val() == "Design4" || $("#hdnDesignName").val() == "Design1") {
        BindCategory(0);
    }
    else {
        BindCategory(selectedCategoryId);
    }

    debugger;
    if (selectedCategoryId > 0 && $("#hdnDesignName").val() != "Design4" && $("#hdnDesignName").val() != "Design1") {
        //check pass 0 to selected category have subcate then 1
        OnCategoryClick(selectedCategoryId, 0);
    }
    debugger;

    //if ($('#selectedLang').val() == "EN") {
    //    var $owl = $('.owl-carousel').owlCarousel({
    //        rtl: false
    //    });
    //    $owl.trigger('refresh.owl.carousel');
    //}
    //else {
    //    var $owl = $('.owl-carousel').owlCarousel({
    //        rtl: true
    //    });
    //    $owl.trigger('refresh.owl.carousel');
    //}
    var IsOnlyConfirmCartBind = false;
    BindCart(CartDetails, CartComments, CartChoicesItems, CartExtraItems, isfromWaiterTemp, IsOnlyConfirmCartBind);
    BindAreaDropdown();

    // Background refresh so the saved addresses / pickup branches come back in
    // the newly selected language. silent:true because the customer is toggling
    // language, not checking out - a failed lookup here must not throw
    // "Service Not Connected, Please Contact Your Manager." at them. The same
    // failure is still reported from customerInfoNext(), where the Delivery step
    // genuinely cannot continue without the data.
    BindDeliveryServiceData({ silent: true });
}
function BindLangLabels(val) {
    var objCartDetails = {
        selectedLang: val
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objCartDetails),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetLangLabels",
        success: function (result) {
            if (result.Message == "Success") {
                var objLabels = JSON.parse(result.dtLabels);
                $('#btnMenu').html(objLabels[0].LabelTest);
                //$('#btnMenuDesktop').html(objLabels[0].LabelTest);

                $('#btnCheckOut').html(objLabels[1].LabelTest);
                $('#btnclearCart').html(objLabels[2].LabelTest);
                //$('#btnclearCartConfirm').html(objLabels[2].LabelTest);
                $('#divUserInformation').html(objLabels[3].LabelTest);
                $('#divSetupNameMobileEmail').html(objLabels[4].LabelTest);
                $('#divDeliveryServiceType').html(objLabels[5].LabelTest);
                $('#divSelectDeliveryPickup').html(objLabels[6].LabelTest);
                $('#divYourAddress').html(objLabels[7].LabelTest);
                $('#divSetupYourAddress').html(objLabels[8].LabelTest);
                $('#divMakePayment').html(objLabels[9].LabelTest);
                $('#divSelectPaymentOptions').html(objLabels[10].LabelTest);
                $('#divCompleted').html(objLabels[11].LabelTest);
                $('#divReviewandSubmit').html(objLabels[12].LabelTest);
                $('#divEnteryourAccountDetails').html(objLabels[13].LabelTest);

                $('#lblFirstName').html(objLabels[14].LabelTest);
                $('#fname').attr("placeholder", objLabels[14].LabelTest);
                $('#spnPleaseenteryourfirstname').html(objLabels[15].LabelTest);

                $('#lblLastName').html(objLabels[16].LabelTest);
                $('#lname').attr("placeholder", objLabels[16].LabelTest);
                $('#spnPleaseenteryourlastname').html(objLabels[17].LabelTest);

                $('#lblPhone').html(objLabels[18].LabelTest);
                $('#phone').attr("placeholder", objLabels[18].LabelTest);
                $('#spnPleaseenteryourphonenumber').html(objLabels[19].LabelTest);

                $('#lblEmail').html(objLabels[20].LabelTest);
                $('#email').attr("placeholder", objLabels[20].LabelTest);
                $('#spnPleaseenteryouremailaddress').html(objLabels[21].LabelTest);

                $('#lblArea1').html(objLabels[39].LabelTest);
                $('#divSelectDeleveryType').html(objLabels[22].LabelTest);
                $('#lblOrderType').html(objLabels[23].LabelTest);
                $('#spnPleaseselectOrderType').html(objLabels[24].LabelTest);
                $('#divSetupYourAddress').html(objLabels[25].LabelTest);
                $('#spnPleaseselectyourArea').html(objLabels[26].LabelTest);

                $('#lblBlock').html(objLabels[27].LabelTest);
                $('#Block').attr("placeholder", objLabels[28].LabelTest);
                $('#spnPleaseenteryourBlock').html(objLabels[28].LabelTest);

                $('#lblStreet').html(objLabels[29].LabelTest);
                $('#Street').attr("placeholder", objLabels[29].LabelTest);
                $('#spnPleaseenteryourStreet').html(objLabels[30].LabelTest);

                $('#lblBuilding').html(objLabels[31].LabelTest);
                $('#Building').attr("placeholder", objLabels[31].LabelTest);
                $('#spnPleaseenteryourBuilding').html(objLabels[32].LabelTest);

                $('#lblFloor').html(objLabels[33].LabelTest);
                $('#Floor').attr("placeholder", objLabels[33].LabelTest);
                $('#spnPleaseenteryourFloor').html(objLabels[34].LabelTest);

                $('#lblFlat').html(objLabels[35].LabelTest);
                $('#Flat').attr("placeholder", objLabels[35].LabelTest);
                $('#spnPleaseenteryourFlat').html(objLabels[36].LabelTest);

                $('#lblLandmark').html(objLabels[37].LabelTest);
                $('#Landmark').attr("placeholder", objLabels[37].LabelTest);
                $('#spnPleaseenteryourLandmark').html(objLabels[38].LabelTest);

                $('#lblArea').html(objLabels[39].LabelTest);
                $('#Area').attr("placeholder", objLabels[39].LabelTest);
                $('#spnPleaseselectyourArea').html(objLabels[40].LabelTest);

                $('#divEnteryourPaymentDetails').html(objLabels[41].LabelTest);

                $('#h1PaymentMethod').html(objLabels[42].LabelTest);
                $('#pChooseyourpreferredpaymentmethod').html(objLabels[43].LabelTest);
                $('#pKNET').html(objLabels[44].LabelTest);
                $('#pCreditCard').html(objLabels[45].LabelTest);
                $('#pCashondelivery').html(objLabels[46].LabelTest);
                $('#h4ReviewyourDetailsandSubmit').html(objLabels[47].LabelTest);
                $('#h6UserInformation').html(objLabels[48].LabelTest);
                $('#h6DeliveryServiceType').html(objLabels[49].LabelTest);
                $('#h6AddressInformation').html(objLabels[50].LabelTest);
                $('#h6PaymentDetails').html(objLabels[51].LabelTest);
                $('#btnPrevious').html(objLabels[52].LabelTest);
                $('#btnSubmit').html(objLabels[53].LabelTest);
                $('#btnNext').html(objLabels[54].LabelTest);

                $('#spnTotal').html(objLabels[55].LabelTest);
                $('#spnTotalConfirm').html(objLabels[55].LabelTest);

                $('#OrderType_Delivery').html(objLabels[56].LabelTest);
                $('#OrderType_Pickup').html(objLabels[57].LabelTest);
                $('#optionSelect').html(objLabels[58].LabelTest);
                $('#optionSelect1').html(objLabels[58].LabelTest);

                jQuery.each($('.txtComment'), function (i, val) {
                    $(this).attr("placeholder", objLabels[59].LabelTest);
                });
                $('#snackbar').html(objLabels[60].LabelTest);

                //$('#validationlblFistName').val(objLabels[56].LabelTest);
                validationlblFistName = objLabels[61].LabelTest;
                validationPopup = objLabels[62].LabelTest;
                ValconfirmButtonText = objLabels[63].LabelTest;
                validationlblLastName = objLabels[64].LabelTest;
                validationlblPhone = objLabels[65].LabelTest;
                validationlblPhoneMin = objLabels[66].LabelTest;
                validationlblPhoneReq = objLabels[67].LabelTest;
                validationlblEmail = objLabels[68].LabelTest;
                validationlblEmailNotValid = objLabels[69].LabelTest;
                validationlblOrderType = objLabels[70].LabelTest;
                validationlblArea = objLabels[71].LabelTest;
                validationlblBlock = objLabels[72].LabelTest;
                validationlblStreet = objLabels[73].LabelTest;
                validationlblBuilding = objLabels[74].LabelTest;

                validationlblFlat = objLabels[75].LabelTest;
                validationlblFloor = objLabels[76].LabelTest;
                validationlblPaymentType = objLabels[77].LabelTest;

                $('#txtTrackorderNumber').attr("placeholder", objLabels[78].LabelTest);
                $('#msgTrackOrderBlank').html(objLabels[78].LabelTest);
                $('#msgTrackOrderWrong').html(objLabels[79].LabelTest);
                $('#msgContactManager').html(objLabels[80].LabelTest);
                $('#spnDeliveryChargesConfirm').html(objLabels[81].LabelTest);

                $('#btnGenerateOrder').html(objLabels[82].LabelTest);
                $('#btnCheckout').html(objLabels[83].LabelTest);


                $('#lblheaderCart').html(objLabels[84].LabelTest);
                $('#lblSelectExtraOption').html(objLabels[85].LabelTest);
                $('#lblLeftMenuMenu').html(objLabels[86].LabelTest);



                $('#lblSectionMenuButton').html(objLabels[87].LabelTest);
                msgSectionBranchSelection = objLabels[88].LabelTest;
                $('#btnSectionDivClose').html(objLabels[89].LabelTest);
                $('#lblReservationButton').html(objLabels[90].LabelTest);
                $('#lblReservationHeader').html(objLabels[90].LabelTest);
                $('#lblReservationCustomerInfoHeader').html(objLabels[90].LabelTest);
                $('#lblReservationConfirmHeader').html(objLabels[90].LabelTest);


                $('#lblNameOfGuests').html(objLabels[91].LabelTest);
                $('#lblScheduleDataAndTime').html(objLabels[92].LabelTest);
                $('#btnlblCheckAvailability').html(objLabels[93].LabelTest);



                msgerrorval = objLabels[94].LabelTest;
                msgPleaseSelectValidSlot = objLabels[95].LabelTest;
                $('#btnlblalertColse').html(objLabels[96].LabelTest);
                $('#btnlblReservationConfirm').html(objLabels[97].LabelTest);


                $('#lblCustomerFullName').html(objLabels[98].LabelTest);
                $('#lblCustomerPhoneNumber').html(objLabels[99].LabelTest);
                $('#lblCustomerEmail').html(objLabels[100].LabelTest);
                $('#lblSpecialRequest').html(objLabels[101].LabelTest);
                $('#btnlblReservationSubmit').html(objLabels[102].LabelTest);

                msgInsertCustomerName = objLabels[103].LabelTest;
                msgInsertCustomerMobile = objLabels[104].LabelTest;
                msgInsertCustomerEmail = objLabels[105].LabelTest;
                msginsertValidEmail = objLabels[106].LabelTest;

                $('#lblNameOfGuestsConfirm').html(objLabels[91].LabelTest);
                $('#ReservationConfirmThankyou').html(objLabels[107].LabelTest);
                $('#btnlblConfirmHome').html(objLabels[108].LabelTest);

                msgBranchNotSelected = objLabels[109].LabelTest;
                $('#lblConfirmationIdConfirm').html(objLabels[110].LabelTest);

                $('#lblSelectExtraComments').html(objLabels[111].LabelTest);
                $('#lblSelectExtraItems').html(objLabels[112].LabelTest);
                $('#lblUnitPrice').html(objLabels[113].LabelTest);
                $('#lblExtraprice').html(objLabels[114].LabelTest);
                $('#lblTotalprice').html(objLabels[115].LabelTest);

                textlblUnitPrice = objLabels[113].LabelTest;
                textlblExtraprice = objLabels[114].LabelTest;
                textlblTotalprice = objLabels[115].LabelTest;
                placeholderComments = objLabels[116].LabelTest;


                //$(".lblUnitPrice").each(function (index) {
                //    $(this).html(objLabels[113].LabelTest);
                //});
                //$(".lblExtraprice").each(function (index) {
                //    $(this).html(objLabels[114].LabelTest);
                //});
                //$(".lblTotalprice").each(function (index) {
                //    $(this).html(objLabels[115].LabelTest);
                //});

                ///////////Start Customer information labels bind////////////
                $('#lblSelectItemsChoice').html(objLabels[117].LabelTest);
                $('#lblUserInformationTag').html(objLabels[118].LabelTest);

                $('#txtCustomerFullname').attr("placeholder", objLabels[98].LabelTest);
                $('#txtCustomerPhoneNumber').attr("placeholder", objLabels[99].LabelTest);
                $('#txtCustomerEmailnew').attr("placeholder", objLabels[100].LabelTest);
                ///////////End Customer information labels bind////////////


                ///////////Start Customer AddressServices labels bind////////////
                $('#CustInfobtnNext').html(objLabels[119].LabelTest);
                $('#CustInfobtnPrevious').html(objLabels[120].LabelTest);

                $('#DelServbtnNext').html(objLabels[119].LabelTest);
                $('#DelServbtnPrevious').html(objLabels[120].LabelTest);
                $('#DelAddressbtnNext').html(objLabels[119].LabelTest);
                $('#DelAddressbtnPrevious').html(objLabels[120].LabelTest);
                $('#DelAddressbtnNext').html(objLabels[119].LabelTest);
                $('#DelPaymentPrevious').html(objLabels[120].LabelTest);



                $('#lblDeliveryService').html(objLabels[121].LabelTest);
                $('#lblDSPickup').html(objLabels[122].LabelTest);
                $('#lblDSDelivery').html(objLabels[123].LabelTest);
                $('#lblDSOrderTime').html(objLabels[124].LabelTest);
                $('#lblDSOrderTime2').html(objLabels[124].LabelTest);
                $('#lblDSChooseLocation').html(objLabels[125].LabelTest);

                lblDSArea = objLabels[126].LabelTest;
                lblDSBlock = objLabels[127].LabelTest;
                lblDSStreet = objLabels[128].LabelTest;
                lblDSLane = objLabels[129].LabelTest;
                lblDSBuilding = objLabels[130].LabelTest;
                lblDSFloor = objLabels[131].LabelTest;
                lblDSFlat = objLabels[132].LabelTest;
                lblDSDiffrentLactionText = objLabels[133].LabelTest;
                lblDSChooesLocationText = objLabels[134].LabelTest;

                debugger;
                var ISDeliveryDateToday = "1";
                if (CustomerDetails != null) {
                    ISDeliveryDateToday = CustomerDetails["ISDeliveryDateToday"];
                }

                if ($('#txtDeliveryServiceDate').val() == "Today"
                    || $('#txtDeliveryServiceDate').val() == objLabels[135].LabelTest
                    || ISDeliveryDateToday == "1") {
                    $('#txtDeliveryServiceDate').val(objLabels[135].LabelTest);
                    TodayLable = objLabels[135].LabelTest;
                }

                if ($('#txtDeliveryPickupServiceDate').val() == "Today"
                    || $('#txtDeliveryPickupServiceDate').val() == objLabels[135].LabelTest
                    || ISDeliveryDateToday == "1") {
                    $('#txtDeliveryPickupServiceDate').val(objLabels[135].LabelTest);
                }

                lblASAP = objLabels[136].LabelTest;
                ///////////End Customer AddressServices labels bind////////////

                ///////////Start Delivery Address labels bind////////////
                $('#lblDADeliveryAddress').html(objLabels[137].LabelTest);
                $('#lblADHome').html(objLabels[138].LabelTest);
                $('#lblADApartment').html(objLabels[139].LabelTest);
                $('#lblADOffice').html(objLabels[140].LabelTest);

                ////Start Home tab lables
                $('#lblADHomeBlock').html(objLabels[141].LabelTest);
                $('#lblADHomeStreet').html(objLabels[142].LabelTest);
                $('#lblADHomeHouseNo').html(objLabels[143].LabelTest);
                $('#lblADHomeLandmark').html(objLabels[144].LabelTest);

                $('#txtHomeBlock').attr("placeholder", objLabels[141].LabelTest);
                $('#txtHomeStreet').attr("placeholder", objLabels[142].LabelTest);
                $('#txtHomeFlat').attr("placeholder", objLabels[143].LabelTest);
                $('#txtHouseLandmark').attr("placeholder", objLabels[144].LabelTest);


                //Start Apartment tab lables
                $('#lblADAppartBlock').html(objLabels[141].LabelTest);
                $('#lblADAppartStreet').html(objLabels[142].LabelTest);
                $('#lblADAppartBuilding').html(objLabels[145].LabelTest);
                $('#lblADAppartFloor').html(objLabels[146].LabelTest);
                $('#lblADAppartFlatNo').html(objLabels[147].LabelTest);
                $('#lblADAppartLandmark').html(objLabels[144].LabelTest);


                $('#txtApartmentBlock').attr("placeholder", objLabels[141].LabelTest);
                $('#txtApartmentStreet').attr("placeholder", objLabels[142].LabelTest);
                $('#txtApartmentBuilding').attr("placeholder", objLabels[145].LabelTest);
                $('#txtApartmentFloor').attr("placeholder", objLabels[146].LabelTest);
                $('#txtApartmentFlatNo').attr("placeholder", objLabels[147].LabelTest);
                $('#txtApartmentLandmark').attr("placeholder", objLabels[144].LabelTest);


                ////Start Office tab lables
                $('#lblADOfficeBlock').html(objLabels[141].LabelTest);
                $('#lblADOfficeStreet').html(objLabels[142].LabelTest);
                $('#lblADOfficeBuilding').html(objLabels[145].LabelTest);
                $('#lblADOfficeFloor').html(objLabels[146].LabelTest);
                $('#lblADOfficeFlatNo').html(objLabels[147].LabelTest);
                $('#lblADOfficeLandmark').html(objLabels[144].LabelTest);

                $('#txtOfficeBlock').attr("placeholder", objLabels[141].LabelTest);
                $('#txtOfficeStreet').attr("placeholder", objLabels[142].LabelTest);
                $('#txtOfficeBuilding').attr("placeholder", objLabels[145].LabelTest);
                $('#txtOfficeFloor').attr("placeholder", objLabels[146].LabelTest);
                $('#txtOfficeFlat').attr("placeholder", objLabels[147].LabelTest);
                $('#txtOfficeLandmark').attr("placeholder", objLabels[144].LabelTest);
                ///////////End Delivery Address labels bind////////////

                //////////////////////Start Payment View lables///////////////
                $('#lblPaymentMethods').html(objLabels[148].LabelTest);
                $('#lblPaymentQuote').html(objLabels[149].LabelTest);
                $('#lblPaymentCash').html(objLabels[150].LabelTest);
                $('#lblPaymentKNET').html(objLabels[151].LabelTest);
                $('#lblPaymentDeliveryInfo').html(objLabels[152].LabelTest);
                $('#lblPaymentOrderRecap').html(objLabels[153].LabelTest);
                $('#lblPaymentOrdarlist').html(objLabels[154].LabelTest);
                $('#lblPaymentChangeOrder').html(objLabels[155].LabelTest);
                $('#lblPaymentBillAmount').html(objLabels[156].LabelTest);
                $('#lblPaymentDelivery').html(objLabels[157].LabelTest);
                $('#lblPaymentDiscount').html(objLabels[158].LabelTest);
                $('#lblPaymentNetAmount').html(objLabels[159].LabelTest);
                $('#lblPaymentViewDetails').html(objLabels[160].LabelTest);
                //$('#lblPaymentConfirmation').html(objLabels[161].LabelTest);

                $('#lblPaymentConfirmation').html(objLabels[161].LabelTest);
                $('#lblOCOrderInformation').html(objLabels[162].LabelTest);
                $('#lblOCPrint').html(objLabels[163].LabelTest);
                $('#lblOCHome').html(objLabels[164].LabelTest);
                $('#lblOCTrackorder').html(objLabels[165].LabelTest);
                $('#lblTOTrackorder').html(objLabels[165].LabelTest);
                $('#lblOCOrder').html(objLabels[166].LabelTest);
                $('#lblOCOrderStatus').html(objLabels[167].LabelTest);
                $('#lblOCPending').html(objLabels[168].LabelTest);
                $('#lblOCOrderTotal').html(objLabels[169].LabelTest);
                $('#lblOCPaymentMehtod').html(objLabels[170].LabelTest);
                $('#lblOCDeliveryInfo').html(objLabels[171].LabelTest);

                btnPaymentProcessOrder = objLabels[172].LabelTest;
                btnPaymentProceedtoPayment = objLabels[173].LabelTest;
                $('#lblPaymentConfirmation').html(btnPaymentProcessOrder);
                //////////////////////End Payment View lables///////////////
                lblADLandmark = objLabels[174].LabelTest;
                $('#lblOrderConfirmOrderDateLabel').html(objLabels[175].LabelTest);

                $('#lblTrackOrdOrdernumber').html(objLabels[176].LabelTest);
                $('#lblTOFeedback').html(objLabels[177].LabelTest);

                //update summary data with updated language
                BindSummaryTabData();
                if (typeof KTWizard4 !== 'undefined') {
                    KTWizard4.init();
                }


                //$('input[name="fname"]').rules('add', {
                //    messages: {
                //        required: "new message for field 1"
                //    }
                //});
            }
        }
    });
}
function BindCart(objCartDetails, cartComments, cartChoicesItems, cartExtraItems, isfromWaiter, IsOnlyConfirmCartBind) {
    debugger;
    var ObjDataCartDetails = [];
    $.each(objCartDetails, function (i, obj) {
        var item = {}
        item["UID"] = obj.UID;
        item["ItemId"] = obj.I;
        item["HID"] = obj.O;
        item["qty"] = obj.Q;
        item["Comments"] = obj.C;
        item["ChoiceId"] = obj.CH;
        ObjDataCartDetails.push(item);
    });
    isfromWaiterTemp = isfromWaiter;
    var objdata = {
        cartdetails: ObjDataCartDetails,
        cartChoices: cartChoicesItems,
        cartExtraItems: cartExtraItems,
        cartComments: cartComments,
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetCartViewItems",
        success: function (result) {
            if (result.Message == "Success") {
                debugger;
                var Items = result.dtItems;
                var ChoicesItems = JSON.parse(result.dtChoicesItems);
                var ExtraItems = JSON.parse(result.dtExtraItems);
                var Comments = JSON.parse(result.dtComments);
                //if click on confirm view tab click then not need to bind cartitems
                if (!IsOnlyConfirmCartBind) {
                    BindCartItems(Items, isfromWaiterTemp, Comments, ChoicesItems, ExtraItems);
                }
                if (IsOnlyConfirmCartBind) {
                    BindConfirmCartItems(Items, isfromWaiterTemp, Comments, ChoicesItems, ExtraItems);
                }
                /*var Items = result.dtItems;
                BindSelectedCategoryItems(Items);*/
            }
        }
    });
}




function BindCartItems(Items, isfromWaiter, cartComments, cartChoicesItems, cartExtraItems) {
    debugger;
    var Mainstr = "";
    var selectedCat_num = 0;
    //var selectedCate="";
    var categoryidList = [];
    //items details view clear becuase some ids are common in cart view like extra items and comments
    $('#divExtraItems').html("");
    $('#divExtraComments').html("");
    $('#cartitemsMainDiv').html("");
    var Subtotal = 0.000;


    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var CategoryName = "";
        var INGREDIENT = "";
        var ChoiceName = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            CategoryName = item.CAT_NAME;
            selectedCurrency = $('#hdnCurrencyENG').val();
            ChoiceName = item.ChoiceName;
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            CategoryName = item.CAT_NAME_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
            ChoiceName = item.ChoiceName_ARABIC;
        }
        $.each(categoryidList, function (i, cat) {
            if (cat != item.CAT_NUM && categoryidList.indexOf(item.CAT_NUM) == -1) {
                var strcategory = '<h3 id="cartCate_' + item.CAT_NUM + '" class="category-name mt-4">' + CategoryName + '</h3>' +
                    '<div id="cartCateItems_' + item.CAT_NUM + '">' +
                    '</div>';
                categoryidList.push(item.CAT_NUM)
                $('#cartitemsMainDiv').append(strcategory);
            }
        });

        if (categoryidList.length == 0) {
            var strcategory = '<h3 id="cartCate_' + item.CAT_NUM + '" class="category-name">' + CategoryName + '</h3>' +
                '<div id="cartCateItems_' + item.CAT_NUM + '">' +
                '</div>';
            categoryidList.push(item.CAT_NUM);
            $('#cartitemsMainDiv').append(strcategory);
        }

        var strExtraItems = "";
        var extraItemsTotal = 0;
        var isextraitems = 0
        $.each(cartExtraItems, function (i, extraItem) {
            if (extraItem.UID == item.UID && extraItem.MainItemId == item.id) {
                isextraitems = 1;
                extraItemsTotal = extraItemsTotal + round(extraItem.Price, decimalPlace).toFixed(decimalPlace);
                strExtraItems = strExtraItems + ' <li>' + extraItem.ItemName + '  ' + round(extraItem.Price, decimalPlace).toFixed(decimalPlace) + ' </li> ';
            }
        });

        //var strItemChoice = "";
        //if (ChoiceName != "") {
        //    strItemChoice = ' <ul class="extra clearfix" style="margin-bottom:0px !Important;"><li>' + ChoiceName + ' ' + parseFloat(item.PRICE).toFixed(3) + ' <a  title="cansal"><i class="fa"></i></a></li></ul> ';
        //}
        var strChoiceItems = "";
        var ChoiceItemsTotal = 0;
        var ischoiceitems = 0
        $.each(cartChoicesItems, function (i, choiceItem) {
            if (choiceItem.UID == item.UID && choiceItem.MainItemId == item.id) {
                ischoiceitems = 1;
                ChoiceItemsTotal = ChoiceItemsTotal + round(choiceItem.Price, decimalPlace).toFixed(decimalPlace);
                //strChoiceItems = strChoiceItems + ' <li>' + choiceItem.ItemName + '  ' + parseFloat(choiceItem.Price).toFixed(3) + ' <a onclick="cartConfirmRemvoeChoiceItem(this,' + choiceItem.MainItemId + ',' + choiceItem.ChoiceItemId + ',' + choiceItem.UID+')" href="#" title="cansal"><i class="fa fa-times-circle"></i></a></li> ';
                strChoiceItems = strChoiceItems + ' <li>' + choiceItem.ItemName + '  ' + round(choiceItem.Price, decimalPlace).toFixed(decimalPlace) + '</li> ';

            }
        });



        var strExtraComments = "";
        var isExtraComments = 0;
        $.each(cartComments, function (i, extraComments) {
            if (extraComments.UID == item.UID && extraComments.MainItemId == item.id) {
                isExtraComments = 1;
                strExtraComments = strExtraComments + ' <li>' + extraComments.Comment + ' <a onclick="cartConfirmRemvoeComment(this,' + extraComments.CommentId + ',' + extraComments.MainItemId + ')" href="#" title="cansal"><i class="fa fa-times-circle"></i></a></li> ';
            }
        });
        debugger;
        var str = '<div id="Item_' + item.UID + '" data-val=' + item.CAT_NUM + ' class="card mb-3">\
            <input id="hdnItemINGREDIENT_' + item.id + '" type="hidden" value="' + INGREDIENT + '"> \
            <input id="hdnITEM_NAME_' + item.id + '" type="hidden" value="' + ItemName + '">\
            <input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden" value="' + item.IMAGENAME + '">\
            <input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '">\
            <input id="hdnItem_PRICE_' + item.id + '" type="hidden" value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '">\
            <input id="hdnItem_TotalPRICE_' + item.id + '" type="hidden" value="' + round(item.TotalPrice, decimalPlace).toFixed(decimalPlace) + '">\
                <div class="card-body">\
                    <div class="media">\
                        <span class="mr-2 product-img">\
                            <img src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="' + item.IMAGENAME + '" />\
                        </span>\
                        <div class="media-body">\
                            <div class="d-flex justify-content-between">\
                                <h4 class="pb-0">' + ItemName + '</h4>\
                                <div class="d-flex item-select-block mb-1">\
                                    <a href="#"  onclick="Minusecardclick('+ item.UID + ',' + item.id + ');" class="btn btn-primary icon-btn">\
                                        <i class="fa fa-minus" aria-hidden="true"></i>\
                                    </a>\
                                    <div id="divItemwiseCount_' + item.UID + '" class="form-control" type="text" name="" value="2" >' + item.qty + '</div>\
                                    <a href="#" onclick="addItemclick('+ item.UID + ',' + item.id + ',' + item.HID + ',1,0);" class="btn btn-primary icon-btn">\
                                        <i class="fa fa-plus" aria-hidden="true"></i>\
                                    </a>\
                                </div>\
                            </div>\
                            <ul class="Choice clearfix">\
                                    '+ strChoiceItems + '\
                            </ul>\
                            <ul class="comments clearfix">\
                                    '+ strExtraComments + '\
                            </ul>\
                            <ul class="extra clearfix">\
                                '+ strExtraItems + '\
                            </ul>\
                        </div>\
                    </div>\
                    <textarea id="comments_' + item.id + '_' + item.UID + '" class="form-control" placeholder="' + placeholderComments + '" value="' + item.Comments + '">' + item.Comments + '</textarea>\
                </div>\
                <div class="card-footer">\
                    <div class="price-outer d-flex align-items-end justify-content-between">\
                        <div class="price-block">\
                            <label id="lblUnitPrice">'+ textlblUnitPrice + '</label>\
                            <span class="price"><em>' + selectedCurrency + '.</em>' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</span>\
                        </div>\
                        <div class="price-block extra-price">\
                            <label id="lblExtraprice">'+ textlblExtraprice + '</label>\
                            <span class="price" id="ExtraItemTotalAmt_' + item.id + '_' + item.UID + '"><em>' + selectedCurrency + '.</em>' + round(extraItemsTotal, decimalPlace).toFixed(decimalPlace) + '</span>\
                        </div>\
                        <div class="price-block total-price">\
                            <label id="lblTotalprice">'+ textlblTotalprice + '</label>\
                            <span class="price" id="ItemTotalamt_' + item.id + '_' + item.UID + '"><em>' + selectedCurrency + '.</em>' + round(((parseInt(item.qty) * parseFloat(extraItemsTotal)) + parseFloat(item.TotalPrice)), decimalPlace).toFixed(decimalPlace) + '</span>\
                        </div>\
                    </div>\
                </div>\
            </div >\
        ';


        $('#cartCateItems_' + item.CAT_NUM).append(str);
        Subtotal = Subtotal + (parseInt(item.qty) * parseFloat(extraItemsTotal)) + Number.parseFloat(item.TotalPrice);
    });
    $('#divSubtotal').html(selectedCurrency + ". " + round(Subtotal, decimalPlace).toFixed(decimalPlace));
    $('#hdnSubtotal').val(round(Subtotal, decimalPlace).toFixed(decimalPlace));
    if ($('#lblPaymentBillAmountVal').length > 0) {
        $('#lblPaymentBillAmountVal').html(round(Subtotal, decimalPlace).toFixed(decimalPlace));
        $('#lblPaymentBillAmountCurrency').html(selectedCurrency + ". ");
    }
}


function BindConfirmCartItems(Items, isfromWaiter, cartComments, cartChoicesItems, cartExtraItems) {
    debugger;
    var Mainstr = "";
    var selectedCat_num = 0;
    //var selectedCate="";
    var categoryidList = [];
    $('#cartitemsMainDivConfirm').html("");
    var Subtotal = 0.000;


    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var CategoryName = "";
        var INGREDIENT = "";
        var ChoiceName = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            CategoryName = item.CAT_NAME;
            selectedCurrency = $('#hdnCurrencyENG').val();
            ChoiceName = item.ChoiceName;
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            CategoryName = item.CAT_NAME_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
            ChoiceName = item.ChoiceName_ARABIC;
        }
        $.each(categoryidList, function (i, cat) {
            if (cat != item.CAT_NUM && categoryidList.indexOf(item.CAT_NUM) == -1) {
                var strcategory = "<div id='cartCate_Confirm_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                    "" + CategoryName + "" +
                    "</div>" +
                    "<div id='cartCateItems_Confirm_" + item.CAT_NUM + "'>" +
                    "</div>";
                categoryidList.push(item.CAT_NUM)
                $('#cartitemsMainDivConfirm').append(strcategory);
            }
        });

        if (categoryidList.length == 0) {
            var strcategory = "<div id='cartCate_Confirm_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                "" + CategoryName + "" +
                "</div>" +
                "<div id='cartCateItems_Confirm_" + item.CAT_NUM + "'>" +
                "</div>";
            categoryidList.push(item.CAT_NUM);
            $('#cartitemsMainDivConfirm').append(strcategory);
        }



        var str = "";
        str = "<div id='Item_Confirm_" + item.id + "' data-val=" + item.CAT_NUM + " class='ng-tns-c0-81 ng-star-inserted'>" +
            "<input id='hdnItemINGREDIENT_Confirm_" + item.id + "' type='hidden' value='" + INGREDIENT + "'>" +
            "<input id='hdnITEM_NAME_Confirm_" + item.id + "' type='hidden' value='" + ItemName + "'>" +
            "<input id='hdnItem_IMAGENAME_Confirm_" + item.id + "' type='hidden' value='" + item.IMAGENAME + "'>" +
            "<input id='hdnItem_VideoNAME_Confirm_" + item.id + "' type='hidden' value='" + item.Video + "'>" +
            "<input id='hdnItem_PRICE_Confirm_" + item.id + "' type='hidden' value='" + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + "'>" +
            "<input id='hdnItem_PRICE_Confirm_Currency" + item.id + "' type='hidden' value='" + selectedCurrency + "'>" +
            "<input id='hdnItem_TotalPRICE_Confirm_" + item.id + "' type='hidden' value='" + round(item.TotalPrice, decimalPlace).toFixed(decimalPlace) + "'>" +
            "<button id='btnItem_Confirm_" + item.id + "' class='menu-item-anchor' prevent-double-click=''>" +
            "<div class='menu-Cat-item item item-block' style='background-color: rgb(255, 255, 255); opacity: 1;'>" +
            "<div onclick='OnItemClick(" + item.id + "," + item.HID + ");' class='menu-item-thumbnail ng-tns-c0-81 ng-star-inserted' item-start='' style='align-self: flex-start;'>" +
            "<img class='ng-tns-c0-81' src='../../ThumbnailImages/" + item.IMAGENAME + "?fit=crop&amp;w=90&amp;h=90&amp;q=100&amp;fm=jpg' width='100' height='100' style='object-fit: cover;'>" +
            "</div>" +
            "<div class='item-inner'>" +
            "<div class='input-wrapper'>" +
            "<div class='label label-ios ng-star-inserted' style=''>" +
            "<div class='ng-tns-c0-81 Itemrightcontent'>" +
            "<div style='width:100% !important;'>" +
            "<h1 onclick='OnItemClick(" + item.id + "," + item.HID + ");' class='menu-item-header clsitemNameHeaderCart'>" + ItemName + "</h1>" +

            "</div>" +
            "<div style='clear:both !important;'></div>" +
            "<div  class='ng-tns-c0-81'>" +
            "<div class='menu-item-footer ng-star-inserted'>" +

            "<div onclick='OnItemClick(" + item.id + "," + item.HID + ");' style='height:30px;float:left;padding-top:5px;'><span id='ItemTotalamt_Confirm_" + item.id + '_' + item.UID + "' class='item-currency ng-star-inserted' style='color: var(--primary);'>" +
            "" + selectedCurrency + ". " + round(item.TotalPrice, decimalPlace).toFixed(decimalPlace) + "" +
            "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>" +
            "</span></div>" +

            "<div style='line-height: 30px;float:right !important; margin-right:5px;'>" +
            "<div style='width:32px;float:left;display:none;' onclick='Minusecardclick(" + item.UID + "," + item.id + ");' class='addbutton'>-</div>" +
            "<div id='divItemwiseCount_Confirm_" + item.UID + "' class='clsselectedQty' style=''>" + item.qty + "</div>" +
            "<div style='width:32px;float:left;display:none;' onclick='addItemclick(" + item.UID + "," + item.id + "," + item.HID + ",1,0);' class='addbutton'>+</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "<div>" +
            "<input type='text' readonly class='txtComment' id='comments_Confirm_" + item.id + "' placeholder='Comments' multiple  value=" + item.Comments + "/>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div><div class='button-effect'></div>" +
            "</div>" +
            "</button>" +
            "</div>";
        $('#cartCateItems_Confirm_' + item.CAT_NUM).append(str);
        Subtotal = Subtotal + round(item.TotalPrice, decimalPlace).toFixed(decimalPlace);
        //Mainstr=Mainstr + str;
    });
    $('#hdnSubtotal').val(round(Subtotal, decimalPlace).toFixed(decimalPlace));
    $('#divSubTotalConfirm').html(selectedCurrency + ". " + round(Subtotal, decimalPlace).toFixed(decimalPlace));
    if ($('#lblPaymentBillAmountVal').length > 0) {
        $('#lblPaymentBillAmountVal').html(round(Subtotal, decimalPlace).toFixed(decimalPlace));
        $('#lblPaymentBillAmountCurrency').html(selectedCurrency + ". ");;
    }
    var deliveryCharges = Number.parseFloat($('#hdnAreaDeliveryCharges').val());
    Subtotal = Subtotal + deliveryCharges;
    $('#divtotalConfirm').html(selectedCurrency + ". " + round(Subtotal, decimalPlace).toFixed(decimalPlace));
    $('#hdntotalAmountConfirm').val(round(Subtotal, decimalPlace).toFixed(decimalPlace));
    $('#cartFooterConfirm').show();
    $('#divDeliveryChargesConfirm').html(selectedCurrency + ". " + round(deliveryCharges, decimalPlace).toFixed(decimalPlace));
}

/*=============================================================================
  findMergeableCartLine(itemid, HID)

  Returns the UID of a basket line the incoming item can simply be added to, or
  0 when it needs a line of its own.

  Two lines are the same order only when NOTHING distinguishes them: same item,
  same size/option (HID), no comment, no choice, no extras. A line carrying a
  comment or an extra is a different request even though it is the same dish -
  "one burger" and "one burger, no onions" have to reach the kitchen as two
  lines, so those are never merged.

  The incoming add is checked too. This runs from the menu tile's + button,
  where nothing has been chosen, but the comment box can still be holding text
  from an item detail view that was open a moment ago; if it is, the add gets
  its own line rather than silently attaching that comment to an existing one.
=============================================================================*/
// One past the highest UID in the basket: the next line's identity.
function nextCartUID() {
    var maxUID = 0;
    $.each(CartDetails || [], function (i, obj) {
        var u = parseInt(obj.UID) || 0;
        if (u > maxUID) maxUID = u;
    });
    return maxUID + 1;
}

function findMergeableCartLine(itemid, HID) {
    // Anything selected on the way in means this is a distinct request.
    var incomingComment = ($('#commentsItemDetailsView').val() || '').trim();
    if (incomingComment.length) return 0;

    var choiceChecked = false;
    $('.ItemsChoice').each(function () { if ($(this).prop('checked')) choiceChecked = true; });
    if (choiceChecked) return 0;

    var extraChecked = false;
    $('.extraItems').each(function () { if ($(this).prop('checked')) extraChecked = true; });
    if (extraChecked) return 0;

    var match = 0;

    $.each(CartDetails || [], function (i, obj) {
        if (match) return;

        if (parseInt(obj.I) !== parseInt(itemid)) return;
        if (parseInt(obj.O) !== parseInt(HID)) return;      // different size / option
        if ((obj.C || '').toString().trim().length) return; // has a comment
        if (parseInt(obj.CH || 0) > 0) return;              // has a choice

        // Extras and choices are held against the LINE's UID, not the item id,
        // so a line is only plain when neither list mentions it.
        var hasExtras = false;
        $.each(CartExtraItems || [], function (j, e) {
            if (parseInt(e.UID) === parseInt(obj.UID)) hasExtras = true;
        });
        if (hasExtras) return;

        var hasChoices = false;
        $.each(CartChoicesItems || [], function (k, c) {
            if (parseInt(c.UID) === parseInt(obj.UID)) hasChoices = true;
        });
        if (hasChoices) return;

        match = parseInt(obj.UID);
    });

    return match;
}

function addDirectItemInToCartclick(UID, itemid, HID, IsFromCart) {
    $('#lblItemInfoQty').val("1");

    // Same plain item already in the basket? Add to that line instead of
    // starting another one. Without this the + button minted a fresh UID every
    // time - max(UID) + 1, which by definition matches nothing - so tapping it
    // three times produced three separate lines of one rather than one line
    // of three.
    var mergeUID = findMergeableCartLine(itemid, HID);
    if (mergeUID > 0) {
        $('#hdnSelectedUID').val(mergeUID);
        addItemclick(mergeUID, itemid, HID, IsFromCart, 1);
        // hdnSelectedUID is what the item detail view stamps onto any extra or
        // choice that gets ticked next. Leaving it pointing at the line we just
        // merged into would attach the next customisation to that line, so it
        // is put back to the next free number.
        $('#hdnSelectedUID').val(nextCartUID());
        return;
    }

    var itemUniqueId = nextCartUID();
    $('#hdnSelectedUID').val(itemUniqueId);

    addItemclick(itemUniqueId, itemid, HID, IsFromCart, 1);
}

function addItemclick(UID, itemid, HID, IsFromCart, IsFromDirectItemInToCartclick) {
    debugger;
    var qty = 0;
    if (IsFromDirectItemInToCartclick == 1) {
        qty = 1;
    }
    else {
        qty = parseInt($('#lblItemInfoQty').val());
        if (UID > 0) {
            qty = parseInt($('#divItemwiseCount_' + UID + '').html());
        }
    }

    //if (!(qty > 0) && $('#divItemwiseCount_' + UID + '').length > 0) {
    //    qty = parseInt($('#divItemwiseCount_' + UID + '').html());
    //}
    if (qty > 0) {
        var tempqty = 1;
        var tempqty = qty;

        var totalcnt = 0;
        var IsExists = 0;
        var tempCartDetails = CartDetails;

        //check group wise extra and choice items minimum qty selected or not else display alert
        debugger
        var IsvalidateExtraItem = true;
        IsvalidateExtraItem = IsFromCart == 1 ? true : validateExtraItemGrpselection();

        if (!IsvalidateExtraItem) {
            return;
        }

        var IsvalidateChoices = true;
        IsvalidateChoices = IsFromCart == 1 ? true : validateExtraChoicesGrpselection();

        if (!IsvalidateChoices) {
            return;
        }

        selectedItemid = itemid;

        $.each(tempCartDetails, function (i, obj) {
            //check here same item id and same extra items and same choices then only qty plus
            // for loop in CartExtraItems with selected UID and existing same itemid, all items are there then it is same. and plus qty and remove new extras from cookiesObj
            //selectedExtras = CartExtraItems.filter(function (i, n) {
            //    return n.MainItemId === itemid;
            //});

            //selectedChoices = CartChoicesItems.filter(function (i, n) {
            //    return n.MainItemId === itemid;
            //});

            //if (obj.I == itemid) {
            //    obj.Q = obj.Q + 1;
            //    //IsExists = 1;
            //} else {
            //    if (selectedItemid == itemid && parseInt($('#lblItemInfoQty').val()) == 0) {
            //        $('#lblItemInfoQty').val(1);
            //    }
            //}

            if (obj.UID == UID) {
                if (IsFromDirectItemInToCartclick == 1) {
                    // Straight from the menu tile: add what was asked for and
                    // do not consult the DOM. The branch below reads the
                    // quantity out of #divItemwiseCount_<UID>, which only
                    // exists while the cart view is rendered - off the menu
                    // page that returns NaN, the increment is skipped, and the
                    // tap does nothing at all even though IsExists is set.
                    obj.Q = obj.Q + tempqty;
                }
                else {
                    var qty = isNaN(qty) == true ? 1 : parseInt($('#lblItemInfoQty').val());
                    if (UID > 0) {
                        qty = isNaN(qty) == true ? 1 : parseInt($('#divItemwiseCount_' + obj.UID + '').html());
                    }
                    if (qty > 0) {
                        obj.Q = obj.Q + 1;
                    }
                }
                IsExists = 1;
            } else {
                //if (selectedItemid == itemid && parseInt($('#lblItemInfoQty').val()) == 0) {
                //    $('#lblItemInfoQty').val(1);
                //}
            }
            totalcnt = totalcnt + obj.Q;
        });

        if (tempCartDetails.length == 0) {
            if (selectedItemid == itemid) {
                $('#lblItemInfoQty').val(1);
            }
        }
        debugger;
        var choiceid = 0;
        $(".ItemsChoice").each(function (index) {
            if ($(this).prop("checked") == true) {
                var idName = $(this).attr("id");
                choiceid = idName.split("_")[1];
            }
        });

        if (IsExists == 0) {
            var item = {}
            item["UID"] = parseInt($('#hdnSelectedUID').val());
            item["I"] = itemid;
            item["O"] = HID;
            item["Q"] = tempqty;
            item["C"] = $('#commentsItemDetailsView').val();
            item["CH"] = parseInt(choiceid);
            tempCartDetails.push(item);
            totalcnt = totalcnt + tempqty;

        }

        // totalcnt above is the number of UNITS, still used by the amount
        // calculations. The badge counts lines, so it is left to BindCartCount
        // rather than painted from here with a different number.
        BindCartCount(tempCartDetails);

        OnAddMinusUpdateAmounts(tempCartDetails, UID);
        var val = JSON.stringify(tempCartDetails);
        createCookie("OrderCookie", val, 365);
        //ShowNotification("Item Added in Cart..");
        CartDetails = tempCartDetails;
        UpdateCartCountSpan();
        clearItemChoicesAndExtras();
        ////set Item detail view Qty  
        //if (selectedItemid == itemid) {
        //    var qty = parseInt($('#lblItemInfoQty').val());
        //    $('#lblItemInfoQty').val(qty+1)
        //}


        $('#hdnSelectedUID').val(parseInt($('#hdnSelectedUID').val()) + tempqty);

        $(".top-header .cart").addClass('add');
        setTimeout(function () {
            $('.top-header .cart').removeClass('add');
        }, 800);
    }
    $('#commentsItemDetailsView').val("");
}

function addItemclickNew(UID, itemid, HID, IsFromCart) {
    var qty = parseInt($('#lblItemInfoQty').val());
    //if (!(qty > 0) && $('#divItemwiseCount_' + UID + '').length > 0) {
    //    qty = parseInt($('#divItemwiseCount_' + UID + '').html());
    //}
    if (UID > 0) {
        qty = parseInt($('#divItemwiseCount_' + UID + '').html());
    }
    if (qty >= 0) {
        $('#lblItemInfoQty').val(qty + 1)
        UpdateItemDetailsPrices(itemid, UID);
    }
}
function clearItemChoicesAndExtras() {
    debugger;
    $(".ItemsChoice").each(function () {
        //if ($(this).prop("checked") == true) {
        $(this).prop("checked", false);
        //}
    });
    $(".extraItems").each(function () {
        //if ($(this).prop("checked") == true) {
        $(this).prop("checked", false);
        //}
    });

    $(".clsGroupSelectd").each(function () {
        $(this).val("0");
    });


    //var itemunitprice = parseFloat($('#divitemDetailsPrice').html());
    //var itemTotalPrice = parseFloat(0) + parseFloat(itemunitprice);
    $('#divExtraitemDetailsPrice').html(round(0, decimalPlace).toFixed(decimalPlace));
    $('#divitemDetailsTotalPrice').html(round(0, decimalPlace).toFixed(decimalPlace));

}
function OnAddMinusUpdateAmounts(tempCartDetails, UID) {
    debugger;
    var FinalTotal = 0;
    var flgUpdateItemDetailsUpdate = 0;
    $.each(tempCartDetails, function (i, obj) {
        var ItemTotalExtraItemAmnt = 0;
        $('#divItemwiseCount_' + obj.UID).html(obj.Q);

        var extraItemsTotal = 0;
        $.each(CartExtraItems, function (i, extraItem) {
            //if (extraItem.MainItemId == obj.I) {
            if (extraItem.UID == obj.UID) {

                extraItemsTotal = extraItemsTotal + round(extraItem.Price, decimalPlace).toFixed(decimalPlace);
            }
        });
        var qty = obj.Q != undefined ? obj.Q : 0;
        qty = qty != null ? qty : 0;
        ItemTotalExtraItemAmnt = round(extraItemsTotal, decimalPlace).toFixed(decimalPlace);
        $('#ExtraItemTotalAmt_' + obj.I + '_' + obj.UID).html(ItemTotalExtraItemAmnt);
        ItemTotalExtraItemAmnt = round(extraItemsTotal * qty, decimalPlace).toFixed(decimalPlace);

        if ($('#divItemwiseCount_Confirm_' + obj.UID).length > 0) {
            $('#divItemwiseCount_Confirm_' + obj.UID).html(obj.Q);
        }

        //update ItemTotal
        //var selectedItemPrice = Number.parseFloat($('#hdnItem_PRICE_' + obj.I).val());
        var selectedItemPrice = round($('#hdnItem_PRICE_' + obj.I).val(), decimalPlace).toFixed(decimalPlace);
        if (isNaN(selectedItemPrice)) {
            var selectedItemPrice = 0;
        }

        if (UID == obj.UID && selectedItemid == obj.I) {
            debugger; ///te1
            flgUpdateItemDetailsUpdate = 1;
            $('#lblItemInfoQty').val(obj.Q);
            setSelectedItemsChoice(selectedItemid, 0, UID);
            UpdateItemDetailsPrices(selectedItemid, UID);
        }


        debugger;
        //var curtotal = Number.parseFloat($('#hdnItem_TotalPRICE_' + obj.I).val());
        var ItemwiseTotal = round((parseFloat(ItemTotalExtraItemAmnt) + (parseFloat(selectedItemPrice) * obj.Q)), decimalPlace).toFixed(decimalPlace);
        $('#hdnItem_TotalPRICE_' + obj.I).val(ItemwiseTotal);
        $('#ItemTotalamt_' + obj.I + '_' + obj.UID).html("<em>" + selectedCurrency + ".</em>" + ItemwiseTotal);
        if ($('#ItemTotalamt_Confirm_' + obj.I + '_' + obj.UID).length > 0) {
            $('#ItemTotalamt_Confirm_' + obj.I + '_' + obj.UID).text(selectedCurrency + ". " + ItemwiseTotal);
        }
        FinalTotal = round((parseFloat(FinalTotal) + parseFloat(ItemwiseTotal)), decimalPlace).toFixed(decimalPlace);

    });

    debugger; ///te2
    //check if selected item details qty updated then no need to update else set as 0;
    if (flgUpdateItemDetailsUpdate == 0) {
        $('#lblItemInfoQty').val(0);
        setSelectedItemsChoice(selectedItemid, 0, UID);
        UpdateItemDetailsPrices(selectedItemid, UID);
    }
    //update subtotal 
    //var curSubtotal = Number.parseFloat($('#hdnSubtotal').val());
    $('#hdnSubtotal').val(FinalTotal);
    $('#divSubtotal').text(selectedCurrency + ". " + FinalTotal);
    if ($('#lblPaymentBillAmountVal').length > 0) {
        $('#lblPaymentBillAmountVal').html(FinalTotal);
        $('#lblPaymentBillAmountCurrency').html(selectedCurrency + ". ");
    }

    if ($('#divSubTotalConfirm').length > 0) {
        $('#divSubTotalConfirm').text(selectedCurrency + ". " + FinalTotal);
    }

    //code for confirm view update Final total amount with deliverycharges
    //code for confirm view update Final total amount with deliverycharges
    //var TotalAmt = Number.parseFloat(FinalTotal);

    UpdateConfirmViewFinalAmounts(selectedCurrency, FinalTotal);
}

function UpdateCartCountSpan() {
    debugger;
    if ($('.clCartCount').html() == "0") {
        $(".clCartCount").each(function (index) {
            $(this).hide();
        });
        $('#cartCountDesktop').hide();
    }
    else {
        $(".cartCount").each(function (index) {
            $(this).show();
        });
        $('#cartCountDesktop').show();
    }
}

function ShowNotification(message) {
    // Get the snackbar DIV
    $('#snackbar').html(message);
    var x = document.getElementById("snackbar");
    // Add the "show" class to DIV
    x.className = "show";
    // After 3 seconds, remove the show class from DIV
    setTimeout(function () { x.className = x.className.replace("show", ""); }, 1000);
}

function Minusecardclick(UID, itemid) {
    debugger;
    var qty = parseInt($('#divItemwiseCount_' + UID).html());
    //if (selectedItemid == itemid) {
    //    qty = $('#lblItemInfoQty').val();
    //}
    if (qty == 0) {
        return false;
    }
    if (qty == 1) {
        $.confirm({
            title: 'Confirm',
            content: 'Are you sure you want to remove?',
            icon: 'fa fa-question',
            closeAnimation: 'scale',
            opacity: 0.2,
            theme: 'bootstrap',
            closeIcon: true,
            animation: 'scale',
            type: 'orange',
            buttons: {
                'confirm': {
                    text: 'Yes',
                    btnClass: 'btn-orange',
                    action: function () {
                        minuseItem(UID, itemid, CartDetails, true);
                        //UpdateSubTotal(itemid);
                    },
                    Cancel: function () {
                        //retval=false;
                    },
                }
            }
        });
    }
    else {
        minuseItem(UID, itemid, CartDetails, false);
        //UpdateSubTotal(itemid);
    }
    $(".top-header .cart").addClass('add');
    setTimeout(function () {
        $('.top-header .cart').removeClass('add');
    }, 800);
}
function minuseItem(UID, itemid, objCartDetails, isitlastitem) {
    debugger;
    var totalcnt = 0;
    var catnumb = $('#Item_' + UID).attr("data-val");
    var tempCartDetails = objCartDetails;
    var FinalTotal = 0;
    var deletedobj = null;
    var tempCartExtraItems = [];
    var tempCartChoicesItems = [];

    $.each(tempCartDetails, function (i, obj) {
        if (obj.UID == UID) {
            obj.Q = obj.Q - 1;
        }
        if (obj.Q == 0) {
            deletedobj = obj;
            //remove last items html which qty is now 0
            $('#Item_' + UID).remove();
            $('#Item_' + UID).remove();
        }
        totalcnt = totalcnt + obj.Q;

        //remove subextra items
        $.each(CartExtraItems, function (j, objext) {
            if (objext.UID != obj.UID) {
                tempCartExtraItems.push(objext);
            }
        });

        //remove choices items
        $.each(CartChoicesItems, function (k, objchoice) {
            if (objchoice.UID != obj.UID) {
                tempCartChoicesItems.push(objchoice);
            }
        });
    });

    //check if last item and it's qty 0 then remove from the object list
    if (deletedobj != null) {
        tempCartDetails = jQuery.grep(tempCartDetails, function (value) {
            return value != deletedobj;
        });
    }
    // After the zero-quantity line has been dropped above, so a line removed
    // by stepping its quantity down to nothing stops being counted.
    BindCartCount(tempCartDetails);

    OnAddMinusUpdateAmounts(tempCartDetails, UID);
    var val = JSON.stringify(tempCartDetails);
    createCookie("OrderCookie", val, 365);
    //ShowNotification("Item Removed from Cart..");

    var val = JSON.stringify(tempCartExtraItems);
    createCookie("ExtraItemsCookie", val, 365);
    var val = JSON.stringify(tempCartChoicesItems);
    createCookie("ChoiceItemsCookie", val, 365);

    checkcategoryItemExist(catnumb);
    CartDetails = tempCartDetails;
    UpdateCartCountSpan();
    //set Item detail view Qty  
    //if (selectedItemid == itemid) {
    //    var qty = parseInt($('#lblItemInfoQty').val());
    //    $('#lblItemInfoQty').val(qty - 1)
    //}
}

function MinusecardclickNew(UID, itemid, HID, IsFromCart) {
    var qty = parseInt($('#lblItemInfoQty').val());
    //if (!(qty > 0) && $('#divItemwiseCount_' + UID + '').length > 0) {
    //    qty = parseInt($('#divItemwiseCount_' + UID + '').html());
    //}
    if (UID > 0) {
        qty = parseInt($('#divItemwiseCount_' + UID + '').html());
    }
    if (qty > 0) {
        $('#lblItemInfoQty').val(qty - 1)
        UpdateItemDetailsPrices(itemid, UID);
    }
}

function UpdateConfirmViewFinalAmounts(selectedCurrency, TotalAmt) {
    var deliveryCharges = Number.parseFloat($('#hdnAreaDeliveryCharges').val());
    var Subtotal = round(TotalAmt + deliveryCharges, decimalPlace).toFixed(decimalPlace);
    if ($('#divtotalConfirm').length > 0) {
        $('#divtotalConfirm').html(selectedCurrency + ". " + Subtotal);
        $('#cartFooterConfirm').show();
        $('#divDeliveryChargesConfirm').html(selectedCurrency + ". " + round(deliveryCharges, decimalPlace).toFixed(decimalPlace));
    }
}
function checkcategoryItemExist(catnumb) {
    debugger;
    if ($('#cartCateItems_' + catnumb).children().length == 0) {
        $('#cartCateItems_' + catnumb).remove();
        $('#cartCate_' + catnumb).remove();
    }

    if ($('#cartCateItems_Confirm_' + catnumb).children().length == 0) {
        $('#cartCateItems_Confirm_' + catnumb).remove();
        $('#cartCate_Confirm_' + catnumb).remove();
    }
}
///////////////////////////// menu bind methods

function btnSectionReservationclick() {
    debugger;
    IsReservationClick = 1;
    if (BranchArrayList.length > 1) {
        $('#branch-menu').modal('show');
    }
    else {
        $('#hdnbrandId').val(BranchArrayList[0].brandId);
        $('#hdnBranchId').val(BranchArrayList[0].id);
        $('#lblReservationHeader').html(BranchArrayList[0].branchName);
        $('#lblReservationCustomerInfoHeader').html(BranchArrayList[0].branchName);
        $('#lblReservationConfirmHeader').html(BranchArrayList[0].branchName);
        ShowDivReservation();
    }

}


function BindSectionMenu() {
    var objdata = {
        BrandId: $('#hdnbrandId').val(),
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetBranchAndSectionList",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var SectionsList = result.dtSections;
                var BranchList = result.dtBranch;

                SectionsArraylist = result.dtSections;
                BranchArrayList = result.dtBranch;

                if (BranchList.length == 1) {
                    $('#hdnbrandId').val(BranchList[0].brandId);
                    $('#hdnBranchId').val(BranchList[0].id);
                    $('#hdndefaultOneBrandId').val(BranchList[0].brandId);
                    $('#hdndefaultOneBranchId').val(BranchList[0].id);
                    BindCategory(selectedCategoryId);
                    $('#btnSectionBranchMenu').removeAttr("data-toggle");
                    $('#btnSectionBranchMenu').removeAttr("data-target");

                    $('#divlandingpage').hide();
                    $("#divlandingpage").css("visibility", "collapse");
                    $('#divleftsideMenuListView').show();
                    $('#divCategoryList').show();
                    //$('#divCategoryList').show();
                    //$('#divSectionMenu').hide();
                    //$('#btncart').show();
                }
                if (BranchList.length > 1) {
                    $('#divSectionMenu').show();
                }
                //else {
                BindBranchAndSectionMenuHTML(SectionsList, BranchList);
                //$('#divCategoryList').hide();
                //$('#divSectionMenu').show();
                $('#btncart').show();
                //}
            }
        }
    });
}



function BindBranchAndSectionMenuHTML(SectionsList, BranchList) {
    if (SectionsList.length > 0) {
        $('#divMainSectionBranchList').html("");
        //$('#divMainReservationBranchList').html("");
        var Mainstr = "";
        var cntSection = 0;
        $.each(SectionsList, function (i, obj) {
            var SectionName = "";
            if ($('#selectedLang').val() == "EN") {
                SectionName = obj.sectionName;
                selectedCurrency = $('#hdnCurrencyENG').val();
            }
            else {
                SectionName = obj.SectionNameArabic;
                selectedCurrency = $('#hdnCurrencyArab').val();
            }

            var str = "";
            str = '<div id="MainDivSection_' + obj.id + '" class="card mb-4">' +
                '<div class="card-header" > ' + SectionName + ' </div>' +
                '<div id="divSection_' + obj.id + '" class="card-body">' +
                //'<a class="branches" href="CategoryList.html" title="">Elit pariatur commodo minim </a>' +
                '</div>' +
                '</div >';

            Mainstr = Mainstr + str;
            cntSection = cntSection + 1;
            ////check if language change and category selected then set category name language wise
            //if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
            //    $('#divCatename').html(catname);
            //    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
            //}
            $('#divMainSectionBranchList').append(str);
            //$('#divMainReservationBranchList').append(str);

            BindSectionWiseBranchList(obj.id, BranchList);
        });
        //$('#divMainSectionBranchList').append(Mainstr);
    }
}

function BindSectionWiseBranchList(sectionid, BranchList) {
    debugger;
    $('#divSection_' + sectionid + '').html("");
    if (BranchList.length > 0) {
        var Mainstr = "";
        var cntSection = 0;
        $.each(BranchList, function (i, obj) {
            if (obj.sectionId == sectionid) {
                var BranchName = "";
                if ($('#selectedLang').val() == "EN") {
                    BranchName = obj.branchName;
                    selectedCurrency = $('#hdnCurrencyENG').val();
                }
                else {
                    BranchName = obj.branchNameAra;
                    selectedCurrency = $('#hdnCurrencyArab').val();
                }

                var str = "";
                debugger;
                str += '<div class="clsSectionBrcDiv">';
                if (obj.branchImg.length > 0) {
                    str += '<img class="card-img-top img-responsive img-Category clsSectionBrcImg" src="../../Images/' + obj.branchImg + '" alt="" onclick="onsectionBranchClick(' + obj.brandId + ',' + obj.id + ',this);">';
                }
                else {
                    str += '<a id="linkBranch_' + obj.id + '" class="branches" onclick="onsectionBranchClick(' + obj.brandId + ',' + obj.id + ',this);">' + BranchName + '</a>';
                }
                str += '</div>';


                //str = '<div class="clsSectionBrcDiv"><img class="card-img-top img-responsive img-Category clsSectionBrcImg" src="../../ThumbnailImages/2022218222047.png" alt="" onclick="onsectionBranchClick(' + obj.brandId + ',' + obj.id + ',this);"> <a id="linkBranch_' + obj.id + '" class="branches" onclick="onsectionBranchClick(' + obj.brandId + ',' + obj.id + ',this);">' + BranchName + '</a></div>';
                //str = '<a id="linkBranch_' + obj.id + '" class="branches" onclick="onsectionBranchClick(' + obj.brandId + ',' + obj.id + ',this);">' + BranchName + '</a>';

                //str = '<div id="Cat_' + item.CAT_NUM + '" onclick="OnCategoryClick(' + item.CAT_NUM + ');" data-val="' + catname + '" data-text="' + cntSection + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4">' +
                //    '<a class="card-primary ml-1 mr-1" >' +
                //    '<img class="card-img-top img-responsive img-Category" src="../ThumbnailImages/' + item.ImageName + '" alt="">' +
                //    '<div class="card-body">' +
                //    '<h3>' + catname + '</h3>' +
                //    '</div>' +
                //    '</a>' +
                //    '</div>';
                Mainstr = Mainstr + str;
                cntSection = cntSection + 1;

                ////check if language change and category selected then set category name language wise
                //if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
                //    $('#divCatename').html(catname);
                //    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
                //}
                $('#divSection_' + sectionid + '').append(str);
            }

        });
        //$('#divMainSectionBranchList').append(Mainstr);
    }
    if (cntSection == 0) {
        $('#MainDivSection_' + sectionid + '').hide();
    }
}

function onsectionBranchClick(brandId, Branchid, objbtn) {
    debugger;
    if (IsReservationClick == 0) {
        $('#hdnbrandId').val(brandId);
        $('#hdnBranchId').val(Branchid);
        MainCateHeader = $(objbtn).html();
        $('#divBranchName').html(MainCateHeader);
        BindCategory(selectedCategoryId);
        $('#divCategoryList').show();

        //check if layout-3 then divlandingpage is exist else layout 2 then direct else 
        if ($('#divlandingpage').length) {
            $('#divlandingpage').hide();
            $("#divlandingpage").css("visibility", "collapse");
            //$("#divlandingpage").removeClass("h-100");
            $('#divleftsideMenuListView').show();
        } else {
            $('#divleftsideMenuListView').show();
        }

        $('#divSectionMenu').hide();
        $('#btnSectionDivClose').click();
        $('#btncart').show();
    }
    else {
        $('#hdnbrandId').val(brandId);
        $('#hdnBranchId').val(Branchid);
        $('#lblReservationHeader').html($(objbtn).html());
        $('#lblReservationCustomerInfoHeader').html($(objbtn).html());
        $('#lblReservationConfirmHeader').html($(objbtn).html());

        //check if layout-3 then divlandingpage is exist else layout 2 then direct else
        if ($('#divlandingpage').length) {
            $('#divlandingpage').hide();
            $("#divlandingpage").css("visibility", "hidden");
            //$("#divlandingpage").removeClass("h-100");
            $('#divleftsideMenuListView').show();
        } else {
            $('#divleftsideMenuListView').show();
        }
        $('#divSectionMenu').hide();
        $('#btnSectionDivClose').click();
        ShowDivReservation();
    }

}

// Design1's main landing view (category selected directly, items shown inline
// via CreateCategorySlider) comes from /ItemsView/GetCategoryList, whose stored
// proc (sp_GetCategoryList) does not return per-item allergen data at all -
// unlike /ItemsView/GetItemList (sp_GetCategoryWiseItemList), used by the
// subcategory-click flow, which does. Rather than changing the stored proc,
// re-use the existing GetItemList endpoint for the same Cat_Num purely to fetch
// its allergen table, so CreateCategorySlider can show the icon here too.
function GetItemsAllergenListForCategory(catNum, callback) {
    if ($('#hdnIsShowAllergen').val() != "1") {
        callback([]);
        return;
    }
    $.ajax({
        type: "Post",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetItemList?Cat_Num=" + catNum + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
        success: function (result) {
            var list = (result.Message == "Success" && result.dtItemsAllergenList) ? result.dtItemsAllergenList : [];
            // Also populate the global ItemAllergenslst - OnItemClickShowPopup()/OnItemClick()
            // filter THAT global when the item is later clicked to open its details, not
            // whatever local list this call's own caller happens to hold, so without this the
            // Item Details popup's allergen icon would silently stay hidden for every item
            // reached through this landing-page (CreateCategorySlider) path.
            ItemAllergenslst = list;
            callback(list);
        },
        error: function () {
            callback([]);
        }
    });
}
function BindCategory(selectedCategoryId) {
    //$('#categoryList').html("");
    debugger;
    if ($("#hdnDesignName").val() == "Design1") {
        $('#divBranchnameandBackToSection').hide();
        $('#divCreateCategorySlider').html("");
        $('#subCategoryItems').html("");
    }
    else if ($("#hdnDesignName").val() == "Design4") {
        $('#divBranchnameandBackToSection').hide();
        $('#categoryAccordion').html("");
    }
    else if ($("#hdnDesignName").val() == "Design5") {
        $('#d5CatArc').html(""); $('#d5Track').html("");
    }
    else {
        $('#categoryList').html("");
    }
    $('#itemlist').html("");
    //var obji = { BrandId: $('#hdnbrandId').val(),Branchid: $('#hdnBranchId').val()}
    var obji = {
        BrandId: $('#hdnbrandId').val(),
        Branchid: $('#hdnBranchId').val(),
        CategoryId: selectedCategoryId,
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        async: false,
        //url: "/ItemsView/GetCategoryList?BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
        url: "/ItemsView/GetCategoryList",
        success: function (result) {
            if (result.Message == "Success") {
                debugger;
                var Category = result.dtCategory;
                var selectedCatItems = result.dtItems;
                var subCategory = result.dtSubCategory;
                if ($("#hdnDesignName").val() == "Design1") {
                    GetItemsAllergenListForCategory(selectedCategoryId, function (ItemsAllergenList) {
                        CreateCategorySlider(Category, selectedCategoryId, selectedCatItems, subCategory, ItemsAllergenList);
                    });
                }
                else if ($("#hdnDesignName").val() == "Design4") {
                    CreateCategoryHtmlAccordion(Category, selectedCategoryId);
                }
                else if ($("#hdnDesignName").val() == "Design5") {
                    CreateDesign5Menu(Category, selectedCatItems, subCategory);
                }
                else {
                    CreateCategoryHtml(Category);
                }

                //BindSelectedCategoryItems(selectedCatItems);
            }
        }
    });
}
function BindSubCategoryDesign1(selectedCategoryId) {
    var obji = {
        BrandId: $('#hdnbrandId').val(),
        Branchid: $('#hdnBranchId').val(),
        CategoryId: selectedCategoryId,
    }
    isLoadervisible = 0;
    $.ajax({
        type: "Post",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetCategoryList",
        success: function (result) {
            debugger;
            isLoadervisible = 1;
            if (result.Message == "Success") {
                var Category = result.dtCategory;
                var selectedCatItems = result.dtItems;
                var subCategory = result.dtSubCategory;
                if ($("#hdnDesignName").val() == "Design1") {
                    GetItemsAllergenListForCategory(selectedCategoryId, function (ItemsAllergenList) {
                        CreateCategorySlider(Category, selectedCategoryId, selectedCatItems, subCategory, ItemsAllergenList);
                    });
                }
                //else if ($("#hdnDesignName").val() == "Design4") {
                //    CreateCategoryHtmlAccordion(Category, selectedCategoryId);
                //}

                //else {
                //    CreateCategoryHtml(Category);
                //}
                //BindSelectedCategoryItems(selectedCatItems);
            }
        }
    });
}
function BindSubCategory(selectedCategoryId) {
    var obji = {
        BrandId: $('#hdnbrandId').val(),
        Branchid: $('#hdnBranchId').val(),
        CategoryId: selectedCategoryId,
    }
    isLoadervisible = 0;
    $.ajax({
        type: "Post",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetCategoryList",
        success: function (result) {
            isLoadervisible = 1;
            debugger;
            if (result.Message == "Success") {
                var Category = result.dtCategory;
                var selectedCatItems = result.dtItems;
                var subCategory = result.dtSubCategory;
                if ($("#hdnDesignName").val() == "Design1") {
                    GetItemsAllergenListForCategory(selectedCategoryId, function (ItemsAllergenList) {
                        CreateCategorySlider(Category, selectedCategoryId, selectedCatItems, subCategory, ItemsAllergenList);
                    });
                }
                else if ($("#hdnDesignName").val() == "Design4") {
                    CreateCategoryHtmlAccordion(Category, selectedCategoryId);
                }

                //else {
                //    CreateCategoryHtml(Category);
                //}
                //BindSelectedCategoryItems(selectedCatItems);
            }
        }
    });
}
function CreateCategorySlider(Category, selectedCategoryId, selectedCatItems, subCategory, ItemsAllergenList) {
    debugger;
    ItemsAllergenList = ItemsAllergenList || [];
    var CatSliderMainstr = "";
    var Mainstr = "";
    var firstCat_num = 0;
    var firstCat_IsHaveSubCategory = 0;

    var isrtl = false;
    if ($('#selectedLang').val() == "EN") {
        isrtl = false
    }
    else {
        isrtl = true
    }

    $.each(Category, function (i, item) {
        firstCAT_NUM = item.CAT_NUM;
        firstIsHaveSubCategory = item.IsHaveSubCategory;
        if ($('#selectedLang').val() == "EN") {
            catname = item.CAT_NAME;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            catname = item.CAT_NAME_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }

        var str = "";
        //selectedCategoryId > 0 //it means Subcategory bind
        if (selectedCategoryId > 0) {
            str = '<div id="subCategory_' + item.CAT_NUM + '" class="sub-category mb-3">' +
                '<div class="card parent-item">' +
                '<div class="row no-gutters">' +
                '<div class="col-md-2">' +
                '<img src="../../images/2022831173936.jpg" class="card-img" alt="">' +
                '</div>' +
                '<div class="col-md-10">' +
                '<div class="card-body">' +
                '<h2 class="mb-0 pb-0">' +
                '<button onclick="OnSubCategoryClickDesign1(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');"' +
                'class="btn d-flex align-items-center justify-content-between w-100" ' +
                'type="button" data-toggle="collapse" ' +
                'data-target="#collapse_' + item.CAT_NUM + '" aria-expanded="true" ' +
                'aria-controls="collapse_' + item.CAT_NUM + '"> ' +
                '' + catname + '' +
                '<svg class="icon" xmlns="http://www.w3.org/2000/svg" ' +
                'width="30" height="30" viewBox="0 0 20 20" ' +
                'fill="none">' +
                '<path d="M5 7.5L10 12.5L15 7.5" stroke="#363636" ' +
                'stroke-width="1.2" stroke-linecap="round" ' +
                'stroke-linejoin="round"></path> ' +
                '</svg> ' +
                '</button> ' +
                '</h2> ' +
                '</div> ' +
                '</div> ' +
                '</div> ' +
                '</div> ' +

                '<div id="collapse_' + item.CAT_NUM + '" class="collapse" aria-labelledby="subCategory_' + item.CAT_NUM + '" data-parent="#subCategoryItems"> ' +
                '<div class="card-body sub-category-items" id="subCategoryItesmsList_' + item.CAT_NUM + '"> ';
            //Bind Sub Items 
            //str = str + BindSubCategoryItemsDesign1(item.CAT_NUM);
            str = str + '</div>' +
                '</div>' +
                '</div>';
            Mainstr = Mainstr + str;
        }
        else {
            var Scrollstr = "";
            Scrollstr = '<a href="#" id="ScrollCategory_' + item.CAT_NUM + '" data-val="' + item.CAT_NUM + '"  class="card-primary ml-1 mr-1 mainCategory" onclick="OnMainCategoryClickDesign1(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');">' +
                '<img class="img-category img-responsive"' +
                'src ="../../ThumbnailImages/' + item.ImageName + '" alt="' + catname + '">' +
                '<div class="card-body">' +
                '<h3>' + catname + '</h3>' +
                '</div>' +
                '</a>';
            CatSliderMainstr = CatSliderMainstr + Scrollstr;

            if (firstCat_num == 0) {
                firstCat_num = item.CAT_NUM;
                firstCat_IsHaveSubCategory = item.IsHaveSubCategory;
            }
        }
    });


    //if main category have direct items then bind it.
    if (selectedCatItems.length > 0) {
        var selectedCurrency = "";

        $.each(selectedCatItems, function (i, item) {
            var allergenList = ItemsAllergenList.filter(function (entry) {
                return entry.itemId === item.id;
            });
            var ItemName = "";
            var INGREDIENT = "";
            if ($('#selectedLang').val() == "EN") {
                ItemName = item.ITEM_NAME;
                INGREDIENT = item.INGREDIENT;
                selectedCurrency = $('#hdnCurrencyENG').val();
            }
            else {
                ItemName = item.ITEM_NAME_ARABIC;
                INGREDIENT = item.INGREDIENT_ARABIC;
                selectedCurrency = $('#hdnCurrencyArab').val();
            }

            ///Begin bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///
            var addButtonClick = "";
            if (item.MinGroupModifierSelection == "1") {
                addButtonClick = '<a href="#" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ');" class="btn btn-primary btn-addtocart" data-toggle="modal" data-target="#itemDetailModal">+</a>';
            }
            else {
                addButtonClick = '<a href="#" onclick="addDirectItemInToCartclick(0,' + item.id + ',' + item.HID + ',1);" class="btn btn-primary btn-addtocart">+</a>';
            }
            ///End bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///

            var itemHtmlStr = '';
            itemHtmlStr = '<div class="sub-category mb-3">' +
                '<div class="card">' +
                '<div class="row no-gutters">' +
                '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
                '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
                '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
                '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
                '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '"/>' +
                '<div class="col-4 col-md-3 col-lg-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')" data-toggle="modal" data-target="#itemDetailModal">' +
                '<div class="card-img-con"><img src="../../images/' + item.IMAGENAME + '" class="card-img" alt=""></div></div>' +
                '<div class="col-8 col-md-9 col-lg-8" >' +
                '<div class="card-body" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')" data-toggle="modal" data-target="#itemDetailModal" style="cursor: pointer;">' +
                '<div class="media">' +
                '<div class="media-body pr-3 position-relative">' +
                (($('#hdnIsShowAllergen').val() == "1") ? bindAllergensHtml(allergenList, { wrapperClass: 'position-absolute allergens allergens-inline', dropup: false, menuRight: true }) : '') +
                '<h4 class="media-body-title pb-2 pr-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')"  data-toggle="modal" data-target="#itemDetailModal">' + ItemName + '</h4>' +
                '<p class="media-body-text mb-2">' + INGREDIENT + '</p>' +
                '<p class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</p>' +
                //'<ul class="list-unstyled list-inline allergen-list">' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-gluten-free.png" class="icon-allergen" alt="">' +
                //'</li>' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-celery.png" class="icon-allergen" alt=""> ' +
                //'</li>' +
                //'</ul>' +

                
                //'<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary btn-addtocart">+</a>'+
                '</div>' +
                '</div>' +
                
                '</div>' +
                '</div>' +
                '</div>' +
                addButtonClick +
                '</div>' +
                '</div>';
            Mainstr = Mainstr + itemHtmlStr;
        });

    }


    //Bind Main Category Slider
    if (selectedCategoryId > 0) {
        $('#subCategoryItems').html(Mainstr);
    }
    else {

        var carousel = jQuery("#divCreateCategorySlider");
        carousel.trigger('destroy.owl.carousel');
        carousel.find('.owl-stage-outer').children().unwrap();
        carousel.removeClass("owl-center owl-loaded owl-text-select-on");
        carousel.html(CatSliderMainstr);
        carousel.owlCarousel({
            //$('#divCreateCategorySlider1').owlCarousel({
            //html: Mainstr,
            loop: false,
            margin: 10,
            responsiveClass: true,
            autoHeight: true,
            rtl: isrtl,
            responsive: {
                0: {
                    items: 3,
                    nav: false
                },
                420: {
                    items: 4,
                    nav: false
                },
                575: {
                    items: 5,
                    nav: false
                },
                600: {
                    items: 3,
                    nav: false
                },
                768: {
                    items: 6,
                    nav: false
                },
                992: {
                    items: 4,
                    nav: false
                },

                // Desktop. Was items:3, which is what made the category strip
                // show only three wide, stretched tiles on a full-width screen
                // (992 just below already shows 4). No CSS can change this -
                // Owl writes the tile width inline from this number - so the
                // desktop count has to be set here.
                1000: {
                    items: 4,
                    nav: false,
                    loop: false
                }
            }
        });
        OnMainCategoryClickDesign1(firstCat_num, firstCat_IsHaveSubCategory);
    }

    //selectedCategoryId > 0 it means Subcategory bind
    //if (selectedCategoryId > 0) {
    //    $('#SubCatOrItemData_' + selectedCategoryId + '').html('<div class="accordion subcategory-accordion" id="accordionExample-summenu' + selectedCategoryId + '">' + Mainstr + '</div>');
    //}
    //else {
    //    $('#categoryAccordion').html(Mainstr);
    //}
}
function CreateCategoryHtmlAccordion(Category, selectedCategoryId) {
    debugger;
    var Mainstr = "";
    //var cntcat = 0;
    //var firstCAT_NUM = 0;
    //var firstIsHaveSubCategory = 0;
    $.each(Category, function (i, item) {
        firstCAT_NUM = item.CAT_NUM;
        firstIsHaveSubCategory = item.IsHaveSubCategory;
        if ($('#selectedLang').val() == "EN") {
            catname = item.CAT_NAME;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            catname = item.CAT_NAME_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }
        var str = "";
        //selectedCategoryId > 0 it means Subcategory bind
        if (selectedCategoryId > 0) {
            str += '<div class="card rounded-0 mb-2">';
            var strCollHeading = '<div class="card-header border-0 rounded-0 p-1" id="heading' + item.CAT_NUM + '">' +
                '<button onclick="OnCategoryClickDesign4(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');" data-val="' + catname + '" class="btn d-flex align-items-center justify-content-between w-100 collapsed" type="button" data-toggle="collapse" data-target="#collapse' + item.CAT_NUM + '" aria-expanded="false" aria-controls="collapse' + item.CAT_NUM + '">' +
                '' + catname + '' +
                //'<svg class="icon" xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 20 20" fill="none">' +
                //'<path d="M5 7.5L10 12.5L15 7.5" stroke="#363636" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />' +
                //'</svg>' +
                '<span class="plus-icon"></span>' +
                '</button>' +
                '</div>';
            var strCollPaneldata = '<div id="collapse' + item.CAT_NUM + '" class="collapse" aria-labelledby="heading' + item.CAT_NUM + '" data-parent="#accordionExample-summenu' + selectedCategoryId + '">' +
                '<div id="SubCatOrItemData_' + item.CAT_NUM + '" class="card-body" >' +
                //dynmic content(item list)
                '</div></div>';

            //str += '<button onclick="OnCategoryClickDesign4(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');" data-val="' + catname + '" class="btn d-flex align-items-center justify-content-between w-100 collapsed" type="button" data-toggle="collapse" data-target="#collapse' + item.CAT_NUM + '" aria-expanded="false" aria-controls="collapse' + item.CAT_NUM + '">' +
            //    '' + catname + '' +
            //    '<svg class="icon" xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 20 20" fill="none">' +
            //    '<path d="M5 7.5L10 12.5L15 7.5" stroke="#363636" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />' +
            //    '</svg>' +
            //    '</button>';
            str += strCollHeading + strCollPaneldata + '</div>'
            Mainstr = Mainstr + str;
        }
        else {
            str += '<div class="card border-0 p-0 mb-2">';
            var strCollHeading = '<div class="card-header border-0 p-1" id="heading' + item.CAT_NUM + '">' +
                '<button onclick="OnCategoryClickDesign4(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');" data-val="' + catname + '" class="btn d-flex align-items-center justify-content-between w-100 collapsed" type="button" data-toggle="collapse" data-target="#collapse' + item.CAT_NUM + '" aria-expanded="false" aria-controls="collapse' + item.CAT_NUM + '">' +
                '' + catname + '' +
                '<svg class="icon" xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 20 20" fill="none">' +
                '<path d="M5 7.5L10 12.5L15 7.5" stroke="#363636" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />' +
                '</svg>' +
                '</button>' +
                '</div>';
            var strCollPaneldata = '<div id="collapse' + item.CAT_NUM + '" class="accordion-body collapse" aria-labelledby="heading' + item.CAT_NUM + '" data-parent="#categoryAccordion">' +
                '<div id="SubCatOrItemData_' + item.CAT_NUM + '" class="card-body px-0" >' +
                //dynmic content(item list)
                '</div></div>';
            str += strCollHeading + strCollPaneldata + '</div>'
            Mainstr = Mainstr + str;
        }

        //cntcat = cntcat + 1;

        //check if language change and category selected then set category name language wise
        //if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
        //    $('#divCatename').html(catname);
        //    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
        //}
    });

    //selectedCategoryId > 0 it means Subcategory bind
    if (selectedCategoryId > 0) {
        $('#SubCatOrItemData_' + selectedCategoryId + '').html('<div class="accordion subcategory-accordion" id="accordionExample-summenu' + selectedCategoryId + '">' + Mainstr + '</div>');
    }
    else {
        $('#categoryAccordion').html(Mainstr);
    }
    //debugger;
    //if (cntcat == 1 && firstCAT_NUM > 0) {
    //    OnCategoryClick(firstCAT_NUM, firstIsHaveSubCategory);
    //}
}
function CreateCategoryHtml(Category) {
    var Mainstr = "";
    var cntcat = 0;
    var firstCAT_NUM = 0;
    var firstIsHaveSubCategory = 0;
    $.each(Category, function (i, item) {
        firstCAT_NUM = item.CAT_NUM;
        firstIsHaveSubCategory = item.IsHaveSubCategory;
        if ($('#selectedLang').val() == "EN") {
            catname = item.CAT_NAME;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            catname = item.CAT_NAME_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }
        var str = "";
        str = '<div id="Cat_' + item.CAT_NUM + '" onclick="OnCategoryClick(' + item.CAT_NUM + ',' + item.IsHaveSubCategory + ');" data-val="' + catname + '" data-text="' + cntcat + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4">' +
            '<a class="card-primary ml-1 mr-1" >' +
            '<img class="card-img-top img-responsive img-Category" src="../../ThumbnailImages/' + item.ImageName + '" alt="">' +
            '<div class="card-body-category">' +
            '<h3>' + catname + '</h3>' +
            '</div>' +
            '</a>' +
            '</div>';
        Mainstr = Mainstr + str;
        cntcat = cntcat + 1;

        //check if language change and category selected then set category name language wise
        if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
            $('#divCatename').html(catname);
            $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
        }
    });
    $('#categoryList').html(Mainstr);
    debugger;
    if (cntcat == 1 && firstCAT_NUM > 0) {
        OnCategoryClick(firstCAT_NUM, firstIsHaveSubCategory);
    }
}
function BindSelectedCategoryItems(Items, ItemsAllergenList) {
    debugger;
    var Mainstr = "";
    var ScrollItemsstr = "";
    var selectedCat_num = 0;

    //var selectedCate="";
    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }
        // filter item wise allergen List
        allergenList = ItemsAllergenList.filter(function (entry) {
            return entry.itemId === item.id;
        });

        var str = "";
        str = '<div id="Item_' + item.UID + '" data-val="' + item.CAT_NUM + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4" >' +
            '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
            '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
            '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
            '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
            '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + item.PRICE + '"/>' +
            '<div class="position-relative"> ';
        if ($('#hdnIsShowAllergen').val() == "1") {
            str += bindAllergensHtml(allergenList);
        }
        str += '<div class="card-primary ml-1 mr-1">' +
            '<img onclick="OnItemClick(' + item.id + ',' + item.HID + ');" class="card-img-top img-responsive img-Item" src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="">' +
            '<div class="card-body">' +
            //'<div style="width:100% !important">' + strAllergens+'</div>'+
            '<h4 onclick="OnItemClick(' + item.id + ',' + item.HID + ');" class="pb-0">' + ItemName + '</h4>' +
            '</div>' +
            '<div class="card-footer">' +
            '<div class="row no-gutters align-items-center justify-content-between">';
        if (allergenList.length > 0) {
            //str += '<div class="col-auto">' +
            //    '<span class="allergens-icon"></span>' +
            //    '</div>' +
            //    '<div class="col text-center">' +
            //    '<span class="price pb-0">' + selectedCurrency + '. ' + item.PRICE + '</span>' +
            //    '</div>';
            if ($('#hdnIsShowAllergen').val() == "1") {
                str += '<div class="col-auto">' +
                    '<span class="allergens-icon"></span>' +
                    '</div>';
            }
            str += '<div class="col text-left">' +
                '<span class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</span>' +
                '</div>';
        }
        else {
            str += '<div class="col-auto">' +
                '<span class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</span>' +
                '</div>';
        }


        str += '<div class="col-auto">';
        if ($('#hdnIsCartVisible').val() == '1') {
            //str = str + '<a href="#" onclick="addItemclick(' + item.id + ',' + item.HID + ');" title="Add to Cart" class="btn btn-sm btn-plus">' +
            //    '<span class="text-icon">+</span>' +
            //    '</a>';
            //str = str + '<a href="#" onclick="OnItemClick(' + item.id + ',' + item.HID + ');" title="Add to Cart" class="btn btn-sm btn-plus">' +
            //    '<span class="text-icon"><svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">' +
            //    '<path d="M16.44 8.7C14.925 5.1825 12.075 3 8.99999 3C5.92499 3 3.07499 5.1825 1.55999 8.7C1.51869 8.79462 1.49738 8.89676 1.49738 9C1.49738 9.10324 1.51869 9.20538 1.55999 9.3C3.07499 12.8175 5.92499 15 8.99999 15C12.075 15 14.925 12.8175 16.44 9.3C16.4813 9.20538 16.5026 9.10324 16.5026 9C16.5026 8.89676 16.4813 8.79462 16.44 8.7V8.7ZM8.99999 13.5C6.62249 13.5 4.37249 11.7825 3.07499 9C4.37249 6.2175 6.62249 4.5 8.99999 4.5C11.3775 4.5 13.6275 6.2175 14.925 9C13.6275 11.7825 11.3775 13.5 8.99999 13.5ZM8.99999 6C8.40665 6 7.82663 6.17595 7.33328 6.50559C6.83993 6.83524 6.45541 7.30377 6.22835 7.85195C6.00129 8.40013 5.94188 9.00333 6.05763 9.58527C6.17339 10.1672 6.45911 10.7018 6.87867 11.1213C7.29823 11.5409 7.83278 11.8266 8.41472 11.9424C8.99666 12.0581 9.59986 11.9987 10.148 11.7716C10.6962 11.5446 11.1648 11.1601 11.4944 10.6667C11.824 10.1734 12 9.59334 12 9C12 8.20435 11.6839 7.44129 11.1213 6.87868C10.5587 6.31607 9.79564 6 8.99999 6V6ZM8.99999 10.5C8.70332 10.5 8.41331 10.412 8.16663 10.2472C7.91996 10.0824 7.7277 9.84811 7.61417 9.57402C7.50064 9.29994 7.47093 8.99834 7.52881 8.70736C7.58669 8.41639 7.72955 8.14912 7.93933 7.93934C8.14911 7.72956 8.41638 7.5867 8.70735 7.52882C8.99833 7.47094 9.29992 7.50065 9.57401 7.61418C9.8481 7.72771 10.0824 7.91997 10.2472 8.16664C10.412 8.41332 10.5 8.70333 10.5 9C10.5 9.39782 10.342 9.77936 10.0606 10.0607C9.77934 10.342 9.39781 10.5 8.99999 10.5Z" fill="white"/>' +
            //    '</svg></span>' +
            //    '</a>';
            str = str + '<a href="#" onclick="OnItemClick(' + item.id + ',' + item.HID + ');" title="Add to Cart" class="btn btn-sm btn-plus">' +
                '<span class="text-icon">View</span>' +
                '</a>';
            //str = str + "<div onclick='addItemclick(" + item.id + "," + item.HID + ");' class='addbutton' style='float:right !important;'>+</div>";
        }
        str = str + '</div>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        Mainstr = Mainstr + str;

        var Scrollstr = "";

        Scrollstr = '<div class="item" id="ScrollItem_' + item.id + '" data-val="' + item.CAT_NUM + '" onclick="OnItemClick(' + item.id + ',' + item.HID + ');">' +
            '<a href="#" class="card-primary ml-1 mr-1">' +
            '<img class="card-img-top img-responsive" src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="">' +
            '<div class="card-body">' +
            '<h3>' + ItemName + '</h3>' +
            '</div>' +
            '</a>' +
            '</div>';
        ScrollItemsstr = ScrollItemsstr + Scrollstr;


        //check if language change and category selected then set category name language wise
        //if (selectedItemid > 0 && item.id == selectedItemid) {
        //    $('#divCatename').html(ItemName);
        //}
    });
    $('#itemlist').html(Mainstr);
    //$('#divScrollItemList').html(ScrollItemsstr);
    debugger;
    var isrtl = false;
    if ($('#selectedLang').val() == "EN") {
        isrtl = false
    }
    else {
        isrtl = true
    }

    var carousel = jQuery(".owl-carousel");
    carousel.trigger('destroy.owl.carousel');
    carousel.find('.owl-stage-outer').children().unwrap();
    carousel.removeClass("owl-center owl-loaded owl-text-select-on");
    carousel.html(ScrollItemsstr);
    carousel.owlCarousel({
        //loop: true,
        margin: 10,
        dots: false,
        //autoplay: true,
        rtl: isrtl,
        responsive: {
            0: {
                items: 3
            },
            420: {
                items: 4
            },
            575: {
                items: 5
            },
            768: {
                items: 6
            },
            992: {
                items: 4
            },
        }

    });




    if (selectedItemid > 0) {
        OnItemClick(selectedItemid, selectedHID);

        //$('#divCategoryList').hide()
        //$('#divMainItemList').hide();
        //$('#divMainItemDetails').show()
    }
    if ($('#hdnisCartSelected').val() == "1") {
        $('#divMainItemList').hide();
        $('#divCategoryList').hide();
        $('#divMainItemDetails').hide();
        $('#divMainItemDetails').hide();
        $('#divCartView').show();
        //$('.banner').height(0);
        if ($('.banner').hasClass('d-block')) {
            $('.banner').removeClass('d-block').addClass('d-none');
        }
    }

    if (($('#hdnDesignName').val() == "Design1") ) {
        $('#divCategoryList').show();
        $('#divMainItemList').hide();
    }
}
function BindSelectedCategoryItemsForWaiter(Items, ItemsAllergenList) {
    debugger;
    var Mainstr = "";
    var ScrollItemsstr = "";
    var selectedCat_num = 0;

    //var selectedCate="";
    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }
        // filter item wise allergen List
        allergenList = ItemsAllergenList.filter(function (entry) {
            return entry.itemId === item.id;
        });

        var str = "";
        str = '<div id="Item_' + item.UID + '" data-val="' + item.CAT_NUM + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4" >' +
            '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
            '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
            '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
            '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
            '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '"/>' +
            '<div class="position-relative"> ';
        if ($('#hdnIsShowAllergen').val() == "1") {
            str += bindAllergensHtml(allergenList);
        }

        debugger;
        var onItemClickEvent = "";
        if (item.MinGroupModifierSelection == "1") {
            onItemClickEvent = " OnItemClickShowPopup(" + item.id + "," + item.HID + "); data-toggle='modal' data-target='#itemDetailModal' ";
        }
        else {
            onItemClickEvent = " addDirectItemInToCartclick(0," + item.id + "," + item.HID + ",1); ";
        }

        str += '<div class="card-primary ml-1 mr-1">' +
            '<img onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')"; data-toggle="modal" data-target="#itemDetailModal" class="card-img-top img-responsive img-Item" src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="">' +
            '<div class="card-body">' +
            //'<div style="width:100% !important">' + strAllergens+'</div>'+
            '<h4 onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')"; data-toggle="modal" data-target="#itemDetailModal" class="pb-0">' + ItemName + '</h4>' +
            '</div>' +
            '<div class="card-footer">' +
            '<div class="row no-gutters align-items-center justify-content-between">';
        if (allergenList.length > 0) {
            //str += '<div class="col-auto">' +
            //    '<span class="allergens-icon"></span>' +
            //    '</div>' +
            //    '<div class="col text-center">' +
            //    '<span class="price pb-0">' + selectedCurrency + '. ' + item.PRICE + '</span>' +
            //    '</div>';
            if ($('#hdnIsShowAllergen').val() == "1") {
                str += '<div class="col-auto">' +
                    '<span class="allergens-icon"></span>' +
                    '</div>';
            }
            str += '<div class="col text-left">' +
                '<span class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</span>' +
                '</div>';
        }
        else {
            str += '<div class="col-auto">' +
                '<span class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</span>' +
                '</div>';
        }


        str += '<div class="col-auto">';
        if ($('#hdnIsCartVisible').val() == '1') {
            //str = str + '<a href="#" onclick="addItemclick(' + item.id + ',' + item.HID + ');" title="Add to Cart" class="btn btn-sm btn-plus">' +
            //    '<span class="text-icon">+</span>' +
            //    '</a>';
            //str = str + '<a href="#" onclick="OnItemClick(' + item.id + ',' + item.HID + ');" title="Add to Cart" class="btn btn-sm btn-plus">' +
            //    '<span class="text-icon"><svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">' +
            //    '<path d="M16.44 8.7C14.925 5.1825 12.075 3 8.99999 3C5.92499 3 3.07499 5.1825 1.55999 8.7C1.51869 8.79462 1.49738 8.89676 1.49738 9C1.49738 9.10324 1.51869 9.20538 1.55999 9.3C3.07499 12.8175 5.92499 15 8.99999 15C12.075 15 14.925 12.8175 16.44 9.3C16.4813 9.20538 16.5026 9.10324 16.5026 9C16.5026 8.89676 16.4813 8.79462 16.44 8.7V8.7ZM8.99999 13.5C6.62249 13.5 4.37249 11.7825 3.07499 9C4.37249 6.2175 6.62249 4.5 8.99999 4.5C11.3775 4.5 13.6275 6.2175 14.925 9C13.6275 11.7825 11.3775 13.5 8.99999 13.5ZM8.99999 6C8.40665 6 7.82663 6.17595 7.33328 6.50559C6.83993 6.83524 6.45541 7.30377 6.22835 7.85195C6.00129 8.40013 5.94188 9.00333 6.05763 9.58527C6.17339 10.1672 6.45911 10.7018 6.87867 11.1213C7.29823 11.5409 7.83278 11.8266 8.41472 11.9424C8.99666 12.0581 9.59986 11.9987 10.148 11.7716C10.6962 11.5446 11.1648 11.1601 11.4944 10.6667C11.824 10.1734 12 9.59334 12 9C12 8.20435 11.6839 7.44129 11.1213 6.87868C10.5587 6.31607 9.79564 6 8.99999 6V6ZM8.99999 10.5C8.70332 10.5 8.41331 10.412 8.16663 10.2472C7.91996 10.0824 7.7277 9.84811 7.61417 9.57402C7.50064 9.29994 7.47093 8.99834 7.52881 8.70736C7.58669 8.41639 7.72955 8.14912 7.93933 7.93934C8.14911 7.72956 8.41638 7.5867 8.70735 7.52882C8.99833 7.47094 9.29992 7.50065 9.57401 7.61418C9.8481 7.72771 10.0824 7.91997 10.2472 8.16664C10.412 8.41332 10.5 8.70333 10.5 9C10.5 9.39782 10.342 9.77936 10.0606 10.0607C9.77934 10.342 9.39781 10.5 8.99999 10.5Z" fill="white"/>' +
            //    '</svg></span>' +
            //    '</a>';
            str = str + '<a href="#" onclick=' + onItemClickEvent +' title="Add to Cart" class="btn btn-sm btn-plus">' +
                '<span class="text-icon">+</span>' +
                '</a>';
            //str = str + "<div onclick='addItemclick(" + item.id + "," + item.HID + ");' class='addbutton' style='float:right !important;'>+</div>";
        }
        str = str + '</div>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        Mainstr = Mainstr + str;

        var Scrollstr = "";

        Scrollstr = '<div class="item" id="ScrollItem_' + item.id + '" data-val="' + item.CAT_NUM + '" onclick=' + onItemClickEvent +'>' +
            '<a href="#" class="card-primary ml-1 mr-1">' +
            '<img class="card-img-top img-responsive" src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="">' +
            '<div class="card-body">' +
            '<h3>' + ItemName + '</h3>' +
            '</div>' +
            '</a>' +
            '</div>';
        ScrollItemsstr = ScrollItemsstr + Scrollstr;


        //check if language change and category selected then set category name language wise
        //if (selectedItemid > 0 && item.id == selectedItemid) {
        //    $('#divCatename').html(ItemName);
        //}
    });
    $('#itemlist').html(Mainstr);
    //$('#divScrollItemList').html(ScrollItemsstr);
    debugger;
    var isrtl = false;
    if ($('#selectedLang').val() == "EN") {
        isrtl = false
    }
    else {
        isrtl = true
    }

    var carousel = jQuery(".owl-carousel");
    carousel.trigger('destroy.owl.carousel');
    carousel.find('.owl-stage-outer').children().unwrap();
    carousel.removeClass("owl-center owl-loaded owl-text-select-on");
    carousel.html(ScrollItemsstr);
    carousel.owlCarousel({
        //loop: true,
        margin: 10,
        dots: false,
        //autoplay: true,
        rtl: isrtl,
        responsive: {
            0: {
                items: 3
            },
            420: {
                items: 4
            },
            575: {
                items: 5
            },
            768: {
                items: 6
            },
            992: {
                items: 4
            },
        }

    });




    if (selectedItemid > 0) {
        OnItemClick(selectedItemid, selectedHID);

        //$('#divCategoryList').hide()
        //$('#divMainItemList').hide();
        //$('#divMainItemDetails').show()
    }
    if ($('#hdnisCartSelected').val() == "1") {
        $('#divMainItemList').hide();
        $('#divCategoryList').hide();
        $('#divMainItemDetails').hide();
        $('#divMainItemDetails').hide();
        $('#divCartView').show();
        //$('.banner').height(0);
        if ($('.banner').hasClass('d-block')) {
            $('.banner').removeClass('d-block').addClass('d-none');
        }
    }

    if (($('#hdnDesignName').val() == "Design1")) {
        $('#divCategoryList').show();
        $('#divMainItemList').hide();
    }
}
function bindAllergensHtml(allergenList, opts) {
    debugger;
    // opts (all optional, default = original overlay-on-image behaviour):
    //   wrapperClass - classes added to the outer .dropdown div in place of the
    //                  default 'position-absolute allergens' (e.g. Design1's
    //                  inline-with-item-name icon uses 'position-absolute allergens allergens-inline').
    //   dropup       - pass false to open the menu downward instead of upward.
    //   menuRight    - pass true to right-align the menu (opens toward the left)
    //                  instead of the Bootstrap default left-aligned (opens toward the right).
    var str = '';
    opts = opts || {};
    var wrapperClass = opts.wrapperClass || 'position-absolute allergens';
    var dropupClass = (opts.dropup === false) ? '' : 'dropup ';
    var menuClass = 'dropdown-menu' + (opts.menuRight ? ' dropdown-menu-right' : '');
    if (allergenList.length > 0) {
        // stopPropagation on the wrapper catches clicks anywhere in the widget
        // (toggle button, menu, list items) so they never bubble up into a
        // parent item-card's own onclick (e.g. CreateCategorySlider's
        // .card-body, which opens the Item Details view/modal) - some designs
        // wrap this whole component in an element that has its own onclick,
        // which previously caused a click on the allergen icon to ALSO open
        // the item (looked like the page "refreshing") before the dropdown
        // opened underneath it. Since stopPropagation here also blocks the
        // click from ever reaching document, Bootstrap's normal
        // document-delegated "[data-toggle=dropdown]" auto-open no longer
        // fires - so the toggle button calls $(this).dropdown('toggle')
        // itself to replace it.
        str = '<div class="dropdown ' + dropupClass + wrapperClass + '" onclick="event.stopPropagation();">' +
            '<button class="btn bg-transparent dropdown-toggle" type="button" data-toggle="dropdown" aria-expanded="false" onclick="event.stopPropagation(); $(this).dropdown(\'toggle\');">' +
            '<img src="../../allergenImages/assign_allergen.png" height="20px" width="20px" alt="">' +
            '</button>' +
            '<div class="' + menuClass + '">' +
            '<ul>';
        $.each(allergenList, function (i, allergen) {
            var allergenName = "";
            if ($('#selectedLang').val() == "EN") {
                allergenName = allergen.allergenName;
            }
            else {
                allergenName = allergen.allergenNameArabic;
            }

            str += '<li class="media">' +
                '<span class="media-img mr-2">' +
                '<img src="../../allergenImages/' + allergen.image + '" height="20px" width="20px" alt="" onerror="this.style.display=\'none\'">' +
                '</span>' +
                '<div class="media-body">' + allergenName + '</div>' +
                '</li>';
            //'<svg height="512" viewBox="0 0 64 64" width="512" xmlns="http://www.w3.org/2000/svg"><g id="Soy"><path d="m63.31 27.35c-.36 4.68-2.45 9.14-9.19 12.43-2.77 8.13-9.12 12.95-17.13 12.95h-.01a20.24475 20.24475 0 0 1 -2.88-.21 19.90642 19.90642 0 0 1 -11.54 3.65 26.01508 26.01508 0 0 1 -13.59-4.24 14.24985 14.24985 0 0 0 9.19 7.75 17.96243 17.96243 0 0 0 5.16.76 16.96735 16.96735 0 0 0 12.05-4.82 18.8959 18.8959 0 0 0 14.5-2.8 14.55588 14.55588 0 0 0 6.03-9.56c3.86-1.55 6.37-4.02 7.46-7.35a15.19227 15.19227 0 0 0 -.05-8.56z" /><path d="m48.90234 33.38672c1.80274-.24707 4.68067-2.83692 4.98243-4.93555a1.9324 1.9324 0 0 0 -1.418-2.10156 2.20727 2.20727 0 0 0 -.666-.10352 2.06113 2.06113 0 0 0 -1.88277 1.29791 4.76922 4.76922 0 0 1 -1.97363 1.94238 1.92221 1.92221 0 0 0 -1.21582 2.37988 2.078 2.078 0 0 0 2.17379 1.52046z" /><path d="m33.59961 50.41113c8.83594 1.61719 16.1709-3.07617 18.88281-12.07422 8.95507-4.02539 9.28906-9.85644 8.751-15.52343l2.02734-5.166a2.213 2.213 0 0 0 -1.4414-2.92773l-.65336-.19045a2.78768 2.78768 0 0 0 -3.1211 1.13281l-2.8623 4.2666c-8.23828 1.24317-13.24121 5.09961-14.88379 11.4707-6.3584-.43457-10.98389 2.2334-12.65528 7.26172-8.99365-1.82324-14.71386.86719-19.58691 9.124a1 1 0 0 0 .28369 1.32422c4.76465 3.37207 9.62158 5.06445 14.21582 5.06445a18.09944 18.09944 0 0 0 11.04348-3.76267zm13.46-22.71777a2.81892 2.81892 0 0 0 1.0791-1.0625 4.047 4.047 0 0 1 4.94429-2.18359 3.9307 3.9307 0 0 1 2.78028 4.30173c-.44433 3.082-4.11914 6.27539-6.70215 6.6211l-.01465.002a3.91205 3.91205 0 0 1 -.46386.02734 4.075 4.075 0 0 1 -3.8711-2.96191 3.93007 3.93007 0 0 1 2.24805-4.74417zm-11.749 9.86133a3.17818 3.17818 0 0 0 1.47851-.8418 4.27568 4.27568 0 0 1 5.70508-.88965 4.195 4.195 0 0 1 1.68164 5.2002c-1.23144 2.87207-5.4043 5.06347-8.22265 5.06347a4.82191 4.82191 0 0 1 -.6045-.03613l-.01562-.00293a4.32772 4.32772 0 0 1 -3.65479-4.22265 4.19806 4.19806 0 0 1 3.63227-4.27051zm-18.30524 11.88281-.01123-.00879a4.2037 4.2037 0 0 1 -1.0498-5.32519 4.13693 4.13693 0 0 1 5.20366-1.86817 3.11918 3.11918 0 0 0 1.65185.00781 4.251 4.251 0 0 1 5.30074 2.04784 4.07813 4.07813 0 0 1 -1.148 5.19628 8.27458 8.27458 0 0 1 -4.832 1.334 8.95389 8.95389 0 0 1 -5.11522-1.38378z" /><path d="m23.41357 44.14648a5.11605 5.11605 0 0 1 -2.89794-.01367 2.17051 2.17051 0 0 0 -2.8086.916 2.21734 2.21734 0 0 0 .51221 2.7998c1.55713 1.17188 5.72021 1.38379 7.55224.02442a2.07906 2.07906 0 0 0 .54444-2.67871 2.22912 2.22912 0 0 0 -2.90235-1.04784z" /><path d="m35.6123 44.06738c1.99415.248 5.80665-1.69043 6.73047-3.84375a2.19727 2.19727 0 0 0 -.93652-2.72265 2.302 2.302 0 0 0 -3.13281.55175 5.17911 5.17911 0 0 1 -2.56739 1.4629 2.18074 2.18074 0 0 0 -2.02832 2.2539 2.34118 2.34118 0 0 0 1.93457 2.29785z" /><path d="m22.68 36.12a24.433 24.433 0 0 1 3.72.29c2.17-4.47 6.6-7.02 12.44-7.06 1.62-4.5 5.61-9.56 15.16-11.25l2.2-3.28c-.03-.78-.09-1.57-.16-2.34l2.22-5.66a2.15624 2.15624 0 0 0 -1.4-2.86l-.99-.29a2.695 2.695 0 0 0 -3.03 1.1l-3.15 4.7c-8.81 1.32-14.14 5.44-15.87 12.26-6.8-.49-11.75 2.36-13.52 7.75-8.93-1.82-14.88.57-19.76 7.9a3.10179 3.10179 0 0 0 .93 4.3 30.27111 30.27111 0 0 0 6.21 2.98c4.02-5.82 8.84-8.54 15-8.54zm-13.14924-.84266c-2.54443.73731-4.15185 3.60743-4.168 3.63575a.9996.9996 0 1 1 -1.751-.96485c.2041-.37011 2.08789-3.64355 5.3623-4.59277a1.00043 1.00043 0 0 1 .55664 1.92187z" /></g></svg>' +
        });


        //'<li class="media">' +
        //'<span class="media-img mr-2">' +
        //'<svg id="Layer_1" enable-background="new 0 0 479.933 479.933" height="512" viewBox="0 0 479.933 479.933" width="512" xmlns="http://www.w3.org/2000/svg"><g><path d="m235.678 27.781c-12.86-4.2-24.4-10.74-34.3-19.45-12.63-11.11-31.69-11.11-44.34.01-9.89 8.7-21.43 15.24-34.3 19.44-163.556 53.348-163.624 336.206.02 389.61 12.85 4.19 24.39 10.74 34.3 19.45 12.529 11.04 31.615 11.176 44.33-.01.389-.342.78-.68 1.174-1.014 2.137-1.815 3.165-4.634 2.671-7.394-.451-2.521-.726-5.06-.828-7.597-.101-2.506-1.407-4.829-3.472-6.253-17.162-11.835-27.352-31.513-26.453-52.443.083-1.924-.591-3.762-1.763-5.289-1.649-2.149-2.165-5.082-1.1-7.789.6-1.536 1.147-3.144 1.638-4.809.578-1.963.338-4.083-.626-5.888-9.474-17.759-10.576-37.101-4.622-54.416.465-1.354.532-2.818.208-4.212-4.385-18.866-3.335-41.954 3.162-58.814 7.62-19.774 6.43-44.126.57-59.27-8.955-23.144-7.929-52.1-.38-71.23 1.63-4.11 6.27-6.12 10.38-4.5s6.13 6.271 4.51 10.38c-5.961 15.091-7.324 39.442.42 59.6 7.455 19.407 8.379 47.713-.58 70.78-1.608 4.14-2.79 8.804-3.585 13.719-1.137 7.031 6.665 11.912 12.519 7.856.739-.512 1.488-1.012 2.248-1.498 1.991-1.275 3.323-3.339 3.668-5.678 6.373-43.118 41.395-49.665 60.408-50.5 5.537-.243 9.23-5.888 7.091-11.001-3.828-9.154-6.08-18.434-6.08-30.527 0-23.35-12.56-45.1-32.78-56.77-3.83-2.21-5.14-7.1-2.93-10.93s7.11-5.14 10.93-2.93c25.15 14.521 40.78 41.59 40.78 70.63 0 8.209 1.547 16.343 4.536 23.946 1.689 4.299 6.609 6.318 10.809 4.395 15.158-6.941 32.137-9.079 47.818-5.836 5.733 1.186 10.676-4.145 9.262-9.825-15.335-61.649-54.081-113.954-115.313-133.943zm-150.73 227.58c7.14 12.38 10.92 26.48 10.92 40.77 0 23.35 12.56 45.1 32.78 56.77 3.82 2.21 5.13 7.1 2.92 10.93-2.17 3.754-7.003 5.169-10.92 2.93-25.15-14.53-40.78-41.59-40.78-70.63 0-11.49-3.03-22.82-8.78-32.77-14.52-25.15-14.52-56.4 0-81.55 5.75-9.95 8.78-21.28 8.78-32.77 0-29.04 15.63-56.11 40.78-70.63 3.82-2.21 8.72-.89 10.92 2.93 2.21 3.83.9 8.72-2.92 10.93-20.22 11.67-32.78 33.42-32.78 56.77 0 14.29-3.78 28.39-10.92 40.77-11.68 20.22-11.68 45.331 0 65.55z" /><path d="m372.945 220.505-57.329 121.245c-1.397 2.947-5.502 3.053-7.119.221-8.432-14.767-23.967-23.404-41.159-24.42-4.41-.23-8.2 3.1-8.46 7.51-.26 4.42 3.1 8.2 7.51 8.46 4.73.29 16.61 1.98 24.88 11.63 8.398 9.813 10.137 24.48 4.84 37.82-.09.226 2.039-4.31-33.358 70.577-.601 1.271-1.828 2.147-3.228 2.282-25.391 2.454-43.297-21.135-38.365-45.205.376-1.833-.627-3.699-2.356-4.414-22.786-9.432-35.255-34.917-24.257-60.682.58-1.358.352-2.934-.591-4.071-25.569-30.831-12.749-71.025 20.027-85.474 1.468-.647 2.392-2.117 2.362-3.721-.518-27.725 23.069-52.621 55.726-44.061 4.184 1.102 8.419 2.912 11.33 4.45 1.161.613 4.383 2.984 7.15 6.14 9.988 11.391 10.727 27.385.84 39.69-6.727 8.394 5.75 18.326 12.37 10.17 16.642-20.526 13.91-50.964-8.705-67.418-2.314-1.683-2.116-5.242.371-6.656 28.53-16.225 66.565-9.809 77.714 22.971.329.966.243 2.034-.193 2.956z" /><path d="m387.394 227.347c.437-.923 1.209-1.669 2.166-2.027 32.474-12.186 61.475 13.191 67.054 45.394.492 2.842-2.094 5.278-4.891 4.575-25.541-6.424-51.92 8.617-57.605 35.943-2.163 10.38 13.518 13.673 15.65 3.35 3.049-14.756 15.361-25.179 31.24-24.65 7.99.259 11.557 2.274 18.205 6.385 1.977 1.223 6.096 4.443 8.995 7.505 18.277 19.307 14.201 48.755-5.97 64.693-1.263.998-1.821 2.646-1.39 4.197 9.489 34.11-12.876 69.935-53.363 69.717-1.479-.008-2.841.819-3.524 2.131-12.787 24.594-40.314 31.499-62.289 19.751-1.65-.882-3.727-.469-4.905.985-15.441 19.074-44.956 20.28-59.275-.963-.788-1.168-.895-2.67-.292-3.944 18.728-39.588 17.301-36.775 17.941-37.437 9.931-10.272 25.444-11.917 35.946-.571 7.178 7.753 18.947-3.097 11.74-10.88-8.103-8.749-18.863-13.271-30.024-12.949-2.953.085-4.918-3.045-3.656-5.716 6.803-14.389 23.894-50.53 23.944-50.62 6.955-12.572 19.392-20.524 32.315-20.275 4.37.1 8.07-3.41 8.16-7.83.09-4.41-3.41-8.07-7.83-8.16-2.971-.067-5.919.154-8.816.645-3.21.543-5.72-2.702-4.328-5.645z" /></g></svg>' +
        //'</span>' +
        //'<div class="media-body">Walnut</div>' +
        //'</li>' +
        //'<li class="media">' +
        //'<span class="media-img mr-2">' +
        //'<svg id="Layer_3" enable-background="new 0 0 64 64" height="512" viewBox="0 0 64 64" width="512" xmlns="http://www.w3.org/2000/svg"><path d="m57.47 16.434c1.151.986 2.045 2.205 2.647 3.554-1.954-1.786-4.485-2.836-7.17-2.956-.039-.439-.096-.876-.182-1.306-.111-.556-.27-1.093-.454-1.616 1.895.27 3.69 1.066 5.159 2.324zm-43.351-7.434c2.362 0 4.689.629 6.729 1.819l3.604 2.103c.919.536 1.888.983 2.872 1.385-.478.929-.876 1.91-1.158 2.947-.052.192-.115.379-.172.569-.82-.615-1.583-1.305-2.272-2.07-2.718-3.021-6.608-4.753-10.671-4.753-2.184 0-4.316.612-6.168 1.769l-1.176.735c1.817-2.713 4.909-4.504 8.412-4.504zm-8.846 15.033c-.833-1.499-1.273-3.199-1.273-4.914 0-.818.108-1.61.292-2.372l3.651-2.282c1.533-.959 3.299-1.465 5.108-1.465 3.497 0 6.846 1.491 9.186 4.091.92 1.023 1.959 1.926 3.084 2.708-2.305 5.846-6.775 10.582-12.57 13.216l-.641.292c-2.656-2.793-4.963-5.902-6.837-9.274zm21.323 29.729c-3.839 1.485-7.871 2.238-11.985 2.238-1.008 0-2.023-.092-3.018-.271-4.979-.907-8.593-5.237-8.593-10.298 0-3.515 2.068-6.727 5.269-8.182l5.311-2.414c7.156-3.253 12.448-9.469 14.518-17.055 1.242-4.553 4.797-8.011 9.181-9.263-3.13 3.137-5.351 7.096-6.344 11.461-1.748 7.692-7.18 13.99-14.53 16.849-3.955 1.538-7.349 4.175-9.812 7.627l-1.404 1.966 1.627 1.162 1.404-1.966c2.238-3.134 5.319-5.529 8.91-6.926 7.971-3.099 13.86-9.928 15.757-18.269 1.125-4.951 3.966-9.345 7.998-12.42.004 0 .01-.001.016-.001 4.797 0 8.962 3.414 9.902 8.119.131.651.197 1.317.197 2.027 0 15.653-9.808 29.965-24.404 35.616zm28.492-17.827c-2.828 2.121-5.922 3.78-9.221 4.967 4.362-6.341 6.928-13.919 7.115-21.871 2.925.171 5.623 1.68 7.265 4.143l.742 1.113c-.056 4.562-2.247 8.906-5.901 11.648z" /></svg>' +
        //'</span>' +
        //'<div class="media-body">Cashew</div>' +
        //'</li>' +
        //'<li class="media">' +
        //'<span class="media-img mr-2">' +
        //'<svg version="1.1" id="Capa_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"' +
        //'viewBox="0 0 512 512" style="enable-background:new 0 0 512 512;" xml:space="preserve">' +
        //'<g>' +
        //'<g>' +
        //'<path d="M503.231,114.837L397.164,8.771c-11.693-11.695-30.731-11.695-42.426,0c-11.695,11.693-11.695,30.732,0,42.426' +
        //'l106.066,106.066c11.695,11.695,30.732,11.695,42.427,0C514.924,145.569,514.924,126.532,503.231,114.837z"/>' +
        //'</g>' +
        //'</g>' +
        //'<g>' +
        //'<g>' +
        //'<path d="M157.383,278.106L25.107,388.586c-15.029,12.523-24.144,30.92-25.036,50.453c-0.881,19.547,6.537,38.688,20.374,52.526' +
        //'c13.828,13.828,32.97,21.244,52.515,20.365c19.536-0.892,37.932-10.007,50.403-24.985L233.89,354.613L157.383,278.106z"/>' +
        //'</g>' +
        //'</g>' +
        //'<g>' +
        //'<g>' +
        //'<path d="M312.311,305.756L206.245,199.69c-11.693-11.695-30.732-11.695-42.426,0c-11.695,11.695-11.695,30.732,0,42.426' +
        //'l106.066,106.067c11.695,11.693,30.732,11.693,42.426,0C324.006,336.488,324.006,317.451,312.311,305.756z"/>' +
        //'</g>' +
        //'</g>' +
        //'<g>' +
        //'<g>' +
        //'<path d="M460.804,199.689L312.311,51.197c-11.693-11.693-30.731-11.693-42.426,0c-11.695,11.695-11.695,30.732,0,42.427' +
        //'l148.493,148.491c11.693,11.695,30.732,11.695,42.426,0C472.499,230.422,472.499,211.384,460.804,199.689z"/>' +
        //'</g>' +
        //'</g>' +
        //'<g>' +
        //'<g>' +
        //'<path d="M397.164,263.329L248.672,114.837c-11.695-11.695-30.732-11.695-42.427,0c-11.693,11.695-11.693,30.732,0,42.426' +
        //'l148.493,148.492c11.695,11.695,30.732,11.695,42.426,0C408.859,294.062,408.859,275.023,397.164,263.329z"/>' +
        //'</g>' +
        //'</g>' +
        //'<g>' +
        //'<g>' +
        //'<path d="M435.537,280.488c1.128,16.691-4.427,33.749-17.159,46.48c-18.497,18.497-46.058,22.132-68.394,11.385' +
        //'c-2.181,11.38-7.665,22.245-16.459,31.042c-18.311,18.311-45.115,22.079-67.327,11.733l-0.004,60.059' +
        //'c0,12.014,4.28,23.326,12.785,31.829c8.492,8.494,19.805,13.176,31.82,13.176c22.745,0,40.829-17.223,43.821-39.159' +
        //'c0.762-1.798,1.185-3.774,1.185-5.847v-59.995c0-8.265,6.733-14.998,15.007-14.987c8.007-0.011,15.178,6.96,15.189,14.987v29.996' +
        //'c0,24.051,20.806,45.016,44.794,44.996c12.015,0,23.326-4.682,31.82-13.176c8.503-8.503,13.185-19.814,13.176-31.82l0.007-142.899' +
        //'C463.971,277.264,449.705,281.444,435.537,280.488z"/>' +
        //'</g>' +
        //'</g>' +
        //'</svg>' +
        //'</span>' +
        //'<div class="media-body">Honey</div>' +
        //'</li>' +

        str += '</ul>' +
            '</div>' +
            '</div>';
    }
    return str;
}
// Auto-close an open allergen dropdown (see bindAllergensHtml above) once its
// toggle button scrolls out of the viewport, so a stale open menu doesn't
// keep floating in place over unrelated content further down/up the page.
// Bound once at script load (page scrolls the window/body directly - no
// inner scrollable wrapper in this layout), not per render.
$(window).on('scroll resize', function () {
    $('.allergens .dropdown-toggle[aria-expanded="true"]').each(function () {
        var rect = this.getBoundingClientRect();
        var viewportHeight = window.innerHeight || document.documentElement.clientHeight;
        var stillVisible = rect.bottom > 0 && rect.top < viewportHeight;
        if (!stillVisible) {
            $(this).dropdown('hide');
        }
    });
});
function BindSelectedCategoryItemsDesign1(Items, cat_num, ItemsAllergenList) {
    debugger;
    var str = "";
    //str = str + BindSubCategoryItemsDesign1(cat_num);
    //if main category have direct items then bind it.
    if (Items.length > 0) {
        var selectedCurrency = "";
        $.each(Items, function (i, item) {
            var allergenList = ItemsAllergenList.filter(function (entry) {
                return entry.itemId === item.id;
            });
            var ItemName = "";
            var INGREDIENT = "";
            if ($('#selectedLang').val() == "EN") {
                ItemName = item.ITEM_NAME;
                INGREDIENT = item.INGREDIENT;
                selectedCurrency = $('#hdnCurrencyENG').val();
            }
            else {
                ItemName = item.ITEM_NAME_ARABIC;
                INGREDIENT = item.INGREDIENT_ARABIC;
                selectedCurrency = $('#hdnCurrencyArab').val();
            }

            ///Begin bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///
            var addButtonClick = "";
            if (item.MinGroupModifierSelection == "1") {
                addButtonClick = '<a href="#" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ');" class="btn btn-primary btn-addtocart" data-toggle="modal" data-target="#itemDetailModal">+</a>';
            }
            else {
                addButtonClick = '<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary btn-addtocart">+</a>';
            }
            ///End bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///


            var itemHtmlStr = '';
            itemHtmlStr = '<div class="sub-category mb-3">' +
                '<div class="card">' +
                '<div class="row no-gutters">' +
                '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
                '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
                '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
                '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
                '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '"/>' +
                '<div class="col-4 col-md-3 col-lg-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')" data-toggle="modal" data-target="#itemDetailModal">' +
                '<div class="card-img-con"><img src="../../images/' + item.IMAGENAME + '" class="card-img" alt=""></div></div>' +
                '<div class="col-8 col-md-9 col-lg-8" >' +
                '<div class="card-body">' +
                '<div class="media">' +
                '<div class="media-body pr-3 position-relative">' +
                (($('#hdnIsShowAllergen').val() == "1") ? bindAllergensHtml(allergenList, { wrapperClass: 'position-absolute allergens allergens-inline', dropup: false, menuRight: true }) : '') +
                '<h4 class="media-body-title pb-2 pr-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')"  data-toggle="modal" data-target="#itemDetailModal">' + ItemName + '</h4>' +
                '<p class="media-body-text pb-2">' + INGREDIENT + '</p>' +
                '<p class="price pb-3">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</p>' +
                //'<ul class="list-unstyled list-inline allergen-list">' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-gluten-free.png" class="icon-allergen" alt="">' +
                //'</li>' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-celery.png" class="icon-allergen" alt=""> ' +
                //'</li>' +
                //'</ul>' +
                addButtonClick +
                //'<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary btn-addtocart">+</a>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>';
            str = str + itemHtmlStr;
        });

    }
    $('#subCategoryItesmsList_' + cat_num + '').html(str);
}
function BindSelectedCategoryItemsDesignForWaiter(Items, cat_num, ItemsAllergenList) {
    debugger;
    var str = "";
    //str = str + BindSubCategoryItemsDesign1(cat_num);
    //if main category have direct items then bind it.
    if (Items.length > 0) {
        var selectedCurrency = "";
        $.each(Items, function (i, item) {
            var allergenList = ItemsAllergenList.filter(function (entry) {
                return entry.itemId === item.id;
            });
            var ItemName = "";
            var INGREDIENT = "";
            if ($('#selectedLang').val() == "EN") {
                ItemName = item.ITEM_NAME;
                INGREDIENT = item.INGREDIENT;
                selectedCurrency = $('#hdnCurrencyENG').val();
            }
            else {
                ItemName = item.ITEM_NAME_ARABIC;
                INGREDIENT = item.INGREDIENT_ARABIC;
                selectedCurrency = $('#hdnCurrencyArab').val();
            }

            ///Begin bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///
            var addButtonClick = "";
            if (item.MinGroupModifierSelection == "1") {
                addButtonClick = '<a href="#" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ');" class="btn btn-primary btn-addtocart" data-toggle="modal" data-target="#itemDetailModal">+</a>';
            }
            else {
                addButtonClick = '<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary btn-addtocart">+</a>';
            }
            ///End bind Addbutton click HTML,If Any min Group mofier required to select then display Popup else direct add to cart///


            var itemHtmlStr = '';
            itemHtmlStr = '<div class="sub-category mb-3">' +
                '<div class="card">' +
                '<div class="row no-gutters">' +
                '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
                '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
                '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
                '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
                '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '"/>' +
                '<div class="col-4 col-md-3 col-lg-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')" data-toggle="modal" data-target="#itemDetailModal">' +
                '<div class="card-img-con"><img src="../../images/' + item.IMAGENAME + '" class="card-img" alt=""></div></div>' +
                '<div class="col-8 col-md-9 col-lg-8" >' +
                '<div class="card-body">' +
                '<div class="media">' +
                '<div class="media-body pr-3 position-relative">' +
                (($('#hdnIsShowAllergen').val() == "1") ? bindAllergensHtml(allergenList, { wrapperClass: 'position-absolute allergens allergens-inline', dropup: false, menuRight: true }) : '') +
                '<h4 class="media-body-title pb-2 pr-4" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ')"  data-toggle="modal" data-target="#itemDetailModal">' + ItemName + '</h4>' +
                '<p class="media-body-text pb-2">' + INGREDIENT + '</p>' +
                '<p class="price pb-3">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</p>' +
                //'<ul class="list-unstyled list-inline allergen-list">' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-gluten-free.png" class="icon-allergen" alt="">' +
                //'</li>' +
                //'<li class="list-inline-item">' +
                //'<img src="../../images/icon-celery.png" class="icon-allergen" alt=""> ' +
                //'</li>' +
                //'</ul>' +
                addButtonClick +
                //'<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary btn-addtocart">+</a>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '</div>';
            str = str + itemHtmlStr;
        });

    }
    $('#subCategoryItesmsList_' + cat_num + '').html(str);
}
function BindSelectedCategoryItemsDesign4(Items, cat_num, ItemsAllergenList) {
    debugger;
    var Mainstr = "";
    var ScrollItemsstr = "";
    var selectedCat_num = 0;

    //var selectedCate="";
    $.each(Items, function (i, item) {
        var allergenList = ItemsAllergenList.filter(function (entry) {
            return entry.itemId === item.id;
        });
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }

        var selectedItemQty = 0;
        if (CartDetails.length > 0) {
            var tempCartDetails = CartDetails;
            $.each(tempCartDetails, function (i, obj) {
                if (obj.I == item.id) {
                    selectedItemQty = obj.Q;
                }
            });
        }

        var str = "";

        str += '<div class="card mb-3 border-0">' +
            '<div class="card-body">' +
            '<div class="media">' +
            '<input id="hdnItemINGREDIENT_' + item.id + '" type="hidden"  value="' + INGREDIENT + '"/>' +
            '<input id="hdnITEM_NAME_' + item.id + '" type="hidden"  value="' + ItemName + '"/>' +
            '<input id="hdnItem_IMAGENAME_' + item.id + '" type="hidden"  value="' + item.IMAGENAME + '"/>' +
            '<input id="hdnItem_VideoNAME_' + item.id + '" type="hidden" value="' + item.Video + '"/>' +
            '<input id="hdnItem_PRICE_' + item.id + '" type="hidden"  value="' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '"/>';
            //'<div class="media-body pr-3" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ');" data-toggle="modal" data-target="#itemDetailModal">' +
        str += '<div class="media-body pr-3">' +
            '<h4 class="media-body-title pb-2">' + ItemName + '</h4>' +
            '<p class="media-body-text pb-2">' +
            '' + INGREDIENT + '' +
            '</p>' +
            '<p class="price pb-0">' + selectedCurrency + '. ' + round(item.PRICE, decimalPlace).toFixed(decimalPlace) + '</p>' +
            '</div>' +
            '<div class="d-flex flex-column justify-content-end">';
            //'<span class="product-img d-block mb-2 mx-auto rounded" style="cursor: pointer;" onclick="OnItemClickShowPopup(' + item.id + ',' + item.HID + ');" data-toggle="modal" data-target="#itemDetailModal">' +
        str += '<span class="product-img d-block mb-2 mx-auto rounded position-relative">' +
            (($('#hdnIsShowAllergen').val() == "1") ? bindAllergensHtml(allergenList) : '') +
        '<img src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="' + item.IMAGENAME + '">' +
            '</span>';

        if ($('#hdnIsCartVisible').val() == '1') {
            str +=
                '<div class="d-flex item-select-block">' +
                '<a href="#" class="btn btn-primary icon-btn divAddMinuseItembtn" onclick="MinusecardclickNew(0,' + item.id + ',' + item.HID + ',0);">' +
                '<i class="fa fa-minus" aria-hidden="true"></i>' +
                '</a>' +
                '<input id="lblItemInfoQty" disabled class="form-control divAddMinuseItembtn" type="text" name="" value="' + selectedItemQty + '">' +
                ' <a href="#" onclick="addItemclickNew(0,' + item.id + ',' + item.HID + ',0);" class="btn btn-primary icon-btn divAddMinuseItembtn">' +
                '<i class="fa fa-plus" aria-hidden="true"></i>' +
                '</a>' +
                '</div>';

            //'<a href="#" onclick="addItemclick(0,' + item.id + ',' + item.HID + ',0);" class="btn-primary d-flex item-select-block divAddtocartButton" style="display:none;padding:10px;margin-left:10px;">' +
            //    '<i class="fa fa-shopping-cart" aria-hidden="true" style="margin-right: 7px;"></i>Add' +
            //    '</a>';
        }
        str += '</div></div>' +
            '</div>' +
            '</div>';

        Mainstr = Mainstr + str;

        //var Scrollstr = "";

        //Scrollstr = '<div class="item" id="ScrollItem_' + item.id + '" data-val="' + item.CAT_NUM + '" onclick="OnItemClick(' + item.id + ',' + item.HID + ');">' +
        //    '<a href="#" class="card-primary ml-1 mr-1">' +
        //    '<img class="card-img-top img-responsive" src="../../ThumbnailImages/' + item.IMAGENAME + '" alt="">' +
        //    '<div class="card-body">' +
        //    '<h3>' + ItemName + '</h3>' +
        //    '</div>' +
        //    '</a>' +
        //    '</div>';
        //ScrollItemsstr = ScrollItemsstr + Scrollstr;

    });
    $('#SubCatOrItemData_' + cat_num + '').html(Mainstr);
    //$('#divScrollItemList').html(ScrollItemsstr);
    debugger;
    var isrtl = false;
    if ($('#selectedLang').val() == "EN") {
        isrtl = false
    }
    else {
        isrtl = true
    }

    var carousel = jQuery(".owl-carousel");
    carousel.trigger('destroy.owl.carousel');
    carousel.find('.owl-stage-outer').children().unwrap();
    carousel.removeClass("owl-center owl-loaded owl-text-select-on");
    carousel.html(ScrollItemsstr);
    carousel.owlCarousel({
        //loop: true,
        margin: 10,
        dots: false,
        //autoplay: true,
        rtl: isrtl,
        responsive: {
            0: {
                items: 3
            },
            420: {
                items: 4
            },
            575: {
                items: 5
            },
            768: {
                items: 6
            },
            992: {
                items: 4
            },
        }

    });




    if (selectedItemid > 0) {
        OnItemClick(selectedItemid, selectedHID);

        //$('#divCategoryList').hide()
        //$('#divMainItemList').hide();
        //$('#divMainItemDetails').show()
    }
    if ($('#hdnisCartSelected').val() == "1") {
        $('#divMainItemList').hide();
        $('#divCategoryList').hide();
        $('#divMainItemDetails').hide();
        $('#divMainItemDetails').hide();
        $('#divCartView').show();
        //$('.banner').height(0);
        if ($('.banner').hasClass('d-block')) {
            $('.banner').removeClass('d-block').addClass('d-none');
        }
    }
}

function OnCategoryClick(cat_num, IsHaveSubCategory) {
    debugger;
    //$('#divMainCategoryNameandBackToSection').hide();
    selectedCategoryId = cat_num;
    if (isbackcounter < 2) {
        isbackcounter++;
    }
    if ($('#hdnIsSubCategoryProject').val() == "true" && IsHaveSubCategory == 1) {
        selectedMainCategoryId = cat_num;
        $('#divBranchName').html($('#Cat_' + cat_num).attr("data-val"));
        BindCategory(selectedCategoryId);

        if ($("#hdnDesignName").val() == "Design2") {
            $('#divBranchnameandBackToSection').show();
        }
        //$('#divMainCategoryNameandBackToSection').show();
    }
    else {
        //$('.banner').height(0);
        if ($('.banner').hasClass('d-block')) {
            $('.banner').removeClass('d-block').addClass('d-none');
        }
        $('#divCatename').html($('#Cat_' + cat_num).attr("data-val"));
        $('#divMainItemList').show();
        $('#divCategoryList').hide()
        $('#itemlist').html("");
        //var obji = { Cat_Num : cat_num, BrandId: $('#hdnbrandId').val(),Branchid: $('#hdnBranchId').val()}
        $.ajax({
            type: "Post",
            //data: obji,
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/ItemsView/GetItemList?Cat_Num=" + cat_num + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
            //url: "/ItemsView/GetItemList",
            success: function (result) {
                if (result.Message == "Success") {
                    var Items = result.dtItems;
                    var ItemsAllergenList = result.dtItemsAllergenList;
                    ItemAllergenslst = result.dtItemsAllergenList;
                    if ($("#hdnIsFromWaiterLogin").val() == "true") {
                        BindSelectedCategoryItemsForWaiter(Items, ItemsAllergenList);
                    }
                    else {
                        BindSelectedCategoryItems(Items, ItemsAllergenList);
                    }
                }
            }
        });
    }
}

function OnMainCategoryClickDesign1(cat_num, IsHaveSubCategory) {
    debugger;
    $('.mainCategory').each(function (index, value) {
        $(this).removeClass("active-item");
    })
    $('#ScrollCategory_' + cat_num).addClass("active-item");

    //$('#divMainCategoryNameandBackToSection').hide();
    selectedCategoryId = cat_num;
    //if (IsHaveSubCategory == 1) {
    selectedMainCategoryId = cat_num;
    BindSubCategoryDesign1(selectedCategoryId);
    //}
    //else {
    //    if (isbackcounter < 2) {
    //        isbackcounter++;
    //    }
    //    isLoadervisible = 0;
    //    $.ajax({
    //        type: "Post",
    //        //data: obji,
    //        contentType: "application/json; charset=utf-8",
    //        dataType: "json",
    //        cache: false,
    //        url: "/ItemsView/GetItemList?Cat_Num=" + cat_num + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
    //        //url: "/ItemsView/GetItemList",
    //        success: function (result) {
    //            isLoadervisible = 1;
    //            if (result.Message == "Success") {
    //                var Items = result.dtItems;
    //                var ItemsAllergenList = result.dtItemsAllergenList;
    //                BindSelectedCategoryItemsDesign1(Items, cat_num, ItemsAllergenList);
    //            }
    //        }
    //    });
    //}
}
function OnSubCategoryClickDesign1(cat_num, IsHaveSubCategory) {
    debugger;
    //$('#divMainCategoryNameandBackToSection').hide();
    selectedCategoryId = cat_num;
    ////if (IsHaveSubCategory == 1) {
    //selectedMainCategoryId = cat_num;
    //BindSubCategoryDesign1(selectedCategoryId);
    ////}
    //else {
    //if (isbackcounter < 2) {
    //    isbackcounter++;
    //}
    isLoadervisible = 0;
    $.ajax({
        type: "Post",
        //data: obji,
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetItemList?Cat_Num=" + cat_num + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
        //url: "/ItemsView/GetItemList",
        success: function (result) {
            isLoadervisible = 1;
            if (result.Message == "Success") {
                var Items = result.dtItems;
                var ItemsAllergenList = result.dtItemsAllergenList;
                // Design2/3's equivalent handler (OnCategoryClick, above) also updates this
                // global - without it, OnItemClickShowPopup()'s allergen filter on click always
                // sees a stale/empty list, so the Item Details popup's icon never shows for
                // Design1/waiter items even though the per-item card icon renders fine.
                ItemAllergenslst = ItemsAllergenList;

                if ($("#hdnIsFromWaiterLogin").val() == "true") {
                    BindSelectedCategoryItemsDesignForWaiter(Items, cat_num, ItemsAllergenList);
                }
                else {
                    BindSelectedCategoryItemsDesign1(Items, cat_num, ItemsAllergenList);
                }
            }
        }
    });
    //}
}
function OnCategoryClickDesign4(cat_num, IsHaveSubCategory) {
    debugger;
    //$('#divMainCategoryNameandBackToSection').hide();
    selectedCategoryId = cat_num;
    if (IsHaveSubCategory == 1) {
        selectedMainCategoryId = cat_num;
        BindSubCategory(selectedCategoryId)
    }
    else {
        if (isbackcounter < 2) {
            isbackcounter++;
        }
        isLoadervisible = 0;
        $.ajax({
            type: "Post",
            //data: obji,
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/ItemsView/GetItemList?Cat_Num=" + cat_num + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
            //url: "/ItemsView/GetItemList",
            success: function (result) {
                isLoadervisible = 1;
                if (result.Message == "Success") {
                    var Items = result.dtItems;
                    var ItemsAllergenList = result.dtItemsAllergenList;
                    // Same reason as OnSubCategoryClickDesign1 above - keep the global in sync
                    // so the Item Details popup's allergen icon works after a Design4 click too.
                    ItemAllergenslst = ItemsAllergenList;
                    BindSelectedCategoryItemsDesign4(Items, cat_num, ItemsAllergenList);
                }
            }
        });
    }

}
function OnItemClick(itemid, HID) {
    debugger;

    selectedItemid = itemid;
    selectedHID = HID;
    $('#divCategoryList').hide();
    $('#divMainItemList').hide();
    $('#divMainItemDetails').show();
    $('#commentsItemDetailsView').val("");

    $('#hdnSelectedItemid').val(itemid);
    $('#hdnSelectedHID').val(HID);
    var itemUniqueId = 0;
    $.each(CartDetails, function (i, obj) {
        itemUniqueId = itemUniqueId < parseInt(obj.UID) ? parseInt(obj.UID) : itemUniqueId;
    })
    $('#hdnSelectedUID').val(itemUniqueId + 1);

    //$('#divItemDetailsViewTopItemName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());

    $('#divitemDetailsItemName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    //$('#divitemDetailsItemName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    debugger;
    if ($('#hdnItem_VideoNAME_' + itemid).val().trim() != "") {
        $('#itemDetailsItemImage').removeClass("d-block");
        $('#itemDetailsItemImage').hide();
        $('#itemDetailsItemVideo').show();
        if (typeof hideItemImageSlider === 'function') { hideItemImageSlider(); }
        $('#itemVideoImage').attr("poster", "../../images/" + $('#hdnItem_IMAGENAME_' + itemid).val().trim() + "");
        $('#itemVideo').attr("src", "../Video/" + $('#hdnItem_VideoNAME_' + itemid).val().trim() + "");
        $("#itemVideoImage")[0].load();
        $('#itemVideoImage').trigger('pause');
    }
    else {
        $('#itemDetailsItemVideo').hide();
        $('#itemDetailsItemImage').show();
        $('#itemDetailsItemImage').css("display", "block !important;");
        $('#itemDetailsItemImage').attr("src", "../../images/" + $('#hdnItem_IMAGENAME_' + itemid).val().trim() + "");
        if (typeof loadItemImageSlider === 'function') { loadItemImageSlider(itemid, $('#hdnItem_IMAGENAME_' + itemid).val().trim()); }
    }
    $('#divitemDetailsIngredient').html($('#hdnItemINGREDIENT_' + itemid).val().trim());
    $('#itemdetMaindivPrice').html(round($('#hdnItem_PRICE_' + itemid).val().trim(), decimalPlace).toFixed(decimalPlace));
    $('#divitemDetailsPriceCurrcode').html(selectedCurrency + '. ');
    $('#divitemDetailsPrice').html(round($('#hdnItem_PRICE_' + itemid).val().trim(), decimalPlace).toFixed(decimalPlace));
    $('#divitemDetailsTotalPrice').html(round(0, decimalPlace).toFixed(decimalPlace));
    $('#txtItemDetailsItemCartCount').html("0");
    $('#divExtraitemDetailsPrice').html(round(0, decimalPlace).toFixed(decimalPlace));
    $('#lblItemDetailsUnitPriceCurr').html(selectedCurrency + '. ');
    $('#lblItemDetailsExtraPriceCurr').html(selectedCurrency + '. ');
    $('#lblItemDetailsTotalPriceCurr').html(selectedCurrency + '. ');

    var selectedItemQty = 0;
    //commented on 3-jan-23, Item details view qty display existing(cart items) count
    //if (CartDetails.length > 0) {
    //    var tempCartDetails = CartDetails;
    //    $.each(tempCartDetails, function (i, obj) {
    //        if (obj.I == itemid) {
    //            selectedItemQty = obj.Q;
    //        }
    //    });
    //}
    if ($('#hdnIsCartVisible').val() == "1") {
        var strbutton = '';
        strbutton += '<a href="#" class="btn btn-primary icon-btn divAddMinuseItembtn" onclick="MinusecardclickNew(0,' + itemid + ',' + HID + ',0);">' +
            '<i class="fa fa-minus" aria-hidden="true"></i>' +
            '</a>' +
            '<input id="lblItemInfoQty" disabled class="form-control divAddMinuseItembtn" type="text" name="" value="' + selectedItemQty + '">' +
            ' <a href="#" onclick="addItemclickNew(0,' + itemid + ',' + HID + ',0);" class="btn btn-primary icon-btn divAddMinuseItembtn">' +
            '<i class="fa fa-plus" aria-hidden="true"></i>' +
            '</a>';

        strbutton += '<a href="#" onclick="addItemclick(0,' + itemid + ',' + HID + ',0);" class="btn-primary d-flex item-select-block divAddtocartButton" style="display:none;padding:10px;margin-left:10px;margin-right:10px;">' +
            '<i class="fa fa-shopping-cart" aria-hidden="true" style="margin-right: 7px;margin-left: 7px;"></i>Add' +
            '</a>';

        $('#btnDetailsViewAdditemContainer').html(strbutton);
    }

    debugger;
    BindItemExtraItemsAndCommentsAndChoice(itemid);
    UpdateItemDetailsPrices(itemid, $('#hdnSelectedUID').val());
    $('#itemVideoImage').trigger('pause');
    if ($('#hdnIsCartVisible').val() == '1') {
        //$('#divItemDetailsViewPriceInfo').show();
        $('#divItemDetailsViewPriceInfo').css("display", "block !important;");
    }
    else {
        //$('#divItemDetailsViewPriceInfo').hide();
        $('#divItemDetailsViewPriceInfo').css("display", "none !important;");
    }

    //Bind Allergens
    // filter item wise allergen List
    debugger;
    if ($('#hdnIsShowAllergen').val() == "1") {
        allergenList = ItemAllergenslst.filter(function (entry) {
            return entry.itemId === itemid;
        });
        var strAllergens = "";
        $.each(allergenList, function (i, allergen) {
            var allergenName = "";
            if ($('#selectedLang').val() == "EN") {
                allergenName = allergen.allergenName;
            }
            else {
                allergenName = allergen.allergenNameArabic;
            }

            strAllergens += '<li class="media">' +
                '<span class="media-img mr-2">' +
                '<img src="../../allergenImages/' + allergen.image + '" height="20px" width="20px" alt="" onerror="this.style.display=\'none\'">' +
                '</span>' +
                '<div class="media-body">' + allergenName + '</div>' +
                '</li>';
            //'<svg height="512" viewBox="0 0 64 64" width="512" xmlns="http://www.w3.org/2000/svg"><g id="Soy"><path d="m63.31 27.35c-.36 4.68-2.45 9.14-9.19 12.43-2.77 8.13-9.12 12.95-17.13 12.95h-.01a20.24475 20.24475 0 0 1 -2.88-.21 19.90642 19.90642 0 0 1 -11.54 3.65 26.01508 26.01508 0 0 1 -13.59-4.24 14.24985 14.24985 0 0 0 9.19 7.75 17.96243 17.96243 0 0 0 5.16.76 16.96735 16.96735 0 0 0 12.05-4.82 18.8959 18.8959 0 0 0 14.5-2.8 14.55588 14.55588 0 0 0 6.03-9.56c3.86-1.55 6.37-4.02 7.46-7.35a15.19227 15.19227 0 0 0 -.05-8.56z" /><path d="m48.90234 33.38672c1.80274-.24707 4.68067-2.83692 4.98243-4.93555a1.9324 1.9324 0 0 0 -1.418-2.10156 2.20727 2.20727 0 0 0 -.666-.10352 2.06113 2.06113 0 0 0 -1.88277 1.29791 4.76922 4.76922 0 0 1 -1.97363 1.94238 1.92221 1.92221 0 0 0 -1.21582 2.37988 2.078 2.078 0 0 0 2.17379 1.52046z" /><path d="m33.59961 50.41113c8.83594 1.61719 16.1709-3.07617 18.88281-12.07422 8.95507-4.02539 9.28906-9.85644 8.751-15.52343l2.02734-5.166a2.213 2.213 0 0 0 -1.4414-2.92773l-.65336-.19045a2.78768 2.78768 0 0 0 -3.1211 1.13281l-2.8623 4.2666c-8.23828 1.24317-13.24121 5.09961-14.88379 11.4707-6.3584-.43457-10.98389 2.2334-12.65528 7.26172-8.99365-1.82324-14.71386.86719-19.58691 9.124a1 1 0 0 0 .28369 1.32422c4.76465 3.37207 9.62158 5.06445 14.21582 5.06445a18.09944 18.09944 0 0 0 11.04348-3.76267zm13.46-22.71777a2.81892 2.81892 0 0 0 1.0791-1.0625 4.047 4.047 0 0 1 4.94429-2.18359 3.9307 3.9307 0 0 1 2.78028 4.30173c-.44433 3.082-4.11914 6.27539-6.70215 6.6211l-.01465.002a3.91205 3.91205 0 0 1 -.46386.02734 4.075 4.075 0 0 1 -3.8711-2.96191 3.93007 3.93007 0 0 1 2.24805-4.74417zm-11.749 9.86133a3.17818 3.17818 0 0 0 1.47851-.8418 4.27568 4.27568 0 0 1 5.70508-.88965 4.195 4.195 0 0 1 1.68164 5.2002c-1.23144 2.87207-5.4043 5.06347-8.22265 5.06347a4.82191 4.82191 0 0 1 -.6045-.03613l-.01562-.00293a4.32772 4.32772 0 0 1 -3.65479-4.22265 4.19806 4.19806 0 0 1 3.63227-4.27051zm-18.30524 11.88281-.01123-.00879a4.2037 4.2037 0 0 1 -1.0498-5.32519 4.13693 4.13693 0 0 1 5.20366-1.86817 3.11918 3.11918 0 0 0 1.65185.00781 4.251 4.251 0 0 1 5.30074 2.04784 4.07813 4.07813 0 0 1 -1.148 5.19628 8.27458 8.27458 0 0 1 -4.832 1.334 8.95389 8.95389 0 0 1 -5.11522-1.38378z" /><path d="m23.41357 44.14648a5.11605 5.11605 0 0 1 -2.89794-.01367 2.17051 2.17051 0 0 0 -2.8086.916 2.21734 2.21734 0 0 0 .51221 2.7998c1.55713 1.17188 5.72021 1.38379 7.55224.02442a2.07906 2.07906 0 0 0 .54444-2.67871 2.22912 2.22912 0 0 0 -2.90235-1.04784z" /><path d="m35.6123 44.06738c1.99415.248 5.80665-1.69043 6.73047-3.84375a2.19727 2.19727 0 0 0 -.93652-2.72265 2.302 2.302 0 0 0 -3.13281.55175 5.17911 5.17911 0 0 1 -2.56739 1.4629 2.18074 2.18074 0 0 0 -2.02832 2.2539 2.34118 2.34118 0 0 0 1.93457 2.29785z" /><path d="m22.68 36.12a24.433 24.433 0 0 1 3.72.29c2.17-4.47 6.6-7.02 12.44-7.06 1.62-4.5 5.61-9.56 15.16-11.25l2.2-3.28c-.03-.78-.09-1.57-.16-2.34l2.22-5.66a2.15624 2.15624 0 0 0 -1.4-2.86l-.99-.29a2.695 2.695 0 0 0 -3.03 1.1l-3.15 4.7c-8.81 1.32-14.14 5.44-15.87 12.26-6.8-.49-11.75 2.36-13.52 7.75-8.93-1.82-14.88.57-19.76 7.9a3.10179 3.10179 0 0 0 .93 4.3 30.27111 30.27111 0 0 0 6.21 2.98c4.02-5.82 8.84-8.54 15-8.54zm-13.14924-.84266c-2.54443.73731-4.15185 3.60743-4.168 3.63575a.9996.9996 0 1 1 -1.751-.96485c.2041-.37011 2.08789-3.64355 5.3623-4.59277a1.00043 1.00043 0 0 1 .55664 1.92187z" /></g></svg>' +
        });

        $('#ulItemsAllergensList').html(strAllergens);

        if (allergenList.length > 0) {
            $('#divItemDetailsAllergen').show();
        }
        else {
            $('#divItemDetailsAllergen').hide();
        }
    }

    if (($('#hdnDesignName').val() == "Design1")) {
        $('#divCategoryList').show();
        $('#divMainItemList').hide();
    }
}


function BindItemExtraItemsAndCommentsAndChoice(itemid) {
    //var obji = { itemid: itemid}
    //$('#divExtraItems').html("");
    //$('#divmainExtraItems').hide();
    $('#divExtraComments').html("");
    $('#divmainExtraComments').hide();

    $.ajax({
        type: "Post",
        //data: obji,
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        //url: "/ItemsView/BindItemExtraItemsAndComments?itemid=" + itemid,
        url: "/ItemsView/BindItemExtraItemsAndComments?itemid=" + itemid + "&Branchid=" + $('#hdnBranchId').val(),

        success: function (result) {
            if (result.Message == "Success") {
                debugger;
                //var choices = JSON.parse(result.dtChoices);
                //var items = JSON.parse(result.dtItems);
                var items = JSON.parse(result.dtchoicesAndExtraItems);
                var extraComments = JSON.parse(result.dtExtraComments);



                var ExtraItemsGroups = [];
                var strExtraItemsGrouplist = '';
                for (i = 0; i < items.length; i++) {

                    var index = ExtraItemsGroups.findIndex(function (itm, j) {
                        return itm.GroupId === items[i].GroupId
                    });

                    if (index === -1) {
                        var obj = {}
                        obj["GroupId"] = items[i].GroupId;
                        obj["groupnameEng"] = items[i].groupnameEng;
                        obj["groupnamearb"] = items[i].groupnamearb;
                        obj["MinSelect"] = items[i].MinSelect;
                        obj["maxselect"] = items[i].maxselect;
                        ExtraItemsGroups.push(obj);

                        var groupname = '';
                        if ($('#selectedLang').val() == "EN") {
                            groupname = items[i].groupnameEng;
                        }
                        else {
                            groupname = items[i].groupnamearb;
                        }

                        if (items[i].ModifierType == 1 && $('#hdnIsChoiceBind').val() == "true") {// if Choices then
                            strExtraItemsGrouplist += '<div class="card extra-item-block comments-item-block mb-4 clsChoiceItemsGrp" id="divChoiceItemGroup_' + items[i].GroupId + '">' +
                                '<input type="hidden" id="hdnchGroupMinSelect_' + items[i].GroupId + '" value="' + items[i].MinSelect + '"/>' +
                                '<input type="hidden" id="hdnchGroupMaxselect_' + items[i].GroupId + '" value="' + items[i].maxselect + '"/>' +
                                '<input type="hidden" class="clsGroupSelectd" id="hdnchGroupSelectd_' + items[i].GroupId + '" value="0"/>' +
                                '<h3 class="modal-title" id="lblSelectChoiceItemsGrp_' + items[i].GroupId + '">' + groupname + '</h3>' +
                                '<ul class="extra-option-list" id="divItemChoices_' + items[i].GroupId + '" ></ul>' +
                                '</div>';
                        }
                        else if (items[i].ModifierType == 2 && $('#hdnIsExtraItemsBind').val() == "true") {
                            strExtraItemsGrouplist += '<div class="card extra-item-block comments-item-block mb-4 clsExtraItemsGrp" id="divExtraItemGroup_' + items[i].GroupId + '">' +
                                '<input type="hidden" id="hdnGroupMinSelect_' + items[i].GroupId + '" value="' + items[i].MinSelect + '"/>' +
                                '<input type="hidden" id="hdnGroupMaxselect_' + items[i].GroupId + '" value="' + items[i].maxselect + '"/>' +
                                '<input type="hidden" class="clsGroupSelectd" id="hdnGroupSelectd_' + items[i].GroupId + '" value="0"/>' +
                                '<h3 class="modal-title" id="lblSelectExtraItemsGrp_' + items[i].GroupId + '">' + groupname + '</h3>' +
                                '<ul class="extra-option-list" id="divExtraItems_' + items[i].GroupId + '" ></ul>' +
                                '</div>';
                        }

                    }
                }
                /*$('#extraitemsGroupMainDiv').html(strExtraItemsGrouplist);*/
                $('#choiceAndExtraitemsGroupMainDiv').html(strExtraItemsGrouplist);


                //debugger;
                //var ChoicesGroups = [];
                //var strChoicesItemsGrouplist = '';
                //for (i = 0; i < choices.length; i++) {

                //    var index = ChoicesGroups.findIndex(function (itm, j) {
                //        return itm.GroupId === choices[i].GroupId
                //    });

                //    if (index === -1) {
                //        var obj = {}
                //        obj["GroupId"] = choices[i].GroupId;
                //        obj["groupnameEng"] = choices[i].groupnameEng;
                //        obj["groupnamearb"] = choices[i].groupnamearb;
                //        obj["MinSelect"] = choices[i].MinSelect;
                //        obj["maxselect"] = choices[i].maxselect;
                //        ChoicesGroups.push(obj);

                //        var groupname = '';
                //        if ($('#selectedLang').val() == "EN") {
                //            groupname = choices[i].groupnameEng;
                //        }
                //        else {
                //            groupname = choices[i].groupnamearb;
                //        }


                //        //render html
                //        strChoicesItemsGrouplist += '<div class="card extra-item-block comments-item-block mb-4 clsChoiceItemsGrp" id="divChoiceItemGroup_' + choices[i].GroupId + '">' +
                //            '<input type="hidden" id="hdnchGroupMinSelect_' + choices[i].GroupId + '" value="' + choices[i].MinSelect + '"/>' +
                //            '<input type="hidden" id="hdnchGroupMaxselect_' + choices[i].GroupId + '" value="' + choices[i].maxselect + '"/>' +
                //            '<input type="hidden" class="clsGroupSelectd" id="hdnchGroupSelectd_' + choices[i].GroupId + '" value="0"/>' +
                //            '<h3 class="modal-title" id="lblSelectChoiceItemsGrp_' + choices[i].GroupId + '">' + groupname + '</h3>' +
                //            '<ul class="extra-option-list" id="divItemChoices_' + choices[i].GroupId + '" ></ul>' +
                //            '</div>';
                //    }
                //}
                //$('#choiceitemsGroupMainDiv').html(strChoicesItemsGrouplist);

                //$('#divItemChoices').html("");
                //$('#divExtraItems').html("");
                $('#divExtraComments').html("");
                $('#cartitemsMainDiv').html("");
                debugger;

                if ($('#hdnIsChoiceBind').val() == "true") {
                    choices = items.filter(function (entry) {
                        return entry.ModifierType === 1;
                    });
                    debugger;
                    ItemChoicesDiv(choices, itemid);
                }
                else {
                    /* $('#divmainItemChoices').hide();*/
                    //$('#choiceitemsGroupMainDiv').html("");
                }


                if ($('#hdnIsExtraItemsBind').val() == "true") {
                    extraitems = items.filter(function (entry) {
                        return entry.ModifierType === 2;
                    });
                    debugger;
                    ExtraItemsDiv(extraitems, itemid);
                }
                else {
                    //$('#divmainExtraItems').hide();
                    //$('#extraitemsGroupMainDiv').html("");
                }
                ExtraCommentsDiv(extraComments, itemid);
            }
        }
    });

}

function ItemChoicesDiv(choices, MainItemid) {
    debugger;
    if (choices.length == 0) {
        //$('#divmainItemChoices').hide();
        //$('#divExtraPrice').hide();
        $('#choiceitemsGroupMainDiv').html("");

        //$('.divAddtocartButton').hide();
        //$('.divAddMinuseItembtn').show();
    }
    else {
        //$('.divAddtocartButton').show();
        //$('.divAddMinuseItembtn').hide();
        //$('#divExtraPrice').show();

        //$('#divmainItemChoices').show();
        //$('#choiceitemsGroupMainDiv').show();
    }
    var Mainstr = "";
    $(".clsChoiceItemsDiv").each(function () {
        $(this).html("");
    });
    var groupids = [];
    var cnt = 0;
    var defaultchoiceId = 0;
    var defaultchoicePrice = 0;
    $.each(choices, function (i, choice) {
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            ItemName = choice.ITEM_NAME;
            INGREDIENT = choice.INGREDIENT;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = choice.ITEM_NAME_ARABIC;
            INGREDIENT = choice.INGREDIENT_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }


        var price = "0";
        if (parseFloat(choice.PRICE) > 0) {
            price = round(choice.PRICE, decimalPlace).toFixed(decimalPlace);
        }
        var printprice = "";
        if (price > 0) {
            printprice = price;
        }
        var str = "";
        str = '<li onclick="ItemDetailsChoicesCheckboxclick(this,' + MainItemid + ',' + choice.id + ',' + price + ',' + choice.GroupId + ')">' +
            '<input type="checkbox" id="ItemChoice_' + choice.id + '" value="' + price + '" name="extra-option" class="custom-control-input ItemsChoice clsChoiceItemsDiv_' + choice.GroupId + '">' +
            '<label for="' + ItemName + '" class="item-name">' +
            '<label id="ItemChoiceName_' + choice.id + '" >' + ItemName + '</label>' +
            '<span>' + printprice + '</span>' +
            '</label>' +
            '</li>';
        Mainstr = Mainstr + str;
        $("#divItemChoices_" + choice.GroupId + "").append(str);


        if (groupids.indexOf(choice.GroupId) == -1) {
            groupids.push(choice.GroupId);
        }

        if (cnt == 0) {
            defaultchoiceId = choice.id;
            defaultchoicePrice = price;
        }
        cnt++;
    });
    $('#divItemChoices').html(Mainstr);

    $('#MainDivitemdetPrice').show();
    //set group wise selected choice items
    //$.each(groupids, function (i, obj) {
    //    setSelectedItemsChoice(MainItemid, obj);
    //});

    //Check if not any choice selected then set default 
    //var isselected = 0;
    //$(".ItemsChoice").each(function (index) {
    //    if ($(this).prop("checked") == true) {
    //        isselected = 1;
    //    }
    //});

    //debugger
    //if (defaultchoiceId > 0 && isselected == 0 && cnt != 0) {
    //    $('#ItemChoice_' + defaultchoiceId + '').prop("checked", true);
    //    var itemOriginalprice = parseFloat($('#hdnItem_PRICE_' + MainItemid).val().trim());
    //    //var itemOriginalprice = parseFloat($('#divitemDetailsPrice').html());
    //    $('#divitemDetailsPrice').html((itemOriginalprice + parseFloat(defaultchoicePrice)).toFixed(3));
    //    $('#MainDivitemdetPrice').show();
    //}
    //else {
    //    $('#MainDivitemdetPrice').hide();
    //}

    //UpdateItemDetailsPrices(MainItemid);
}
function setSelectedItemsChoice(MainItemid, GroupId, UID) {
    debugger;
    var tempCartDetails = CartDetails;
    var hdnchGroupSelectd = parseInt($('#hdnchGroupSelectd_' + GroupId + '').val());
    $.each(tempCartDetails, function (i, obj) {
        if (obj.UID == UID && obj.I == MainItemid && obj.CH > 0 && obj.GroupId == GroupId) {
            //&& obj.ExtraItemId == ExtraItemId
            $('#ItemChoice_' + obj.CH + '').prop("checked", true);
            var price = $('#ItemChoice_' + obj.CH + '').val();
            //$('#divitemDetailsPrice').html(parseFloat(price).toFixed(3));
            var itemOriginalprice = parseFloat($('#hdnItem_PRICE_' + MainItemid).val().trim());
            $('#divitemDetailsPrice').html(round((itemOriginalprice + parseFloat(price)), decimalPlace).toFixed(decimalPlace));
            $('#MainDivitemdetPrice').show();

            hdnchGroupSelectd++
            $('#hdnchGroupSelectd_' + GroupId + '').val(hdnchGroupSelectd);
        }

        //if (obj.CH == 0) {
        //    $('#MainDivitemdetPrice').hide();
        //}
    });
}


function ExtraItemsDiv(Items, MainItemid) {
    debugger;
    if (Items.length == 0) {
        //$('#divmainExtraItems').hide();
        $('#divExtraPrice').hide();
        $('#extraitemsGroupMainDiv').html("");
    }
    else {
        //$('#divmainExtraItems').show();
        $('#divExtraPrice').show();
    }
    var Mainstr = "";
    $(".clsExtraItemsDiv").each(function () {
        $(this).html("");
    });
    var groupids = [];
    $.each(Items, function (i, item) {
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }
        var itemPrice = round(item.PRICE, decimalPlace).toFixed(decimalPlace);
        var str = "";
        str = '<li onclick="ItemDetailsExtraItemsCheckboxclick(this,' + MainItemid + ',' + item.id + ',' + itemPrice + ',' + item.GroupId + ')">' +
            '<input type="checkbox" id="extraItem_' + item.id + '" value="' + itemPrice + '" name="extra-option" class="custom-control-input extraItems clsExtraItemsDiv_' + item.GroupId + '">' +
            '<label for="' + ItemName + '" class="item-name">' +
            '<label id="extraItemName_' + item.id + '" >' + ItemName + '</label>' +
            '<span>+' + itemPrice + '</span>' +
            '</label>' +
            '</li>';
        Mainstr = Mainstr + str;
        $("#divExtraItems_" + item.GroupId + "").append(str);


        if (groupids.indexOf(item.GroupId) == -1) {
            groupids.push(item.GroupId);
        }

    });


    //set group wise selected extra items
    //$.each(groupids, function (i, obj) {
    //    setSelectedExtraItems(MainItemid, obj);
    //});

}

function setSelectedExtraItems(MainItemid, GroupId) {
    debugger;
    var tempCartExtraItems = CartExtraItems;
    var hdnGroupSelectd = parseInt($('#hdnGroupSelectd_' + GroupId + '').val());
    $.each(tempCartExtraItems, function (i, obj) {
        if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemid && obj.GroupId == GroupId) {
            //&& obj.ExtraItemId == ExtraItemId
            $('#extraItem_' + obj.ExtraItemId + '').prop("checked", true);
            hdnGroupSelectd++
            $('#hdnGroupSelectd_' + GroupId + '').val(hdnGroupSelectd);
        }
    });
}

function ExtraCommentsDiv(extraComments, MainItemId) {
    if (extraComments.length == 0) {
        $('#divmainExtraComments').hide();
    }
    else {
        $('#divmainExtraComments').show();
    }
    var Mainstr = "";
    $.each(extraComments, function (i, data) {
        var CommentName = "";
        if ($('#selectedLang').val() == "EN") {
            CommentName = data.comments_eng;
            selectedCurrency = $('#hdnCurrencyENG').val();
        }
        else {
            CommentName = data.comments_arb;
            selectedCurrency = $('#hdnCurrencyArab').val();
        }

        var str = "";
        str = '<li onclick="ItemDetailsCommentsCheckboxclick(this,' + MainItemId + ',' + data.id + ')">' +
            '<input type="checkbox" id="extraComment_' + data.id + '_' + MainItemId + '" name="extra-option" class="custom-control-input extraComment">' +
            '<label for="' + CommentName + '" class="item-name">' +
            '<span id="extraCommentName_' + data.id + '_' + MainItemId + '">' + CommentName + '</span>' +
            '</label>' +
            '</li>';
        Mainstr = Mainstr + str;
    });
    $('#divExtraComments').html(Mainstr);

    setSelectedExtraComments(MainItemId);
}

function setSelectedExtraComments(MainItemid) {
    var tempCartComments = CartComments;
    $.each(tempCartComments, function (i, obj) {
        if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemid) {
            //&& obj.ExtraItemId == ExtraItemId
            $('#extraComment_' + obj.CommentId + '_' + MainItemid + '').prop("checked", true);
        }
    });
}

function UpdateItemDetailsPrices(itemid, UID) {
    debugger;
    var unitprice = + round($('#divitemDetailsPrice').html(), decimalPlace).toFixed(decimalPlace);
    var selectedQty = $('#lblItemInfoQty').val() != undefined ? parseInt($('#lblItemInfoQty').val()) : 0.000;
    if (selectedQty == 0) {
        selectedQty = parseInt($('#divItemwiseCount_' + UID + '').html());
    }
    var ExtraItemsTotal = 0.000;
    if (selectedQty > 0) {
        $(".extraItems").each(function (index) {
            if ($(this).prop("checked") == true) {
                ExtraItemsTotal = ExtraItemsTotal + parseFloat($(this).val());
            }
            //console.log(index + ": " + $(this).text());
        });
    }


    //var tempCartExtraItems = CartExtraItems;
    //$.each(tempCartExtraItems, function (i, obj) {
    //    if (obj.UID == parseInt(UID) && obj.MainItemId == itemid) {
    //        ExtraItemsTotal = parseFloat(ExtraItemsTotal) + (parseInt(selectedQty) * parseFloat(obj.Price));
    //    }
    //});
    debugger;

    $('#divExtraitemDetailsPrice').html(round(parseFloat(ExtraItemsTotal) ? parseFloat(ExtraItemsTotal) : (0.000), decimalPlace).toFixed(decimalPlace));
    ExtraItemsTotal = parseFloat(ExtraItemsTotal) ? (ExtraItemsTotal * selectedQty) : (0.000);
    var ItemDetailsTotal = (unitprice * selectedQty) + ExtraItemsTotal;
    $('#divitemDetailsTotalPrice').html(round(parseFloat(ItemDetailsTotal) ? parseFloat(ItemDetailsTotal) : (0.000), decimalPlace).toFixed(decimalPlace));

}
function cartConfirmRemvoeChoiceItem(obj, MainItemId, ChoiceItemId, UID) {
    var tempCartChoicesItems = CartChoicesItems;
    $.each(tempCartChoicesItems, function (i, obj) {
        if (obj.UID == parseInt(UID) && obj.MainItemId == MainItemId && obj.ChoiceItemId == ChoiceItemId) {
            tempCartChoicesItems = jQuery.grep(tempCartChoicesItems, function (value) {
                return value != obj;
            });
        }
    });

    $(obj).parent().remove();
    OnAddMinusUpdateAmounts(tempCartChoicesItems, UID);

    var val = JSON.stringify(tempCartChoicesItems);
    createCookie("ChoiceItemsCookie", val, 365);
    CartChoicesItems = tempCartChoicesItems;

}

function cartConfirmRemvoeExtraItem(obj, MainItemId, ExtraItemId, UID) {
    var tempCartExtraItems = CartExtraItems;
    $.each(tempCartExtraItems, function (i, obj) {
        if (obj.UID == UID && obj.MainItemId == MainItemId && obj.ExtraItemId == ExtraItemId) {
            tempCartExtraItems = jQuery.grep(tempCartExtraItems, function (value) {
                return value != obj;
            });
        }
    });

    $(obj).parent().remove();
    OnAddMinusUpdateAmounts(tempCartExtraItems, UID);

    var val = JSON.stringify(tempCartExtraItems);
    createCookie("ExtraItemsCookie", val, 365);
    CartExtraItems = tempCartExtraItems;

}

function cartConfirmRemvoeComment(obj, CommentId, MainItemId) {
    var tempCartComments = CartComments;
    $.each(tempCartComments, function (i, obj) {
        if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemId && obj.CommentId == CommentId) {
            tempCartComments = jQuery.grep(tempCartComments, function (value) {
                return value != obj;
            });
        }
    });

    var val = JSON.stringify(tempCartComments);
    createCookie("CommentCookie", val, 365);

    CartComments = tempCartComments;

    $(obj).parent().remove();
}

function clearCart() {
    $.confirm({
        title: 'Confirm',
        content: 'Are you sure you want to remove?',
        icon: 'fa fa-question',
        closeAnimation: 'scale',
        opacity: 0.2,
        theme: 'bootstrap',
        closeIcon: true,
        animation: 'scale',
        type: 'orange',
        buttons: {
            'confirm': {
                text: 'Yes',
                btnClass: 'btn-orange',
                action: function () {
                    ClearcartData();
                },
                Cancel: function () {
                    //retval=false;
                },
            }
        }
    });
}
function ClearcartData() {
    CartDetails = [];
    CartComments = [];
    CartExtraItems = [];
    CartChoicesItems = [];
    $('#cartitemsMainDiv').html("");

    // BindCartCount([]) rather than UpdateCartCountSpan() on its own.
    // UpdateCartCountSpan only decides whether to SHOW the badge, by reading the
    // number already printed in it - so after a clear it read the old count,
    // decided it was not "0", and left the basket badge on screen showing the
    // order that had just been placed.
    BindCartCount([]);

    //Commented on 18-Dec-22 Reason is Waiter login cookies also removed. It should not.
    //document.cookie.split(";").forEach(function (c) { document.cookie = c.replace(/^ +/, "").replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/"); });

    // Every basket cookie, erased on the current path AND on every ancestor
    // path. They used to be written with no path attribute, which binds them to
    // the directory of the page that set them - and the menu runs on several
    // such URLs (brand code and language are path segments). That left more
    // than one cookie called OrderCookie: the delete removed the one it could
    // see and checkCookie() below then read a survivor straight back in, which
    // is why a basket reappeared after an order was placed.
    //
    // eraseCookie is unconditional - the old code only deleted a cookie when
    // accessCookie() could see it, and accessCookie() only ever sees the first
    // copy.
    var cartCookies = [
        'OrderCookie',        // the basket itself
        'CommentCookie',      // per-line comments
        'ExtraItemsCookie',   // extras chosen against a line
        'ChoiceItemsCookie',  // choices chosen against a line
        'TpayOrderConfirm',   // legacy Tap/goSell handoff
        'TpayOrderResponse'
    ];
    for (var ci = 0; ci < cartCookies.length; ci++) {
        eraseCookie(cartCookies[ci]);
    }

    checkCookie();

    // checkCookie() repopulates from whatever cookies remain. If anything
    // survived - a copy on a path this page cannot name, a cookie the browser
    // refused to expire - the basket would silently come back, which is the
    // exact bug this function is meant to prevent. Say so rather than letting
    // it through quietly.
    if (CartDetails && CartDetails.length) {
        if (window.console) {
            console.warn('ClearcartData: basket cookie survived the clear',
                         document.cookie);
        }
        CartDetails = [];
        CartComments = [];
        CartExtraItems = [];
        CartChoicesItems = [];
        BindCartCount([]);
    }

    $('#hdnSubtotal').val("0");
    $('#divSubtotal').text(selectedCurrency + ". " + "0.000");
    if ($('#lblPaymentBillAmountVal').length > 0) {
        $('#lblPaymentBillAmountVal').html("0.000");
        $('#lblPaymentBillAmountCurrency').html(selectedCurrency + ". ");
    }

}

/*=============================================================================
  ClearCheckoutData()

  ClearcartData() empties the basket. It deliberately does NOT touch the
  customer, because it also runs when someone clears their cart mid-session and
  losing their name and address at that point would be maddening.

  After an order is PLACED, though, the whole checkout has to reset - otherwise
  the next customer at the same tablet starts with the previous customer's name,
  mobile and delivery address already filled in. That is a privacy problem as
  much as a usability one, so this is called only on a completed order.

  Everything the checkout remembers lives in three places: the globals, the
  CustomerDetailsCookie, and the form fields themselves. All three are cleared.
=============================================================================*/
function ClearCheckoutData() {
    try {
        // ---- globals -------------------------------------------------------
        if (typeof CustomerDetails    !== 'undefined') CustomerDetails    = {};
        if (typeof Custinfo           !== 'undefined') Custinfo           = {};
        if (typeof AddrInfo           !== 'undefined') AddrInfo           = {};
        if (typeof customerAddresses  !== 'undefined') customerAddresses  = null;
        if (typeof deliveryDate       !== 'undefined') deliveryDate       = null;

        // ---- the one cookie the checkout persists --------------------------
        // Same path problem as the basket cookies: written with no path, so
        // copies can exist per URL depth. eraseCookie clears all of them.
        eraseCookie('CustomerDetailsCookie');

        // ---- customer info step --------------------------------------------
        $('#txtCustomerFullname, #txtCustomerPhoneNumber, #txtCustomerEmailnew, '
        + '#txtCustomerCivilID, #txtTableNumber, #txtNumberofGuests').val('');
        $('#chkReOrder, #chkTakeAway').prop('checked', false);
        $('#formCustomerInfo').removeClass('was-validated');

        // ---- delivery address step -----------------------------------------
        $('#txtHomeBlock, #txtHomeStreet, #txtHomeFlat, #txtHouseLandmark, '
        + '#txtApartmentBlock, #txtApartmentStreet, #txtApartmentBuilding, '
        + '#txtApartmentFloor, #txtApartmentFlatNo, #txtApartmentLandmark, '
        + '#txtOfficeBlock, #txtOfficeStreet, #txtOfficeBuilding, '
        + '#txtOfficeFloor, #txtOfficeFlat, #txtOfficeLandmark').val('');
        $('#AddressArea').val('');
        $('#hdnlat, #hdnlong').val('');
        $('#formDeliveryAddress').removeClass('was-validated');
        $('#ulListAddresses, #divBranchListPickup').html('');

        // ---- discount / payment step ---------------------------------------
        $('#txtdiscountCoupon').val('');
        $('#hdnDiscountTypeID').val('0');
        $('#lblDiscountAmount').text('0.000');
        $('#selectedPayementType').html('');
        $('.paymenttype').removeClass('activePayment');
    } catch (e) {
        // A reset that throws must never block the confirmation screen - the
        // order is already placed by this point.
    }
}

function checkCookie() {
    var IsItems = 0;
    var data = accessCookie("OrderCookie");

    // A cookie that is present but unreadable, or that holds an empty basket,
    // counts as no basket. Parsing it unguarded meant one malformed cookie
    // threw here and took the rest of the restore - and, because ClearcartData
    // calls this, the clear itself - down with it.
    var parsed = null;
    if (data != "" && data != undefined) {
        try { parsed = JSON.parse(decodeURIComponent(data)); }
        catch (e) {
            try { parsed = JSON.parse(data); } catch (e2) { parsed = null; }
        }
        if (parsed && !parsed.length) parsed = null;
    }

    if (parsed) {
        CartDetails = parsed;
        BindCartCount(CartDetails);
        IsItems = 1;
    }
    else {
        CartDetails = [];
        $(".clCartCount").each(function (index) {
            $(this).text(0);
            $(this).hide();
        });

        //$('#cartCountDesktop').text(0);
    }


    if (IsItems == 1) {
        var dataComment = accessCookie("CommentCookie");
        if (dataComment != "" && dataComment != undefined) {
            var obj = JSON.parse(dataComment);
            CartComments = obj;
        }

        //check when multiple select then it's throw exception
        try {
            var dataItemsCookie = accessCookie("ExtraItemsCookie");
            if (dataItemsCookie != "" && dataItemsCookie != undefined) {
                var objItemdata = JSON.parse(dataItemsCookie);
                CartExtraItems = objItemdata;
            }
        } catch { }



        try {
            var dataChoiceCookie = accessCookie("ChoiceItemsCookie");
            if (dataChoiceCookie != "" && dataChoiceCookie != undefined) {
                var objchoices = JSON.parse(dataChoiceCookie);
                CartChoicesItems = objchoices;
            }
        } catch { }
    }
    else {
        // No basket means no extras, no choices and no comments either. These
        // were left holding the previous basket's rows, so a new basket started
        // with someone else's extras attached to it - and the cart page counts
        // those rows, which is how one item could be listed as four.
        CartComments     = [];
        CartExtraItems   = [];
        CartChoicesItems = [];
    }

    var dataCustomerCookie = accessCookie("CustomerDetailsCookie");
    if (dataCustomerCookie != "" && dataCustomerCookie != undefined) {
        var objCustDetai = JSON.parse(dataCustomerCookie);
        CustomerDetails = objCustDetai;
    }
}
function accessCookie(cookieName) {
    var name = cookieName + "=";
    var allCookieArray = document.cookie.split(';');
    for (var i = 0; i < allCookieArray.length; i++) {
        var temp = allCookieArray[i].trim();
        if (temp.indexOf(name) == 0)
            return temp.substring(name.length, temp.length);
    }
    return "";
}

/*function myFunction() {
  var elmnt = document.getElementById("scrolldiv");
  var x = elmnt.scrollLeft;
  var y = elmnt.scrollTop;
    if(y >1)
    {
        $("#TopRow").addClass("toprowbackground");
    }
    else
    {
        $("#TopRow").removeClass("toprowbackground");
    }
}*/

$("#OrderType").change(function () {
    if ($(this).val() == "Delivery") {
        $('.clsDelivery').each(function () {
            $(this).show();
        });
        $('.clsPickup').each(function () {
            $(this).hide();
        });
    }
    else {
        $('.clsDelivery').each(function () {
            $(this).hide();
        });
        $('.clsPickup').each(function () {
            $(this).show();
        });

    }
});
//.change();

function BindSummaryTabData() {
    /*var Htmlstr = $('#CartView').html();
    var FinalHtmlstr = Htmlstr.replace("text:test;", "display:none;");
    FinalHtmlstr = FinalHtmlstr.replace("text:test;", "display:none;");
    $('#orderConfirmCart').html(FinalHtmlstr);*/

    //first tab User Information 
    $('#cnfFirstLastName').html($('#fname').val() + ' ' + $('#lname').val());
    $('#cnfPhoneNumber').html($('#phone').val());
    $('#cnfEmail').html($('#email').val());

    //Second tab Delivery Service Type 
    $('#cnfOrderType').html($('#OrderType').val());

    //Third tab Delivery Service Type 
    if ($('#OrderType').val() == "Delivery") {
        var str = $('#lblArea').html() + ' : ' + $('#AddressArea').children("option:selected").text() + ', '
            + $('#lblBlock').html() + ' : ' + $('#Block').val() + ', ' +
            $('#lblStreet').html() + ' : ' + $('#Street').val() + ', ' +
            $('#lblBuilding').html() + ' : ' + $('#Building').val() + ', ' +
            $('#lblFloor').html() + ' : ' + $('#Floor').val() + ', ' +
            $('#lblFlat').html() + ' : ' + $('#Flat').val() + ', ' +
            $('#lblLandmark').html() + ' : ' + $('#Landmark').val();

        $('#cnfAddressarea').html(str);
        /*$('#cnfBlock').html();
        $('#cnfStreet').html();
        $('#cnfBuilding').html();
        $('#cnfFlat').html();
        $('#cnfLandmark').html();*/
    }
    else {
        $('#cnfAddressarea').html('Area : ' + $('#ddrPickupArea').children("option:selected").text());
    }
}

function setSelected(selecteddiv) {
    debugger;
    $('#divKNET').css('background-color', '');
    $('#divELECTRONIC_CARD').css('background-color', '');
    $('#divCASH').css('background-color', '');
    $('#' + selecteddiv).css('background-color', '#eeeeef');

    if (selecteddiv == "divKNET") {
        $('#selectedPayementType').html("KNET");
    }
    else if (selecteddiv == "divELECTRONIC_CARD") {
        $('#selectedPayementType').html("Credit Card");
    }
    else {
        $('#selectedPayementType').html("Cash on delivery");
    }
}
function checkpayment() {
    debugger;
    if ($('#selectedPayementType').html() == "KNET") {
        var pdata = {}
        pdata["Amount"] = $('#hdntotalAmountConfirm').val();
        pdata["OrderReferenceNumber"] = 12314;
        pdata["PaymentType"] = 1; //1 is knet and 2 is MPGS,
        pdata["Variable1"] = "";
        pdata["Variable2"] = "";
        pdata["Variable3"] = "";
        pdata["Variable4"] = "";
        pdata["Variable5"] = "";

        var objdata = {
            paymentData: pdata,
        }
        debugger;
        $.ajax({
            type: "POST",
            data: JSON.stringify(objdata),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            url: "/payment/Index",
            success: function (result) {
                debugger;
                if (result.Message == "Success") {
                    debugger;
                    window.location.href = result.url;
                }
                else {
                    alert("Payment not done please contact to administrator.");
                }
            }
        });

    }
    else {
        SubmitOrder();
    }
}



function SubmitOrder() {
    debugger;
    //isfromWaiterTemp = isfromWaiter;
    //var Custinfo = {}

    //Custinfo["CustomerNameEng"] = $('#fname').val() + ' ' + $('#lname').val();
    //Custinfo["Mobile"] = $('#phone').val();
    //Custinfo["Email"] = $('#email').val();
    ////Custinfo["Mobile2"] = "";
    //Custinfo["HomeNo"] = "";
    //Custinfo["CivilID"] = "";
    //Custinfo["Block"] = $('#Block').val();
    //Custinfo["Street"] = $('#Street').val();
    //Custinfo["AddressRemarks"] = $('#Landmark').val();
    //Custinfo["Building"] = $('#Building').val();
    //Custinfo["Flat"] = $('#Flat').val();
    //Custinfo["Floor"] = $('#Floor').val();
    //Custinfo["AddressRemarks"] = "";
    //Custinfo["BranchID"] = $('#hdnBranchId').val();
    //Custinfo["Latitude"] = $('#hdnlat').val();
    //Custinfo["Longitude"] = $('#hdnlong').val();
    //if ($('#OrderType').val() == "Delivery") {
    //    Custinfo["AreaID"] = $('#AddressArea').val();
    //}
    //else {
    //    Custinfo["AreaID"] = $('#ddrPickupArea').val();
    //}


    var customerInfo = {}
    customerInfo["id"] = 0;
    customerInfo["CustomerName"] = $('#fname').val() + ' ' + $('#lname').val();
    customerInfo["Mobile"] = $('#phone').val();
    //customerInfo["Mobile2"] = $('#phone').val();
    customerInfo["CivilID"] = $('#txtCustomerCivilID').val();

    var addressInfo = {}
    addressInfo["id"] = 0;
    addressInfo["CustomerId"] = 0;
    addressInfo["Email"] = $('#email').val();
    if ($('#OrderType').val() == "Delivery") {
        addressInfo["Areaid"] = $('#AddressArea').val();
    }
    else {
        addressInfo["Areaid"] = $('#ddrPickupArea').val();
    }
    //addressInfo["AreaName"] = "";
    addressInfo["Block"] = $('#Block').val();
    addressInfo["Street"] = $('#Street').val();
    addressInfo["Lane"] = $('#Landmark').val();
    addressInfo["Building"] = $('#Building').val();
    addressInfo["Flat"] = $('#Flat').val();
    addressInfo["Floor"] = $('#Floor').val();
    addressInfo["HouseNo"] = "";
    //addressInfo["PACI"] = "";
    addressInfo["AddressRemarks"] = "";
    addressInfo["Lat"] = $('#hdnlat').val();
    addressInfo["Long"] = $('#hdnlong').val();




    var objCartDetails = CartDetails;
    var ObjDataCartDetails = [];
    $.each(objCartDetails, function (i, obj) {
        var item = {}
        item["ItemId"] = obj.I;
        item["HID"] = obj.O;
        item["qty"] = obj.Q;
        item["Comments"] = obj.C;
        item["ChoiceId"] = obj.CH;
        ObjDataCartDetails.push(item);
    });

    var objdata = {
        orderDetails: ObjDataCartDetails,
        customerInfo: customerInfo,
        addressInfo: addressInfo,
        selectedPayementType: $('#selectedPayementType').html(),  //check enum InvoicePaymentTypes or tblInvoicePaymentType
        branchid: 1
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/SubmitOrder",
        success: function (result) {
            if (result.Message == "Success") {
                $.confirm({
                    title: 'Order No: ' + result.InvoiceNo + '',
                    //content: 'Your order has been successfully process. Your order no is ' + result.InvoiceNo + '.',
                    content: 'Your order has been successfully been processed. An Invoice has been emailed to you.',
                    //icon: 'fa fa-question',
                    closeAnimation: 'scale',
                    opacity: 0.2,
                    theme: 'bootstrap',
                    //closeIcon: true,
                    animation: 'scale',
                    type: 'orange',
                    buttons: {
                        'confirm': {
                            text: 'Continue Shopping',
                            btnClass: 'btn-orange',
                            action: function () {
                                //ShowNotification("Your order has been successfully process. Your order no is " + result.InvoiceNo + ".");
                                ClearcartData();
                                //ShowMenuclick();
                                ShowMenuclickRedirect();
                            },
                            Cancel: function () {
                                //retval=false;
                                ClearcartData();
                                //ShowMenuclick();
                                ShowMenuclickRedirect();
                            },
                        }
                    }
                });

            }
            else {
                // ShowNotification(result.Message);
            }
        }
    });
}
var mymap = null;
function TrackOrder() {
    BindTrackorderdata();
}

//function BindTrackorderdata() {
//    //document.getElementById('mapcontainer').innerHTML = "<div id='TrackingMapDiv' style='width: 100%; height: 100%;' class='top_map_objects'></div>";
//    //$('.smartcms_ost_timeline').hide();
//    //$('.smartcms_ost_map').hide();
//    $('#DivOrderstatus').hide();
//    $('#msgTrackOrderBlank').hide();
//    $('#msgTrackOrderWrong').hide();
//    $('#msgContactManager').hide();

//    if ($('#txtTrackorderNumber').val() == "") {
//        $('#msgTrackOrderBlank').show();
//        return false;
//    }
//    var obj = {
//        InoiceNumber: $.trim($('#txtTrackorderNumber').val())
//    }
//    $.ajax({
//        type: "Post",
//        data: JSON.stringify(obj),
//        contentType: "application/json; charset=utf-8",
//        dataType: "json",
//        cache: false,
//        url: "/ItemsView/TrackOrder",
//        success: function (result) {
//            debugger;
//            if (result.Message == "Success") {
//                var Status = JSON.parse(result.InvoiceStatus);
//                $('#htmlOrdernumber').html($.trim($('#txtTrackorderNumber').val()));
//                $('.orderStatus').each(function () {
//                    $(this).removeClass("done");
//                    $(this).removeClass("active");
//                });
//                if (Status == "1") { //Order Received
//                    $('#liordOrderReceived').addClass("active");
//                    //$('#liordOrderKitchen').addClass("active");
//                }
//                else if (Status == "2") { //OrderShipped / Kitchen
//                    $('#liordOrderReceived').addClass("done");
//                    $('#liordOrderKitchen').addClass("active");
//                }
//                else if (Status == "3") { //Order With Driver
//                    $('#liordOrderReceived').addClass("done");
//                    $('#liordOrderKitchen').addClass("done");
//                    $('#liordOrderWithDriver').addClass("active");
//                }
//                else if (Status == "4") { //Order Delivered
//                    $('#liordOrderReceived').addClass("done");
//                    $('#liordOrderKitchen').addClass("done");
//                    $('#liordOrderWithDriver').addClass("done");
//                    $('#liordOrderDelivered').addClass("done");
//                }
//                //$('.smartcms_ost_timeline').show();
//                //$('.smartcms_ost_map').show();
//                $('#DivOrderstatus').show();

//                mymap = new L.Map('TrackingMapDiv', {
//                    center: [0, 0],
//                    zoom: 0,
//                    layers: [
//                        new L.TileLayer('http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
//                            'attribution': 'Map data © <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
//                        })
//                    ]
//                }).setView([29.378586, 47.990341], 12);
//                $.each(result.dtMapData, function (key, value) {
//                    mymap.setView([value.CurrentLat, value.CurrentLong], 15);
//                });
//                setInterval(function () {
//                    setTrackOrderMap();
//                }, 3000);
//            } else {
//                if (result.Message == "Invalid Invoice Number.") {
//                    $('#msgTrackOrderWrong').show();
//                }
//                else if (result.Message == "Error,Contact Your Manager.") {
//                    $('#msgContactManager').show();
//                }
//            }
//        }
//    });
//}

function BindTrackorderdataNew() {
    debugger;
    document.getElementById('mapcontainer').innerHTML = "<div id='TrackingMapDiv' style='width: 100%; height: 100%;' class='top_map_objects'></div>";
    //document.getElementById('mapcontainer').innerHTML = "<div id='TrackingMapDiv' width='100%' height='100%' style=' width: 100%;border:0;'></div>"
    //$('.smartcms_ost_timeline').hide();
    //$('.smartcms_ost_map').hide();
    $('#DivOrderstatus').hide();
    $('#msgTrackOrderBlank').hide();
    $('#msgTrackOrderWrong').hide();
    $('#msgContactManager').hide();

    if ($('#txtTrackorderNumber').val() == "") {
        $('#msgTrackOrderBlank').show();
        return false;
    }
    var obj = {
        InoiceNumber: $.trim($('#txtTrackorderNumber').val())
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsViewNew/BindTrackorderdataNew",
        success: function (result) {
            debugger;
            result = JSON.parse(result);
            if (result.Message == "Success") {
                var Status = JSON.parse(result.InvoiceStatus);
                $('#htmlOrdernumber').html($.trim($('#txtTrackorderNumber').val()));
                $('.orderStatus').each(function () {
                    $(this).removeClass("done");
                    $(this).removeClass("active");
                });
                if (Status == "1") { //Order Received
                    $('#liordOrderReceived').addClass("active");
                    //$('#liordOrderKitchen').addClass("active");
                }
                else if (Status == "2") { //OrderShipped / Kitchen
                    $('#liordOrderReceived').addClass("done");
                    $('#liordOrderKitchen').addClass("active");
                }
                else if (Status == "3") { //Order With Driver
                    $('#liordOrderReceived').addClass("done");
                    $('#liordOrderKitchen').addClass("done");
                    $('#liordOrderWithDriver').addClass("active");
                }
                else if (Status == "4") { //Order Delivered
                    $('#liordOrderReceived').addClass("done");
                    $('#liordOrderKitchen').addClass("done");
                    $('#liordOrderWithDriver').addClass("done");
                    $('#liordOrderDelivered').addClass("done");
                }
                $('#DivOrderstatus').show();


                mymap = new L.Map('TrackingMapDiv', {
                    center: [0, 0],
                    zoom: 0,
                    layers: [
                        //new L.TileLayer('http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                        //    'attribution': 'Map data © <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
                        //})
                        new L.TileLayer('https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png', {
                            'attribution': '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                        })
                    ]
                }).setView([29.378586, 47.990341], 12);

                createMap(result.dtMapData);
            } else {
                if (result.Message == "Invalid Invoice Number.") {
                    $('#msgTrackOrderWrong').show();
                }
                else if (result.Message == "Error,Contact Your Manager.") {
                    //$('#msgContactManager').show();
                    $('#msgContactManager').show();
                }
            }
        }
    });
}
var LeafIcon = L.Icon.extend({
    options: {
        //shadowUrl: 'leaf-shadow.png',
        //iconSize:     [45, 40],
        //shadowSize:   [50, 64],
        iconAnchor: [30, 40],
        //shadowAnchor: [4, 62],
        popupAnchor: [-3, -35]
    }
});

var DriverMarkinlayersToRemove = [];
var polylinelayersToRemove = [];
function createMap(objdata) {

    /*var mymap = L.map('TrackingMapDiv', {
        //center: [39.73, -104.99],
       // zoom: 10,
       // layers: [grayscale, cities]
    }).setView([29.378586, 47.990341], 12);*/




    /*L.tileLayer(mapboxUrl, {
       maxZoom: 20,
       attribution: mapboxAttribution,
       id: 'mapbox.streets'
   }).addTo(mymap);*/
    debugger


    //first remove old driverMarkins
    for (i = 0; i < DriverMarkinlayersToRemove.length; i++) {
        mymap.removeLayer(DriverMarkinlayersToRemove[i]);
    }
    DriverMarkinlayersToRemove = [];

    //first remove old path
    for (i = 0; i < polylinelayersToRemove.length; i++) {
        mymap.removeLayer(polylinelayersToRemove[i]);
    }
    polylinelayersToRemove = [];

    $.each(objdata, function (key, value) {
        debugger;
        //var carIcon = new LeafIcon({iconUrl: '../../Content/maps/images/car.png'}),
        //CustomerIcon = new LeafIcon({iconUrl: '../../Content/maps/images/Customer.png'});

        //var carIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/' + value.DriverImage });
        var carIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/car.png' });
        var CustomerIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/Customer.png' });

        var DriverMarkin = L.marker([value.CurrentLat, value.CurrentLong], { icon: carIcon }).bindPopup('Driver Name: ' + value.DriverName)
        DriverMarkin.addTo(mymap);
        DriverMarkinlayersToRemove.push(DriverMarkin);

        var CustMarkin = L.marker([value.ToLat, value.ToLong], { icon: CustomerIcon }).bindPopup('Customer : ' + value.CustomerName + '\n,InvoiceNo: ' + value.InvoiceNo)
        CustMarkin.addTo(mymap);
        //layersToRemove.push(CustMarkin);
        //mymap.setView([value.ToLat, value.ToLong], 14);

        //draw path
        var pointA = new L.LatLng(value.CurrentLat, value.CurrentLong);
        var pointB = new L.LatLng(value.ToLat, value.ToLong);
        var pointList = [pointA, pointB];
        var firstpolyline = new L.Polyline(pointList, {
            color: value.DriverColor,
            weight: 7,
            opacity: 0.7,
            smoothFactor: 1
        });

        firstpolyline.addTo(mymap);
        polylinelayersToRemove.push(firstpolyline);
    });

}
function BindAreaDropdown() {
    debugger;
    $.ajax({
        type: "Post",
        // branchId filters the list to areas this branch actually delivers to
        data: { branchId: parseInt($('#hdnBranchId').val(), 10) || 0 },
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetAreaList",
        success: function (result) {
            $('#AddressArea').html("");
            var areastr = "<option id='optionSelect' value=''>Select</option>";
            if (result.Message == "Success") {
                var ObjAreaList = JSON.parse(result.dtresult);
                $.each(ObjAreaList, function (index, jsonObject) {
                    var AreaName = "";
                    if ($('#selectedLang').val() == "EN") {
                        AreaName = jsonObject.AreaName;
                    }
                    else {
                        AreaName = jsonObject.AreaNameAra;
                    }

                    areastr = areastr + "<option value='" + jsonObject.AreaID + "' data-val='" + jsonObject.DeliveryCharges + "'>" + AreaName + "</option>";
                    //$.each(jsonObject, function (key, val) {
                    //    console.log("key : " + key + " ; value : " + val);
                    //});
                });

            } else {
                if (result.Message == "Invalid Invoice Number.") {
                    $('#msgTrackOrderWrong').show();
                }
                else if (result.Message == "Error,Contact Your Manager.") {
                    //$('#msgContactManager').show();
                    $('#msgTrackOrderWrong').show();
                }
            }
            $('#AddressArea').html(areastr);
            $('#AddressArea').val($('#hdnSelectedArea').val());
        }
    });
}

function ddrAreaChangeBindDelCharg(obj) {
    var selectedDeliveryCharge = $(obj).find(':selected').attr('data-val');
    $('#hdnAreaDeliveryCharges').val(selectedDeliveryCharge);
    $('#hdnSelectedArea').val($(obj).find(':selected').val());
}

$(document).on('click', '.menu-item', function (e) {
    $('#kt_header_mobile_toggle').click()
    //jQuery.each($('.header-navs-on'), function (i, val) {
    //    $(this).removeClass("header-navs-on");
    //    $('.header-navs-overlay').remove();
    //    $('.burge-icon-active').removeClass("burge-icon-active");
    //}); 
});


//////////////////start track order generate map events///////////////////////
var mapboxUrl = 'https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token=__MAPBOX_ACCESS_TOKEN__';
var mapboxAttribution = 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, ' +
    '<a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, ' +
    'Imagery © <a href="https://www.mapbox.com/">Mapbox</a>';

/*var mapboxUrl='http://{s}.tile.osm.org/{z}/{x}/{y}.png';
var mapboxAttribution='&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors';*/
//var LeafIcon = L.Icon.extend({
//    options: {
//        //shadowUrl: 'leaf-shadow.png',
//        //iconSize:     [45, 40],
//        //shadowSize:   [50, 64],
//        iconAnchor: [30, 40],
//        //shadowAnchor: [4, 62],
//        popupAnchor: [-3, -35]
//    }
//});



var DriverMarkinlayersToRemove = [];
var polylinelayersToRemove = [];

function setTrackOrderMap() {
    var obj = {
        InoiceNumber: $('#txtTrackorderNumber').val()
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/TrackOrder",
        success: function (result) {
            if (result.Message == "Success") {
                BindTrackorderMap(result.dtMapData);
            } else {
            }
        }
    });

}
function BindTrackorderMap(objdata) {


    //first remove old driverMarkins
    for (i = 0; i < DriverMarkinlayersToRemove.length; i++) {
        mymap.removeLayer(DriverMarkinlayersToRemove[i]);
    }
    DriverMarkinlayersToRemove = [];

    //first remove old path
    for (i = 0; i < polylinelayersToRemove.length; i++) {
        mymap.removeLayer(polylinelayersToRemove[i]);
    }
    polylinelayersToRemove = [];

    $.each(objdata, function (key, value) {
        //var carIcon = new LeafIcon({iconUrl: '../../Content/maps/images/car.png'}),
        //CustomerIcon = new LeafIcon({iconUrl: '../../Content/maps/images/Customer.png'});

        var carIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/' + value.DriverImage }),
            CustomerIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/Customer.png' });

        var DriverMarkin = L.marker([value.CurrentLat, value.CurrentLong], { icon: carIcon }).bindPopup('Driver Name: ' + value.DriverName)
        DriverMarkin.addTo(mymap);
        DriverMarkinlayersToRemove.push(DriverMarkin);


        var CustMarkin = L.marker([value.ToLat, value.ToLong], { icon: CustomerIcon }).bindPopup('Customer : ' + value.CustomerName + '\n,InvoiceNo: ' + value.InvoiceNo)
        CustMarkin.addTo(mymap);

        //mymap.setView([value.ToLat, value.ToLong], 14);

        //draw path
        var pointA = new L.LatLng(value.CurrentLat, value.CurrentLong);
        var pointB = new L.LatLng(value.ToLat, value.ToLong);
        var pointList = [pointA, pointB];
        var firstpolyline = new L.Polyline(pointList, {
            color: value.DriverColor,
            weight: 7,
            opacity: 0.7,
            smoothFactor: 1
        });

        firstpolyline.addTo(mymap);
        polylinelayersToRemove.push(firstpolyline);
    });

    //setClickOnmapclick(mymap);
}
//////////////////End track order generate map events///////////////////////

function ItemDetailsChoicesCheckboxclick(obj, MainItemId, ChoiceId, price, GroupId) {
    //var ischecked = false;
    debugger;
    //$(".ItemsChoice").each(function (index) {
    //    if ($(this).prop("checked") == true) {
    //        $(this).prop("checked", false);
    //    }
    //});
    var ischecked = false;
    if ($(obj).find("input[type='checkbox']").prop("checked") == true) {
        ischecked = false;
    } else {
        ischecked = true;
    }
    //var islimitover = ischecked == false ? true : choicesitemSelect(ischecked, GroupId);
    var islimitover = choicesitemSelect(ischecked, GroupId);
    if (islimitover) {

        if (ischecked) {
            $(obj).find("input[type='checkbox']").prop("checked", true);
        }
        else {
            $(obj).find("input[type='checkbox']").prop("checked", false);
        }


        //var itemOriginalprice = parseFloat($('#hdnItem_PRICE_' + MainItemId).val().trim());
        //$('#divitemDetailsPrice').html(price.toFixed(3));
        //$('#divitemDetailsPrice').html((itemOriginalprice + parseFloat(price)).toFixed(3));
        ////if ($(obj).find("input[type='checkbox']").prop("checked") == true) {
        //$(obj).find("input[type='checkbox']").prop("checked", true);
        ////}

        //if ($(obj).find("input[type='checkbox']").prop("checked") == true) {
        //    ischecked = false;
        //    $(obj).find("input[type='checkbox']").prop("checked", false);


        //} else {
        //    ischecked = true;
        //    $(obj).find("input[type='checkbox']").prop("checked", true);
        //}
        var extraitemsTotal = 0.000;
        $(".extraItems").each(function (index) {
            if ($(this).prop("checked") == true) {
                extraitemsTotal = extraitemsTotal + parseFloat($(this).val());
            }
            //console.log(index + ": " + $(this).text());
        });

        var itemunitprice = parseFloat($('#divitemDetailsPrice').html());
        var itemTotalPrice = parseFloat(extraitemsTotal) + parseFloat(itemunitprice);
        $('#divitemDetailsTotalPrice').html(round(parseFloat(itemTotalPrice) ? itemTotalPrice : (0.000), decimalPlace).toFixed(decimalPlace));

        //pending store choice in cookies
        ///////////////Start manage ExtraItemsCookie /////////////////////////
        //var tempCartDetails = CartDetails;
        //$.each(tempCartDetails, function (i, obj) {
        //    if (obj.I == MainItemId) {
        //        obj.CH = ChoiceId;
        //        obj.gp = GroupId;
        //        //tempCartExtraItems = jQuery.grep(tempCartExtraItems, function (value) {
        //        //    return value != obj;
        //        //});
        //    }
        //});
        //var val = JSON.stringify(tempCartDetails);
        //createCookie("OrderCookie", val, 365);
        //CartDetails = tempCartDetails;

        var tempCartChoicesItems = CartChoicesItems;
        //add
        if (ischecked) {
            var item = {}
            item["UID"] = parseInt($('#hdnSelectedUID').val());
            item["MainItemId"] = MainItemId;
            item["ChoiceItemId"] = ChoiceId;
            item["GroupId"] = GroupId;
            item["ItemName"] = $('#ItemChoiceName_' + ChoiceId + '').html().trim().replace("&nbsp;", "");
            item["Price"] = price;
            tempCartChoicesItems.push(item);
        }
        else {  //remove
            $.each(tempCartChoicesItems, function (i, obj) {
                if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemId && obj.ChoiceItemId == ChoiceId && obj.GroupId == GroupId) {
                    tempCartChoicesItems = jQuery.grep(tempCartChoicesItems, function (value) {
                        return value != obj;
                    });
                }
            });
        }
        var val = JSON.stringify(tempCartChoicesItems);
        createCookie("ChoiceItemsCookie", val, 365);

        CartChoicesItems = tempCartChoicesItems;

        UpdateItemDetailsPrices(MainItemId, parseInt($('#hdnSelectedUID').val()));
        /////////////////End manage ExtraItemsCookie /////////////////////////
    }

}

function ItemDetailsExtraItemsCheckboxclick(obj, MainItemId, ExtraItemId, price, GroupId) {
    debugger;

    var ischecked = false;
    if ($(obj).find("input[type='checkbox']").prop("checked") == true) {
        ischecked = false;
    } else {
        ischecked = true;
    }
    //var islimitover = ischecked == false ? true : extraitemSelect(ischecked, GroupId);
    var islimitover = extraitemSelect(ischecked, GroupId);
    if (islimitover) {

        if (ischecked) {
            $(obj).find("input[type='checkbox']").prop("checked", true);
        }
        else {
            $(obj).find("input[type='checkbox']").prop("checked", false);
        }


        var ExtraItemsTotal = 0.000;
        $(".extraItems").each(function (index) {
            if ($(this).prop("checked") == true) {
                ExtraItemsTotal = ExtraItemsTotal + parseFloat($(this).val());
            }
            //console.log(index + ": " + $(this).text());
        });

        //commented on 3-jan-2023, no need to update price, price should be update on add button click
        //var itemunitprice = parseFloat($('#divitemDetailsPrice').html());
        //var itemTotalPrice = parseFloat(ExtraItemsTotal) + parseFloat(itemunitprice);
        //$('#divitemDetailsTotalPrice').html(parseFloat(itemTotalPrice) ? itemTotalPrice.toFixed(3) : (0.000).toFixed(3));


        /////////////////Start manage ExtraItemsCookie /////////////////////////
        var tempCartExtraItems = CartExtraItems;
        //add
        if (ischecked) {
            var item = {}
            item["UID"] = parseInt($('#hdnSelectedUID').val());
            item["MainItemId"] = MainItemId;
            item["ExtraItemId"] = ExtraItemId;
            item["GroupId"] = GroupId;
            item["ItemName"] = $('#extraItemName_' + ExtraItemId + '').html().trim().replace("&nbsp;", "");
            item["Price"] = price;
            tempCartExtraItems.push(item);
        }
        else {  //remove
            $.each(tempCartExtraItems, function (i, obj) {
                if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemId && obj.ExtraItemId == ExtraItemId && obj.GroupId == GroupId) {
                    tempCartExtraItems = jQuery.grep(tempCartExtraItems, function (value) {
                        return value != obj;
                    });
                }
            });
        }
        var val = JSON.stringify(tempCartExtraItems);
        createCookie("ExtraItemsCookie", val, 365);

        CartExtraItems = tempCartExtraItems;

        var selectedQty = $('#lblItemInfoQty').val() != undefined ? parseInt($('#lblItemInfoQty').val()) : 0.000;
        //if (selectedQty == 0) {
        //    selectedQty = parseInt($('#divItemwiseCount_' + UID + '').html());
        //}


        //insert if condition on 3-jan-2023, no need to update price, price should be update on add button click
        if (selectedQty > 0) {
            UpdateItemDetailsPrices(MainItemId, parseInt($('#hdnSelectedUID').val()));
            //debugger;
            //$('#divExtraitemDetailsPrice').html(parseFloat(ExtraItemsTotal.toFixed(3)) ? ExtraItemsTotal.toFixed(3) : (0.000).toFixed(3));

            //var unitprice = parseFloat($('#divitemDetailsPrice').html());
            //var ItemDetailsTotal = (unitprice * 1) + ExtraItemsTotal;
            //$('#divitemDetailsTotalPrice').html(parseFloat(ItemDetailsTotal) ? ItemDetailsTotal.toFixed(3) : (0.000).toFixed(3));
        }


        /////////////////End manage ExtraItemsCookie /////////////////////////
    }

}

function ItemDetailsCommentsCheckboxclick(obj, MainItemId, CommentId) {
    var ischecked = false;
    if ($(obj).find("input[type='checkbox']").prop("checked") == true) {
        ischecked = false;
        $(obj).find("input[type='checkbox']").prop("checked", false);
    } else {
        ischecked = true;
        $(obj).find("input[type='checkbox']").prop("checked", true);
    }


    /////////////////Start manage ExtraItemsCookie /////////////////////////
    var tempCartComments = CartComments;
    //add
    if (ischecked) {
        var item = {}
        item["UID"] = parseInt($('#hdnSelectedUID').val());
        item["MainItemId"] = MainItemId;
        item["CommentId"] = CommentId;
        item["Comment"] = $('#extraCommentName_' + CommentId + '_' + MainItemId + '').html();
        tempCartComments.push(item);
    }
    else {  //remove
        $.each(tempCartComments, function (i, obj) {
            if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.MainItemId == MainItemId && obj.CommentId == CommentId) {
                tempCartComments = jQuery.grep(tempCartComments, function (value) {
                    return value != obj;
                });
            }
        });
    }
    var val = JSON.stringify(tempCartComments);
    createCookie("CommentCookie", val, 365);

    CartComments = tempCartComments;
    /////////////////End manage ExtraItemsCookie /////////////////////////
}

function extraitemSelect(ischecked, groupid) {
    debugger;
    var isvalid = true;
    var cntselected = 0;
    var minlimit = parseInt($('#hdnGroupMinSelect_' + groupid + '').val());
    var maxlimit = parseInt($('#hdnGroupMaxselect_' + groupid + '').val());

    if (parseInt(maxlimit) == 1) {
        var tempCartExtraItems = CartExtraItems;
        var IsUpdate = 0;
        $(".clsExtraItemsDiv_" + groupid + "").each(function () {
            if ($(this).prop("checked") == true) {
                $(this).prop("checked", false);
                IsUpdate = 1;
            }
            $.each(tempCartExtraItems, function (i, obj) {
                if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.GroupId == groupid) {
                    tempCartExtraItems = jQuery.grep(tempCartExtraItems, function (value) {
                        return value != obj;
                    });
                    IsUpdate = 1;
                }
            });
        });
        if (IsUpdate == 1) {
            var val = JSON.stringify(tempCartExtraItems);
            createCookie("ExtraItemsCookie", val, 365);
            CartExtraItems = tempCartExtraItems;
        }
    }



    $(".clsExtraItemsDiv_" + groupid + "").each(function () {
        if ($(this).prop("checked") == true) {
            cntselected += 1;
        }
    });
    if (ischecked && cntselected >= maxlimit) {
        isvalid = false;
    }
    if (ischecked && isvalid) {
        $('#hdnGroupSelectd_' + groupid + '').val(cntselected + 1);
    }
    else {
        $('#hdnGroupSelectd_' + groupid + '').val(cntselected - 1);
    }

    return isvalid;
}


function choicesitemSelect(ischecked, groupid) {
    debugger;
    var isvalid = true;
    var cntselected = 0;
    var minlimit = parseInt($('#hdnchGroupMinSelect_' + groupid + '').val());
    var maxlimit = parseInt($('#hdnchGroupMaxselect_' + groupid + '').val());

    if (parseInt(maxlimit) == 1) {
        var tempCartChoicesItems = CartChoicesItems;
        var IsUpdate = 0;
        $(".clsChoiceItemsDiv_" + groupid + "").each(function () {
            if ($(this).prop("checked") == true) {
                $(this).prop("checked", false);
                IsUpdate = 1;
            }
            $.each(tempCartChoicesItems, function (i, obj) {
                if (obj.UID == parseInt($('#hdnSelectedUID').val()) && obj.GroupId == groupid) {
                    tempCartChoicesItems = jQuery.grep(tempCartChoicesItems, function (value) {
                        return value != obj;
                    });
                    IsUpdate = 1;
                }
            });
        });
        if (IsUpdate == 1) {
            var val = JSON.stringify(tempCartChoicesItems);
            createCookie("ChoiceItemsCookie", val, 365);
            CartChoicesItems = tempCartChoicesItems;
        }
    }
    $(".clsChoiceItemsDiv_" + groupid + "").each(function () {
        if ($(this).prop("checked") == true) {
            cntselected += 1;
        }
    });


    if (cntselected >= maxlimit && ischecked) {
        isvalid = false;
    }
    if (ischecked && isvalid) {
        $('#hdnchGroupSelectd_' + groupid + '').val(cntselected + 1);
    }
    else {
        if (cntselected == 0) {
            $('#hdnchGroupSelectd_' + groupid + '').val(0);
        }
        else {
            $('#hdnchGroupSelectd_' + groupid + '').val(cntselected - 1);
        }
    }

    return isvalid;
}
//function validateExtraItemGrpselection() {
//    debugger;
//    var rtn = true;
//    $(".clsExtraItemsGrp").each(function () {
//        var tmp = $(this).attr("id").split("_");
//        var groupid = tmp[1];
//        var minqty = parseInt($('#hdnGroupMinSelect_' + groupid + '').val());
//        var selectqty = parseInt($('#hdnGroupSelectd_' + groupid + '').val());
//        if (minqty != selectqty) {
//            rtn= false;
//            $('#divExtraItemGroup_' + groupid + '').css('background-color', 'red'); // remove this and display alert and hightlight group
//        }
//    });
//    return rtn;
//}


function validateExtraItemGrpselection() {
    debugger;
    var isvalid = true;
    var errorstring = "";
    $.each($(".clsExtraItemsGrp"), function (i, obj) {
        var tmpval = $(obj).attr("id").split("_");
        var groupid = tmpval[1];
        var minvalue = parseInt($('#hdnGroupMinSelect_' + groupid + '').val());
        var maxvalue = parseInt($('#hdnGroupMaxselect_' + groupid + '').val());
        var selectedvalue = parseInt($('#hdnGroupSelectd_' + groupid + '').val());
        //check minimum values is there
        if (minvalue > 0) {
            if (selectedvalue < minvalue) {
                var groupname = $('#lblSelectExtraItemsGrp_' + groupid + '').html();
                isvalid = false;
                $('#lblSelectExtraItemsGrp_' + groupid + '').focus();
                errorstring = errorstring + "Please select " + groupname + " group minimum " + minvalue + "item.<br\><br\>\n";
                //alert("Please select " + groupname + " group minimum " + minvalue + "item.");
            }
        }
    });

    if (isvalid == false) {
        $.confirm({
            title: 'Alert',
            content: errorstring,
            icon: 'fa fa-exclamation-triangle',
            closeAnimation: 'scale',
            opacity: 0.2,
            theme: 'bootstrap',
            closeIcon: true,
            animation: 'scale',
            type: 'orange',
            width: '250',
            buttons: {
                'confirm': {
                    text: 'Ok',
                    btnClass: 'btn-orange',
                    //action: function () {
                    //    //minuseItem(itemid, CartDetails, true);
                    //    //UpdateSubTotal(itemid);
                    //},
                    //Cancel: function () {
                    //    //retval=false;
                    //},
                }
            }
        });
    }
    return isvalid;
}

function validateExtraChoicesGrpselection() {
    debugger;
    var isvalid = true;
    var errorstring = "";
    $.each($(".clsChoiceItemsGrp"), function (i, obj) {
        var tmpval = $(obj).attr("id").split("_");
        var groupid = tmpval[1];
        var minvalue = parseInt($('#hdnchGroupMinSelect_' + groupid + '').val());
        var maxvalue = parseInt($('#hdnchGroupMaxselect_' + groupid + '').val());
        var selectedvalue = parseInt($('#hdnchGroupSelectd_' + groupid + '').val());
        //check minimum values is there
        if (minvalue > 0) {
            if (selectedvalue < minvalue) {
                var groupname = $('#lblSelectChoiceItemsGrp_' + groupid + '').html();
                $('#lblSelectChoiceItemsGrp_' + groupid + '').focus();
                isvalid = false;
                //alert("Please select " + groupname + " group minimum " + minvalue + "item.");
                errorstring = errorstring + "Please select " + groupname + " group minimum " + minvalue + "item.<br\><br\>\n";
            }
        }
    });

    if (isvalid == false) {
        $.confirm({
            title: 'Alert',
            content: errorstring,
            //content: "Please select required Options",
            icon: 'fa fa-exclamation-triangle',
            closeAnimation: 'scale',
            opacity: 0.2,
            theme: 'bootstrap',
            closeIcon: true,
            animation: 'scale',
            type: 'orange',
            width: '250',
            buttons: {
                'confirm': {
                    text: 'Ok',
                    btnClass: 'btn-orange',
                    //action: function () {
                    //    //minuseItem(itemid, CartDetails, true);
                    //    //UpdateSubTotal(itemid);
                    //},
                    //Cancel: function () {
                    //    //retval=false;
                    //},
                }
            }
        });
    }
    return isvalid;
}


function startRatingClick(btn, LayoutID, id) {
    debugger;
    $('.strRat').each(function (i, obj) {
        $(this).removeClass("checked");
    });
    for (var i = 0; i <= id; i++) {
        $("#strRating_" + LayoutID + "_" + i).addClass('checked');
    }

    //$('#branch-menu').modal('show');

}

function smaileRatingClick(btn, id) {
    debugger;
    $('.clsmile').each(function (i, obj) {
        $(this).removeClass("clsSmilechecked");
    });
    $(btn).addClass("clsSmilechecked");
    //for (var i = 0; i <= id; i++) {
    //    $("#strRating_" + i).addClass('checked');
    //}

}





function giveFeedback(btn) {
    //$('#branch-menu').modal('show');
    debugger;
    //$("#order-feedback").modal('show');
    $('#divMainQuestions').html("");
    $('#txtFdbCustomerName').val("");
    $('#txtFdbCustomerPhonenumber').val("");
    var objdata = {
        BrandId: $('#hdnbrandId').val(),
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsViewNew/GetFeedbackFormQuestion",
        success: function (result) {
            if (result.Message == "Success") {
                debugger;
                var QuestionsList = JSON.parse(result.dtQuestions);
                bindFeedBackQuestions(QuestionsList);
                $("#order-feedback").modal('show');
            }
        }
    });
}
function bindFeedBackQuestions(QuestionsList) {
    debugger;
    if (QuestionsList.length > 0) {
        $.each(QuestionsList, function (i, obj) {
            if (obj.Type == "Star Rating") {
                var str = '<div id="question_' + obj.LayoutID + '" data-Question="' + obj.LayoutID + '" data-val="Rating" data-FeedbackTypeId="' + obj.FeedbackTypeid + '" class="card mb-3 clQuestions">\
                    <div class="card-body p-4">\
                        <h5 id="questionTxt_' + obj.LayoutID + '" class="card-title font-weight-bold pb-2">' + obj.Questions + '</h5>\
                        <div class="star-rating mb-0 p-0">\
                            <span id="strRating_'+ obj.LayoutID + '_1" class="fa fa-star strRat checked" onclick="startRatingClick(this,' + obj.LayoutID + ',1)"></span>\
                            <span id="strRating_'+ obj.LayoutID + '_2" class="fa fa-star strRat checked" onclick="startRatingClick(this,' + obj.LayoutID + ',2)"></span>\
                            <span id="strRating_'+ obj.LayoutID + '_3" class="fa fa-star strRat checked" onclick="startRatingClick(this,' + obj.LayoutID + ',3)"></span>\
                            <span id="strRating_'+ obj.LayoutID + '_4" class="fa fa-star strRat" onclick="startRatingClick(this,' + obj.LayoutID + ',4)"></span>\
                            <span id="strRating_'+ obj.LayoutID + '_5" class="fa fa-star strRat" onclick="startRatingClick(this,' + obj.LayoutID + ',5)"></span>\
                        </div>\
                    </div>\
                </div>';
                $('#divMainQuestions').append(str);
            }
            if (obj.Type == "Smiley") {
                var str = '<div id="question_' + obj.LayoutID + '" data-Question="' + obj.LayoutID + '" data-val="Smile" data-FeedbackTypeId="' + obj.FeedbackTypeid + '" class="card mb-3 clQuestions">\
                                <div class="card-body p-4">\
                                    <h5 id="questionTxt_' + obj.LayoutID + '" class="card-title font-weight-bold pb-2">' + obj.Questions + '</h5>\
                                    <div class="smiley-outer d-flex">\
                                        <img id="imgSmile_'+ obj.LayoutID + '_1" class="mr-3 clsmile" src="../Images/smiley-03.svg" alt="smiley" onclick="smaileRatingClick(this,1)">\
                                        <img id="imgSmile_'+ obj.LayoutID + '_2" class="mr-3 clsmile clsSmilechecked" src="../Images/smiley-02.svg" alt="smiley" onclick="smaileRatingClick(this,2)">\
                                        <img id="imgSmile_'+ obj.LayoutID + '_3" class="clsmile" src="../Images/smiley-01.svg" alt="smiley" onclick="smaileRatingClick(this,3)">\
                                    </div>\
                                </div>\
                            </div>';
                $('#divMainQuestions').append(str);
            }
            if (obj.Type == "Question") {
                var str = '<div id="question_' + obj.LayoutID + '" data-Question="' + obj.LayoutID + '" data-val="RadioQuestion" data-FeedbackTypeId="' + obj.FeedbackTypeid + '" class="card mb-3 clQuestions">\
                                <div class="card-body p-4">\
                                    <h5 id="questionTxt_' + obj.LayoutID + '" class="card-title font-weight-bold pb-2">' + obj.Questions + '</h5>\
                                    <div class="form-check form-check-inline">\
                                        <input  id="chkRadio_'+ obj.LayoutID + '_Yes" data-val="Yes" class="form-check-input" type="radio" name="inlineRadioOptions" id="inlineRadio1" value="option1">\
                                        <label class="form-check-label" for="inlineRadio1">Yes</label>\
                                    </div>\
                                    <div class="form-check form-check-inline">\
                                        <input  id="chkRadio_'+ obj.LayoutID + '_No" data-val="No" class="form-check-input" type="radio" name="inlineRadioOptions" id="inlineRadio2" value="option2">\
                                        <label class="form-check-label" for="inlineRadio2">No</label>\
                                    </div>\
                                </div>\
                        </div>';
                $('#divMainQuestions').append(str);
            }
            if (obj.Type == "Text") {
                var str = '<div id="question_' + obj.LayoutID + '" data-Question="' + obj.LayoutID + '" data-val="Text" data-FeedbackTypeId="' + obj.FeedbackTypeid + '" class="card mb-3 clQuestions">\
                    <div class="card-body p-4">\
                        <h5 id="questionTxt_' + obj.LayoutID + '" class="card-title font-weight-bold pb-2">' + obj.Questions + '</h5>\
                        <textarea id="txtarea_'+ obj.LayoutID + '"  class="form-control h-100" rows="3"></textarea>\
                    </div>\
                </div>';
                $('#divMainQuestions').append(str);
            }
        });
    }
}


function btnFeedback_submitClick() {
    debugger;
    var Customer_name = $('#txtFdbCustomerName').val();
    var Customer_email = "";
    var Customer_mobile = $('#txtFdbCustomerPhonenumber').val();
    var lstQUestion = [];
    $(".clQuestions").each(function () {
        var QuestionId = $(this).attr("data-Question");
        var QuestionType = $(this).attr("data-val");
        var QuestionTypeId = $(this).attr("data-FeedbackTypeId");
        //var QuestionText = $('#questionTxt_'+QuestionId+'').text();
        item = {};
        item["QuestionId"] = QuestionId;
        item["Response_Type"] = QuestionTypeId;
        //item["Question"] = $(this).attr("data-FeedbackTypeId");
        //item["Response_Type"] = $(this).attr("data-FeedbackTypeId");
        if (QuestionType == "Rating") {
            if ($('#strRating_' + QuestionId + '_5').hasClass("checked")) {
                item["Response"] = "5";
            }
            else if ($('#strRating_' + QuestionId + '_4').hasClass("checked")) {
                item["Response"] = "4";
            }
            else if ($('#strRating_' + QuestionId + '_3').hasClass("checked")) {
                item["Response"] = "3";
            }
            else if ($('#strRating_' + QuestionId + '_2').hasClass("checked")) {
                item["Response"] = "2";
            }
            else if ($('#strRating_' + QuestionId + '_1').hasClass("checked")) {
                item["Response"] = "1";
            }
            else {
                item["Response"] = "0";
            }
        }
        if (QuestionType == "Smile") {
            if ($('#imgSmile_' + QuestionId + '_3').hasClass("clsSmilechecked")) {
                item["Response"] = "3";
            }
            else if ($('#imgSmile_' + QuestionId + '_2').hasClass("clsSmilechecked")) {
                item["Response"] = "2";
            }
            else {
                item["Response"] = "1";
            }
        }
        if (QuestionType == "RadioQuestion") {
            if ($('#chkRadio_' + QuestionId + '_Yes').is(':checked')) {
                item["Response"] = "yes";
            }
            else {
                item["Response"] = "No";
            }
        }
        if (QuestionType == "Text") {
            item["Response"] = $("#txtarea_" + QuestionId + "").val();
        }
        lstQUestion.push(item);
    });
    var objdata = {
        customerName: Customer_name,
        customerEmail: Customer_email,
        customerMobile: Customer_mobile,
        BranchId: $('#hdnBranchId').val(),
        questionList: lstQUestion,
    }
    debugger;
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsViewNew/PostFeedback",
        success: function (result) {
            if (result.Message == "Success") {
                debugger;
                $("#order-feedback").modal('hide');

                $("#alertTitle").html("");
                $("#alertMessage").html("Feedback submitted successfully");
                $("#alertModal").modal();
            }
            else {
                $("#alertTitle").html("");
                $("#alertMessage").html("Feedback submitted Not successfully, Please try again.");
                $("#alertModal").modal();
            }
        }
    });
}
function OnItemClickShowPopup(itemid, HID) {
    debugger;
    selectedItemid = itemid;
    selectedHID = HID;
    $('#divMainItemDetails').show();

    $('#hdnSelectedItemid').val(itemid);
    $('#hdnSelectedHID').val(HID);
    var itemUniqueId = 0;
    $.each(CartDetails, function (i, obj) {
        itemUniqueId = itemUniqueId < parseInt(obj.UID) ? parseInt(obj.UID) : itemUniqueId;
    })
    $('#hdnSelectedUID').val(itemUniqueId + 1);

    $('#divitemDetailsItemNameTitle').text($('#hdnITEM_NAME_' + itemid).val().trim());
    $('#divitemDetailsItemName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    //$('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
    //$('#divitemDetailsItemName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    debugger;
    if ($('#hdnItem_VideoNAME_' + itemid).val().trim() != "") {
        $('#itemDetailsItemImage').removeClass("d-block");
        $('#itemDetailsItemImage').hide();
        $('#itemDetailsItemVideo').show();
        if (typeof hideItemImageSlider === 'function') { hideItemImageSlider(); }
        $('#itemVideoImage').attr("poster", "../../images/" + $('#hdnItem_IMAGENAME_' + itemid).val().trim() + "");
        $('#itemVideo').attr("src", "../Video/" + $('#hdnItem_VideoNAME_' + itemid).val().trim() + "");
        $("#itemVideoImage")[0].load();
        $('#itemVideoImage').trigger('pause');
    }
    else {
        $('#itemDetailsItemVideo').hide();
        $('#itemDetailsItemImage').show();
        $('#itemDetailsItemImage').css("display", "block !important;");
        $('#itemDetailsItemImage').attr("src", "../../images/" + $('#hdnItem_IMAGENAME_' + itemid).val().trim() + "");
        if (typeof loadItemImageSlider === 'function') { loadItemImageSlider(itemid, $('#hdnItem_IMAGENAME_' + itemid).val().trim()); }
    }
    $('#divitemDetailsIngredient').html($('#hdnItemINGREDIENT_' + itemid).val().trim());
    $('#itemdetMaindivPrice').html(round($('#hdnItem_PRICE_' + itemid).val().trim(), decimalPlace).toFixed(decimalPlace));
    $('#divitemDetailsPriceCurrcode').html(selectedCurrency + '. ');
    $('#divitemDetailsPrice').html(round($('#hdnItem_PRICE_' + itemid).val().trim(), decimalPlace).toFixed(decimalPlace));
    $('#divitemDetailsTotalPrice').html(round(0, decimalPlace).toFixed(decimalPlace));
    $('#txtItemDetailsItemCartCount').html("0");
    $('#divExtraitemDetailsPrice').html(round(0, decimalPlace).toFixed(decimalPlace));
    $('#lblItemDetailsUnitPriceCurr').html(selectedCurrency + '. ');
    $('#lblItemDetailsExtraPriceCurr').html(selectedCurrency + '. ');
    $('#lblItemDetailsTotalPriceCurr').html(selectedCurrency + '. ');

    var selectedItemQty = 0;
    if ($('#hdnIsCartVisible').val() == "1") {
        var strbutton = '';
        strbutton += '<a href="#" class="btn btn-primary icon-btn divAddMinuseItembtn" onclick="MinusecardclickNew(0,' + itemid + ',' + HID + ',0);">' +
            '<i class="fa fa-minus" aria-hidden="true"></i>' +
            '</a>' +
            '<input id="lblItemInfoQty" disabled class="form-control divAddMinuseItembtn" type="text" name="" value="' + selectedItemQty + '">' +
            ' <a href="#" onclick="addItemclickNew(0,' + itemid + ',' + HID + ',0,0);" class="btn btn-primary icon-btn divAddMinuseItembtn">' +
            '<i class="fa fa-plus" aria-hidden="true"></i>' +
            '</a>';

        strbutton += '<a href="#" onclick="addItemclick(0,' + itemid + ',' + HID + ',0,0);" class="btn-primary d-flex item-select-block divAddtocartButton" style="display:none;padding:10px;margin-left:10px;">' +
            '<i class="fa fa-shopping-cart" aria-hidden="true" style="margin-right: 7px;"></i>Add' +
            '</a>';

        $('#btnDetailsViewAdditemContainer').html(strbutton);
    }
    debugger;
    BindItemExtraItemsAndCommentsAndChoice(itemid);
    UpdateItemDetailsPrices(itemid, $('#hdnSelectedUID').val());
    $('#itemVideoImage').trigger('pause');
    if ($('#hdnIsCartVisible').val() == '1')
    {
        //$('#divItemDetailsViewPriceInfo').show();
        $('#divItemDetailsViewPriceInfo').css("display", "block !important;");
    }
    else {
        //$('#divItemDetailsViewPriceInfo').hide();
        $('#divItemDetailsViewPriceInfo').css("display", "none !important;");
    }

    //Bind Allergens
    // filter item wise allergen List
    debugger;
    if ($('#hdnIsShowAllergen').val() == "1") {
        allergenList = ItemAllergenslst.filter(function (entry) {
            return entry.itemId === itemid;
        });
        var strAllergens = "";
        $.each(allergenList, function (i, allergen) {
            var allergenName = "";
            if ($('#selectedLang').val() == "EN") {
                allergenName = allergen.allergenName;
            }
            else {
                allergenName = allergen.allergenNameArabic;
            }

            strAllergens += '<li class="media">' +
                '<span class="media-img mr-2">' +
                '<img src="../../allergenImages/' + allergen.image + '" height="20px" width="20px" alt="" onerror="this.style.display=\'none\'">' +
                '</span>' +
                '<div class="media-body">' + allergenName + '</div>' +
                '</li>';
            //'<svg height="512" viewBox="0 0 64 64" width="512" xmlns="http://www.w3.org/2000/svg"><g id="Soy"><path d="m63.31 27.35c-.36 4.68-2.45 9.14-9.19 12.43-2.77 8.13-9.12 12.95-17.13 12.95h-.01a20.24475 20.24475 0 0 1 -2.88-.21 19.90642 19.90642 0 0 1 -11.54 3.65 26.01508 26.01508 0 0 1 -13.59-4.24 14.24985 14.24985 0 0 0 9.19 7.75 17.96243 17.96243 0 0 0 5.16.76 16.96735 16.96735 0 0 0 12.05-4.82 18.8959 18.8959 0 0 0 14.5-2.8 14.55588 14.55588 0 0 0 6.03-9.56c3.86-1.55 6.37-4.02 7.46-7.35a15.19227 15.19227 0 0 0 -.05-8.56z" /><path d="m48.90234 33.38672c1.80274-.24707 4.68067-2.83692 4.98243-4.93555a1.9324 1.9324 0 0 0 -1.418-2.10156 2.20727 2.20727 0 0 0 -.666-.10352 2.06113 2.06113 0 0 0 -1.88277 1.29791 4.76922 4.76922 0 0 1 -1.97363 1.94238 1.92221 1.92221 0 0 0 -1.21582 2.37988 2.078 2.078 0 0 0 2.17379 1.52046z" /><path d="m33.59961 50.41113c8.83594 1.61719 16.1709-3.07617 18.88281-12.07422 8.95507-4.02539 9.28906-9.85644 8.751-15.52343l2.02734-5.166a2.213 2.213 0 0 0 -1.4414-2.92773l-.65336-.19045a2.78768 2.78768 0 0 0 -3.1211 1.13281l-2.8623 4.2666c-8.23828 1.24317-13.24121 5.09961-14.88379 11.4707-6.3584-.43457-10.98389 2.2334-12.65528 7.26172-8.99365-1.82324-14.71386.86719-19.58691 9.124a1 1 0 0 0 .28369 1.32422c4.76465 3.37207 9.62158 5.06445 14.21582 5.06445a18.09944 18.09944 0 0 0 11.04348-3.76267zm13.46-22.71777a2.81892 2.81892 0 0 0 1.0791-1.0625 4.047 4.047 0 0 1 4.94429-2.18359 3.9307 3.9307 0 0 1 2.78028 4.30173c-.44433 3.082-4.11914 6.27539-6.70215 6.6211l-.01465.002a3.91205 3.91205 0 0 1 -.46386.02734 4.075 4.075 0 0 1 -3.8711-2.96191 3.93007 3.93007 0 0 1 2.24805-4.74417zm-11.749 9.86133a3.17818 3.17818 0 0 0 1.47851-.8418 4.27568 4.27568 0 0 1 5.70508-.88965 4.195 4.195 0 0 1 1.68164 5.2002c-1.23144 2.87207-5.4043 5.06347-8.22265 5.06347a4.82191 4.82191 0 0 1 -.6045-.03613l-.01562-.00293a4.32772 4.32772 0 0 1 -3.65479-4.22265 4.19806 4.19806 0 0 1 3.63227-4.27051zm-18.30524 11.88281-.01123-.00879a4.2037 4.2037 0 0 1 -1.0498-5.32519 4.13693 4.13693 0 0 1 5.20366-1.86817 3.11918 3.11918 0 0 0 1.65185.00781 4.251 4.251 0 0 1 5.30074 2.04784 4.07813 4.07813 0 0 1 -1.148 5.19628 8.27458 8.27458 0 0 1 -4.832 1.334 8.95389 8.95389 0 0 1 -5.11522-1.38378z" /><path d="m23.41357 44.14648a5.11605 5.11605 0 0 1 -2.89794-.01367 2.17051 2.17051 0 0 0 -2.8086.916 2.21734 2.21734 0 0 0 .51221 2.7998c1.55713 1.17188 5.72021 1.38379 7.55224.02442a2.07906 2.07906 0 0 0 .54444-2.67871 2.22912 2.22912 0 0 0 -2.90235-1.04784z" /><path d="m35.6123 44.06738c1.99415.248 5.80665-1.69043 6.73047-3.84375a2.19727 2.19727 0 0 0 -.93652-2.72265 2.302 2.302 0 0 0 -3.13281.55175 5.17911 5.17911 0 0 1 -2.56739 1.4629 2.18074 2.18074 0 0 0 -2.02832 2.2539 2.34118 2.34118 0 0 0 1.93457 2.29785z" /><path d="m22.68 36.12a24.433 24.433 0 0 1 3.72.29c2.17-4.47 6.6-7.02 12.44-7.06 1.62-4.5 5.61-9.56 15.16-11.25l2.2-3.28c-.03-.78-.09-1.57-.16-2.34l2.22-5.66a2.15624 2.15624 0 0 0 -1.4-2.86l-.99-.29a2.695 2.695 0 0 0 -3.03 1.1l-3.15 4.7c-8.81 1.32-14.14 5.44-15.87 12.26-6.8-.49-11.75 2.36-13.52 7.75-8.93-1.82-14.88.57-19.76 7.9a3.10179 3.10179 0 0 0 .93 4.3 30.27111 30.27111 0 0 0 6.21 2.98c4.02-5.82 8.84-8.54 15-8.54zm-13.14924-.84266c-2.54443.73731-4.15185 3.60743-4.168 3.63575a.9996.9996 0 1 1 -1.751-.96485c.2041-.37011 2.08789-3.64355 5.3623-4.59277a1.00043 1.00043 0 0 1 .55664 1.92187z" /></g></svg>' +
        });

        $('#ulItemsAllergensList').html(strAllergens);

        if (allergenList.length > 0) {
            $('#divItemDetailsAllergen').show();
        }
        else {
            $('#divItemDetailsAllergen').hide();
        }
    }


    //var modal = document.getElementById("itemDetailModal");
    //modal.style.display = "block";
}
function round(value, exp) {
    // one decimal round
    if (exp == 1) {
        return (Math.round(value * 10) / 10);
    }
    // Two decimal round
    if (exp == 2) {
        return (Math.round(value * 100) / 100);
    }
    // Three decimal round
    if (exp == 3) {
        return (Math.round(value * 1000) / 1000);
    }
    // Four decimal round
    if (exp == 4) {
        return (Math.round(value * 10000) / 10000);
    }
    // Zero decimal round
    else {
        return (Math.round(value));
    }
}