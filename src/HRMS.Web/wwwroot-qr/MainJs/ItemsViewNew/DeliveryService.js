

var selectedClass = "active";

//lable bind dynamic language
var lblDSArea = 'Area';
var lblDSBlock = 'Block';
var lblDSStreet = 'Street';
var lblDSLane = 'Lane';
var lblADLandmark = 'Landmark';
var lblDSBuilding = 'Building';
var lblDSFloor = 'Floor';
var lblDSFlat = 'Flat';
var lblDSDiffrentLactionText = 'Delever to Different Location';
var lblDSChooesLocationText = 'Chooes Location the Map';
var lblASAP = 'ASAP';
var TodayLable = "Today";
var selectedDate;

var svgCurrenthtml = '<svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-current-location" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
    '<path stroke="none" d="M0 0h24v24H0z" fill="none" />' +
    '<circle cx="12" cy="12" r="3" />' +
    '<circle cx="12" cy="12" r="8" />' +
    '<line x1="12" y1="2" x2="12" y2="4" />' +
    '<line x1="12" y1="20" x2="12" y2="22" />' +
    '<line x1="20" y1="12" x2="22" y2="12" />' +
    '<line x1="2" y1="12" x2="4" y2="12" />' +
    '</svg>';
var svgHomehtml = '<svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-home-2" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
    '<path stroke="none" d="M0 0h24v24H0z" fill="none"/>' +
    '<polyline points ="5 12 3 12 12 3 21 12 19 12"/>' +
    '<path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-7"/>' +
    '<rect x="10" y="12" width ="4" height ="4"/> ' +
    '</svg>';

var svgBuildinghtml = '<svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-building" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
    '<path stroke="none" d="M0 0h24v24H0z" fill="none" />' +
    '<line x1="3" y1="21" x2="21" y2="21"/>' +
    '<line x1="9" y1="8" x2="10" y2="8"/>' +
    '<line x1="9" y1="12" x2="10" y2="12"/>' +
    '<line x1="9" y1="16" x2="10" y2="16"/>' +
    '<line x1="14" y1="8" x2="15" y2="8"/>' +
    '<line x1="14" y1="12" x2="15" y2="12"/>' +
    '<line x1="14" y1="16" x2="15" y2="16"/>' +
    '<path d="M5 21v-16a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v16"/>' +
    '</svg>';
var svgOfficehtml = '<svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-briefcase" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
    '<path stroke="none" d="M0 0h24v24H0z" fill="none" />' +
    '<rect x = "3" y = "7" width = "18" height = "13" rx = "2" /> ' +
    '<path d = "M8 7v-2a2 2 0 0 1 2 -2h4a2 2 0 0 1 2 2v2" /> ' +
    '<line x1 = "12" y1 = "12" x2 = "12" y2 = "12.01" /> ' +
    '<path d = "M3 13a20 20 0 0 0 18 0" /> ' +
    '</svg >';
var svgDiffrenthtml = '<svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-map-pin" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
    '<path stroke="none" d="M0 0h24v24H0z" fill="none" />' +
    '<circle cx="12" cy="11" r="3" />' +
    '<path d="M17.657 16.657l-4.243 4.243a2 2 0 0 1 -2.827 0l-4.244 -4.243a8 8 0 1 1 11.314 0z" />' +
    '</svg>';


var dateToday = new Date();


$('#txtDeliveryServiceDate').datepicker({
    //inline: true,
    autoclose: true,
    format: "dd M yyyy",
    minDate: dateToday,
    //startDate: "+0d",
    startDate: dateToday,
    //setDate: null,
    //rtl: true,
    ignoreReadonly: true,
}).change(deliverydateChanged).on('changeDate', deliverydateChanged);

function deliverydateChanged(ev) {
    debugger;
    $("#ISDeliveryDateToday").val("0");
    selectedDate = $("#txtDeliveryServiceDate").datepicker("getDate");
    BindTimeSlot(selectedDate, 0, "DeliveryTab");
}

$('#txtDeliveryPickupServiceDate').datepicker({
    //inline: true,
    autoclose: true,
    format: "dd M yyyy",
    minDate: dateToday,
    //startDate: "+0d",
    startDate: dateToday,
    //setDate: null,
    //rtl: true,
    ignoreReadonly: true,
}).change(pickupdateChanged).on('changeDate', pickupdateChanged);

function pickupdateChanged(ev) {
    debugger;
    // deliverydateChanged() (above) sets this when the Delivery tab's date
    // is picked; this handler is its Pickup-tab counterpart and was missing
    // the same line, so #ISDeliveryDateToday stayed "1" (Today) no matter
    // what pickup date was actually chosen. setDeliveryServiceCookies() and
    // BindDeliveryServiceFromCookies() below both trust this flag.
    $("#ISDeliveryDateToday").val("0");
    selectedDate = $("#txtDeliveryPickupServiceDate").datepicker("getDate");
    BindTimeSlot(selectedDate, 0, "PickupTab");
}

function customerInfoNext() {
    debugger;

    if (!$("#formCustomerInfo").hasClass("was-validated")) {
        $("#formCustomerInfo").addClass("was-validated");
    }
    var regex = /^([a-zA-Z0-9_\.\-\+])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
    var flgError = 0;
    if (!$('#formCustomerInfo').valid()) {
        flgError = 1;
    }
    //if (!regex.test($('#txtCustomerEmailnew').val())) {
    //    flgError = 1;
    //    alert("Invalid Email");
    //}

    if (!$('#txtCustomerPhoneNumber').val().length > 8) {
        flgError = 1;
        alert("Invalid Number");
    }

    if (flgError == 0) {

        //direct display payment view if branch id exsit in Query string and webconfig IsDeliveryEnable false(means only pickup)
        if (parseInt($('#hdnBranchId').val()) > 0 && $('#hdnIsDeliveryEnable').val() == "false") {
            //DeliveryServiceNext();
            DeliveryAddressNext();
        }
        else if (parseInt($('#hdnBranchId').val()) > 0 && $('#hdnIsFromWaiterLogin').val() == "true") {
            //DeliveryServiceNext();
            DeliveryAddressNext();
        }
        else {
            $('#divCategoryList').hide();
            $('#divMainItemDetails').hide();
            $('#divCartView').hide();
            $('#divQRCodeMain').hide();
            $('#TrackingOrder').hide();
            $('#divReservation').hide();
            $('#divReservationConfirm').hide();

            //checkout views list
            $('#divCustomerInfo').hide();
            $('#divDeliveryService').show();
            $('#divDeliveryAddress').hide();
            $('#divPaymentView').hide();
            $('#divOrderConfirmView').hide();

            BindDeliveryServiceData();

            //set customer info cookies
            seCustomerInfoCookies();

            // set default 
            if ($('#selDeliveryTimeSlot').find(":selected").text() == "") {
                deliverydateChanged(null)
            }
        }
    }
    else {
        $('#formCustomerInfo').addClass("was-validated");
    }
    if ($('#hdnIsFromWaiterLogin').val() == "true") {
        $('#pickup').click();
        DeliveryAddressNext();
    }
}

function seCustomerInfoCookies() {
    debugger;
    if (CustomerDetails != null) {
        CustomerDetails["CustomerFullName"] = $('#txtCustomerFullname').val();
        CustomerDetails["PhoneNumber"] = $('#txtCustomerPhoneNumber').val();
        CustomerDetails["EmailId"] = $('#txtCustomerEmailnew').val();
        CustomerDetails["TableNumber"] = $('#txtTableNumber').val();
        CustomerDetails["NumberofGuests"] = $('#txtNumberofGuests').val();
        CustomerDetails["ReOrder"] = $('#chkReOrder').is(':checked');
        CustomerDetails["TakeAway"] = $('#chkTakeAway').is(':checked');

        var val = JSON.stringify(CustomerDetails);
        createCookie("CustomerDetailsCookie", val, 365);
    }
}
function BindDeliveryServiceFromCookies() {
    debugger;
    if (CustomerDetails != null) {

        if (CustomerDetails["DeliveryType"] == "Delivery") {

            //hide pickup tab content and deselect
            $("#pickup").removeClass("active");
            $("#nav-pickup").removeClass("show");
            $("#nav-pickup").removeClass("active");


            if (!($("#delivery").hasClass("active"))) {
                $("#delivery").addClass("active");
                $("#nav-delivery").removeClass("show");
                $("#nav-delivery").removeClass("active");
            }

            debugger;
            if (CustomerDetails["DeliveryDate"] != "" && CustomerDetails["DeliveryDate"] != null) {
                if (CustomerDetails["ISDeliveryDateToday"] == "1") {
                    $("#txtDeliveryServiceDate").val(TodayLable);
                }
                else {
                    $("#txtDeliveryServiceDate").val(CustomerDetails["DeliveryDate"]);
                }

                var dt = $("#txtDeliveryServiceDate").datepicker("getDate");
                BindTimeSlot(selectedDate, 0, "DeliveryTab");
            }
            if (CustomerDetails["DeliveryTime"] != "" && CustomerDetails["DeliveryTime"] != null) {
                $("#selDeliveryTimeSlot").val(CustomerDetails["DeliveryTime"]);
                $('#selDeliveryTimeSlot').selectpicker("refresh");
            }


            if (CustomerDetails["SelectedAddressIndex"] != "0") {
                $('.clSelectedDeliveryAddress').each(function (index) {
                    $(this).removeClass("active");
                });
                $("#addressId_" + CustomerDetails["SelectedAddressIndex"] + "").addClass("active");
            }


        }
        else {

            //hide Delivery content and deselect
            $("#delivery").removeClass("active");
            $("#nav-delivery").removeClass("show");
            $("#nav-delivery").removeClass("active");

            if (!($("#pickup").hasClass("active"))) {
                $("#pickup").addClass("active");
                $("#nav-pickup").addClass("show");
                $("#nav-pickup").addClass("active");
            }

            if (CustomerDetails["DeliveryDate"] != "" && CustomerDetails["DeliveryDate"] != null) {
                //$("#txtDeliveryPickupServiceDate").val(CustomerDetails["DeliveryDate"]);
                if (CustomerDetails["ISDeliveryDateToday"] == "1") {
                    $("#txtDeliveryPickupServiceDate").val(TodayLable);
                }
                else {
                    $("#txtDeliveryPickupServiceDate").val(CustomerDetails["DeliveryDate"]);
                }

                var dt = $("#txtDeliveryPickupServiceDate").datepicker("getDate");
                BindTimeSlot(selectedDate, 0, "PickupTab");
            }
            if (CustomerDetails["DeliveryTime"] != "" && CustomerDetails["DeliveryTime"] != null) {
                $("#selPickupTimeSlot").val(CustomerDetails["DeliveryTime"]);
                $('#selPickupTimeSlot').selectpicker("refresh");
            }
        }
    }
}

function DeliveryServicePrevious() {
    $('#divCategoryList').hide();
    $('#divMainItemDetails').hide();
    $('#divCartView').hide();
    $('#divQRCodeMain').hide();
    $('#TrackingOrder').hide();
    $('#divReservation').hide();
    $('#divReservationConfirm').hide();

    //checkout views list
    $('#divCustomerInfo').show();
    $('#divDeliveryService').hide();
    $('#divDeliveryAddress').hide();
    $('#divPaymentView').hide();
    $('#divOrderConfirmView').hide();


    var areaid = 0;
    var selectedAddressIndex = 2;
    if ($('#pickup').hasClass("active")) {
        debugger;
        redirectOnPayment = 1;
        $('.clrbranchList').each(function (index) {
            if ($(this).hasClass("active")) {
                //Custinfo["BranchID"] = parseInt($(this).attr("data-brId"));
                areaid = parseInt($(this).attr("data-arId"));
            }
        });
    }
    else {
        $('.clSelectedDeliveryAddress').each(function (index) {
            if ($(this).hasClass("active")) {
                selectedAddressIndex = parseInt($(this).attr("data-val"));
            }
        });
        if (selectedAddressIndex < 2) {
            redirectOnPayment = 1;
            if (customerAddresses != null) {
                var data = customerAddresses[selectedAddressIndex];
                areaid = data.AreaID;
            }
            //bindSelectedAddressValue(selectedAddressIndex);
        }

    }
    debugger;
    //set customer info cookies
    setDeliveryServiceCookies(areaid, selectedAddressIndex);

    $("#formCustomerInfo").removeClass("was-validated");
}

function DeliveryServiceNext() {
    debugger;
    if ($('#pickup').hasClass("active") && $('#selPickupTimeSlot').val() == null) {
        alert("Select delivery time");
        return false;
    } else if ($('#selDeliveryTimeSlot').val() == null) {
        alert("Select delivery time");
        return false;
    }

    $('#divCategoryList').hide();
    $('#divMainItemDetails').hide();
    $('#divCartView').hide();
    $('#divQRCodeMain').hide();
    $('#TrackingOrder').hide();
    $('#divReservation').hide();
    $('#divReservationConfirm').hide();

    //checkout views list
    $('#divCustomerInfo').hide();
    $('#divDeliveryService').hide();
    $('#divDeliveryAddress').hide();
    $('#divPaymentView').hide();
    $('#divOrderConfirmView').hide();

    var redirectOnPayment = 0;
    var areaid = 0;
    var selectedAddressIndex = 2;
    if ($('#pickup').hasClass("active")) {
        debugger;
        redirectOnPayment = 1;
        $('.clrbranchList').each(function (index) {
            if ($(this).hasClass("active")) {
                //Custinfo["BranchID"] = parseInt($(this).attr("data-brId"));
                areaid = parseInt($(this).attr("data-arId"));
            }
        });
    }
    else {
        $('.clSelectedDeliveryAddress').each(function (index) {
            if ($(this).hasClass("active")) {
                selectedAddressIndex = parseInt($(this).attr("data-val"));
            }
        });
        if (selectedAddressIndex < 2) {
            redirectOnPayment = 1;
            if (customerAddresses != null) {
                var data = customerAddresses[selectedAddressIndex];
                areaid = data.AreaID;
            }
            //bindSelectedAddressValue(selectedAddressIndex);
        }

    }




    if (redirectOnPayment == 0) {
        $('#divDeliveryAddress').show();
        createCustomerAddressMap(null);
        CustomerAddressMap.invalidateSize();
        debugger;
        BindDeliveryAddressFromCookies();
        $("#formDeliveryAddress").removeClass("was-validated");
    }
    else {
        var deliverycharges = 0.000;
        $("#AddressArea option").filter(function () {
            if (parseInt($(this).val()) == parseInt(areaid) && parseInt(areaid) > 0) {
                deliverycharges = round($(this).attr('data-val'), decimalPlace).toFixed(decimalPlace);
            }
        });

        debugger;
        $('#lblPaymentDeliveryChargeCurrency').html(selectedCurrency + ". ");
        $('#lblPaymentDeliveryCharge').html(round(deliverycharges, decimalPlace).toFixed(decimalPlace));

        $('#lblPaymentDiscountChargeCurrency').html(selectedCurrency + ". ");
        //$('#lblPaymentDiscountCharge').html(0.000);

        var finalamount = parseFloat(deliverycharges) + parseFloat($('#lblPaymentBillAmountVal').html());
        $('#lblPaymentNetAmountCurrency').html(selectedCurrency + ". ");
        $('#lblPaymentNetAmountVal').html(round(finalamount, decimalPlace).toFixed(decimalPlace));
        $('#lblfinalAmount').html(round(finalamount, decimalPlace).toFixed(decimalPlace));

        //var final = deliverycharges+ 
        onViewDetailsItemsOnPaymentView();
        $('#divPaymentView').show();
        FillCustinfoAndAddressInfo();
    }
    //if (!($('#btnCashPayment').hasClass("activePayment"))) {
    //    $('#btnCashPayment').addClass('activePayment');
    //}
    //$('#selectedPayementType').html('Cash on delivery');
    $('.paymenttype').each(function (index) {
        $(this).removeClass('activePayment');
    });
    if ($('#selectedPayementType').html() == "KNET") {
        $('#btnKnetPayment').addClass('activePayment');
    }
    else {
        $('#btnCashPayment').addClass('activePayment');
    }

    debugger;
    //set customer info cookies
    setDeliveryServiceCookies(areaid, selectedAddressIndex);
}

function setDeliveryServiceCookies(areaid, selectedAddressIndex) {

    if (CustomerDetails != null) {
        CustomerDetails["AreaId"] = areaid;



        CustomerDetails["DeliveryTime"] = $("#selDeliveryTimeSlot").val();
        CustomerDetails["SelectedAddressIndex"] = selectedAddressIndex;

        if ($("#delivery").hasClass("active")) {
            CustomerDetails["DeliveryType"] = "Delivery";

            if ($("#ISDeliveryDateToday").val() == "1") {
                CustomerDetails["ISDeliveryDateToday"] = "1";
                //CustomerDetails["DeliveryDate"] = $("#txtDeliveryServiceDate").val();
                CustomerDetails["DeliveryDate"] = TodayLable;
            }
            else {
                CustomerDetails["ISDeliveryDateToday"] = "0";
                CustomerDetails["DeliveryDate"] = $("#txtDeliveryServiceDate").val();
            }

        }
        else {
            CustomerDetails["DeliveryType"] = "Pickup";

            if ($("#ISDeliveryDateToday").val() == "1") {
                CustomerDetails["ISDeliveryDateToday"] = "1";
                //CustomerDetails["DeliveryDate"] = $("#txtDeliveryServiceDate").val();
                CustomerDetails["DeliveryDate"] = TodayLable;
            }
            else {
                CustomerDetails["ISDeliveryDateToday"] = "0";
                CustomerDetails["DeliveryDate"] = $("#txtDeliveryPickupServiceDate").val();
            }
        }


        var val = JSON.stringify(CustomerDetails);
        createCookie("CustomerDetailsCookie", val, 365);
    }
}

/*
 * options.silent - true when this is a background refresh rather than the
 * customer actually standing on the Delivery/Pickup step.
 *
 * Why it exists: selectLanguage() (BindCartDetails.js) calls this on every
 * EN <-> AR toggle so the address/branch lists re-render in the new language.
 * Any server-side failure here used to open the modal, so switching language
 * anywhere in the menu popped "Service Not Connected, Please Contact Your
 * Manager." even though the customer was nowhere near checkout. A background
 * refresh now logs the failure to the console and leaves the lists empty; the
 * same failure still shows the modal from customerInfoNext(), where it really
 * does block the customer.
 */
function BindDeliveryServiceData(options) {
    var silent = !!(options && options.silent);

    // Single place that decides how a failed lookup is surfaced.
    function reportFailure(detail) {
        if (window.console) {
            console.error("GetDeliveryServiceData failed" + (detail ? ": " + detail : ""));
        }
        if (silent) { return; }

        // Detail is populated only when custom errors are off, so real
        // customers still see just the plain sentence.
        var msg = "Service Not Connected, Please Contact Your Manager.";
        if (detail) {
            msg += '<br/><small style="color:#888;">' + detail + '</small>';
        }
        $("#alertTitle").html("");
        $("#alertMessage").html(msg);
        $("#alertModal").modal();
    }

    // Both binders overwrite these containers wholesale on success, so there is
    // nothing to gain from blanking them first - and on a silent refresh that
    // fails it would wipe lists the customer is already looking at.
    if (!silent) {
        $('#ulListAddresses').html("");
        $('#divBranchListPickup').html("");
    }
    var webserviceUrl = $('#hdnCallcWebServiceUrl').val();
    // BrandID scopes the pickup branch list. Without it a customer who scanned
    // one restaurant's QR code would be offered every brand's branches.
    var obj = {
        Mobile: $('#txtCustomerPhoneNumber').val(),
        Email: $('#txtCustomerEmailnew').val(),
        BrandID: parseInt($('#hdnbrandId').val()) || 0
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsViewNew/GetDeliveryServiceData",


        //type: "GET",
        //data: JSON.stringify(obj),
        ////data: obj,
        //contentType: "application/json; charset=utf-8",
        ////dataType: "json",
        //cache: false,
        //url: webserviceUrl + "/DmToCallCenterServices/GetCustomerAddresses",
        success: function (result) {
            debugger;
            if (result && result.Message == "Error,Contact Your Manager.") {
                // The server threw - almost always sp_GetDeliveryServiceData is
                // missing, or failed to compile so it was never created.
                reportFailure(result.Detail);
                return;
            }

            // On success the action returns a JSON *string*, so `result` here is
            // a string and has to be parsed once more. A malformed payload is a
            // failure like any other rather than an unhandled exception that
            // would leave the toggle half-applied.
            try {
                result = (typeof result === "string") ? JSON.parse(result) : result;
            }
            catch (e) {
                reportFailure(e.message);
                return;
            }

            if (result.Message == "Success") {

                debugger;
                if (result.dtAddressList != "") {
                    customerAddresses = JSON.parse(result.dtAddressList);
                }
                else {
                    customerAddresses = null;
                }


                branchList = JSON.parse(result.dtBranchList);
                BindCustomerAddressList(customerAddresses);
                BindBranchList(branchList);
                BindTimeSlot($('#txtSelectedDate').val(), 1, "DeliveryTab");

                //BindDeliveryServiceFromCookies
                //BindDeliveryServiceFromCookies();

            }
            else {
                reportFailure(result.Message);
            }

        },
        // Previously absent: an HTTP-level failure (500 page, timeout, session
        // lost) did nothing at all, so the Delivery step just sat there empty.
        error: function (xhr, textStatus) {
            reportFailure(xhr && xhr.status ? ("HTTP " + xhr.status + " " + textStatus) : textStatus);
        }
    });
}

function BindCustomerAddressList(customerAddresses) {
    debugger;
    var strbind = "";
    var cnt = 0;
    if (customerAddresses != null) {
        $.each(customerAddresses, function (i, obj) {
            if (cnt < 2) {
                var svg;
                if (cnt == 0) {
                    svg = svgHomehtml;
                    selectedClass = "active";
                }
                else if (cnt == 1) {
                    svg = svgBuildinghtml;
                    selectedClass = "";
                }

                var area = obj.AreaName.trim().length > 0 ? "" + lblDSArea + ": " + obj.AreaName.trim() + ", " : "";
                var block = obj.Block.trim() != null ? "" + lblDSBlock + ": " + obj.Block.trim() + ", " : "";

                var firstline = area + block;

                var Street = obj.Street.trim() != null ? "" + lblDSStreet + ": " + obj.Street.trim() + ", " : "";
                var lane = obj.Lane.trim() != null ? "" + lblDSLane + ": " + obj.Lane.trim() + ", " : "";
                var building = obj.Building.trim() != null ? "" + lblDSBuilding + ": " + obj.Building.trim() + ", " : "";
                var floor = obj.Floor.trim() != null ? "" + lblDSFloor + ": " + obj.Floor.trim() + ", " : "";
                var flat = obj.flat.trim() != null ? "" + lblDSFlat + ": " + obj.flat.trim() + ", " : "";

                var secondline = Street + lane + building + floor + flat;
                //cartcount = cartcount + obj.Q;
                strbind += '<li id="addressId_' + cnt + '" data-val="' + cnt + '" class="media clSelectedDeliveryAddress ' + selectedClass + '" onclick="deliveryAddressSelect(this,' + cnt + ')">' +
                    '<span class="icon-outer">' + svg +
                    '</span >' +
                    '<div class="media-body pl-3 pr-3">' +
                    '<h4 class="mt-0 mb-1">' + firstline.slice(0, -2) + '</h4>' +
                    '<p>' + secondline.slice(0, -2) + '</p>' +
                    '</div>' +
                    '</li>';
            }
            cnt++;
        });
    }

    //var CurrentAddressDivHtml = '<li id="addressId_2" data-val="2"  class="media clSelectedDeliveryAddress " onclick="deliveryAddressSelect(this,' + 2 + ')">' +
    //    '<span class="icon-outer">' +
    //    svgCurrenthtml +
    //    '</span>' +
    //    '<div class="media-body pl-3 pr-3">' +
    //    '<h4 class="mt-0 mb-1">Delever to Current Location</h4>' +
    //    '<p>Enabal Device Location</p>' +
    //    '</div>' +
    //    '</li>';
    var DiffrentAddressDivHtml = '<li id="addressId_2" data-val="2"  class="media clSelectedDeliveryAddress " onclick="deliveryAddressSelect(this,' + 3 + ')">' +
        '<span class="icon-outer" >' +
        svgDiffrenthtml +
        '</span >' +
        '<div class="media-body pl-3 pr-3" > ' +
        '<h4 class="mt-0 mb-1"> ' + lblDSDiffrentLactionText + '</h4 > ' +
        '<p>' + lblDSChooesLocationText + '</p > ' +
        '</div>' +
        '</li>';

    $('#ulListAddresses').html(strbind + DiffrentAddressDivHtml);
}

function BindBranchList(branchList) {
    debugger;
    var strbind = "";
    var cnt = 0;

    // An empty pickup list used to render as a blank panel with a working Next
    // button, so the customer walked into a failure two screens later. Say it.
    if (!branchList || branchList.length === 0) {
        $('#divBranchListPickup').html(
            '<div class="alert alert-warning mb-0" style="font-size:13px;">'
            + 'No branch is available for pickup right now.</div>');
        return;
    }

    $.each(branchList, function (i, obj) {
        var AreaName = "";
        if ($('#selectedLang').val() == "EN") {
            AreaName = obj.AreaName;
        }
        else {
            AreaName = obj.AreaNameAra;
        }
        var branchname = $('#selectedLang').val() == "EN" ? obj.BranchName : obj.BranchNameAra;

        if (cnt == 0) {
            selectedClass = "active";
        }
        else if (cnt == 1) {
            selectedClass = "";
        }
        var area = AreaName.trim().length > 0 ? AreaName.trim() : "";

        //strbind += '<a data-brId="' + obj.BranchID + '" data-arId="' + obj.AreaID + '" data-arName="' + area +'" class="list-group-item list-group-item-action clrbranchList ' + selectedClass + '" onclick="pickupBranchSelect(this,' + obj.BranchID + ')">' +
        strbind += '<a data-brId="' + obj.BranchID + '" data-arId="1" data-arName="' + area + '" class="list-group-item list-group-item-action clrbranchList ' + selectedClass + '" onclick="pickupBranchSelect(this,' + obj.BranchID + ')">' +
            '<h4>' + branchname + '</h4>' +
            '<p>' + lblDSArea + " : " + area + '</p > ' +
            '</a>';
        cnt++;
    });
    $('#divBranchListPickup').html(strbind);
    debugger;
    if ($('#hdnIsDeliveryEnable').val() == "false") {
        $('#pickup').click();
        $('#pickup').click();
        if ($("#pickup").hasClass("active") == false) {
            $('#pickup').addClass("active");
        }
        $('#delivery').hide();
    }
    if ($('#hdnIsScheduleOrderEnabled').val() == "false") {
        $('#divPickupTimeSelection').hide();
    }
}

function BindTimeSlot(selectedDate, isFirstTimeLoad, selectedTab) {
    debugger;
    if (selectedDate == "Today") {
        selectedDate = new Date();
    }
    var objdata = {
        reservationDate: selectedDate,
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        async: false,
        url: "/ItemsViewNew/GetTimeSlot",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Mainstr = "";
                Mainstr += '<option value="' + 0 + '" data-value="ASAP">' + lblASAP + '</option>';
                var cntcat = 0;
                if (result.dtLabels != "") {
                    var objResult = JSON.parse(result.dtresult);
                    $.each(objResult, function (i, data) {
                        var slotName = "";
                        if ($('#selectedLang').val() == "EN") {
                            slotName = data.slotName;
                        }
                        else {
                            slotName = data.slotName;
                        }

                        Mainstr += '<option value="' + data.id + '" data-value="' + data.fromTime + '">' + slotName + '</option>';
                        //str = '<a id="rdSlot_' + data.id + '" data-value="' + data.id + '" class="times-zone rdSlot" onclick="onSlotclick(this);">' + slotName + '</a>';
                        cntcat = cntcat + 1;
                    });
                    debugger;
                    if (isFirstTimeLoad == 1) {
                        $('#selDeliveryTimeSlot').html(Mainstr);
                        $('#selDeliveryTimeSlot').selectpicker("refresh");

                        $('#selPickupTimeSlot').html(Mainstr);
                        $('#selPickupTimeSlot').selectpicker("refresh");
                    }
                    else {
                        if (selectedTab == "DeliveryTab") {
                            $('#selDeliveryTimeSlot').html(Mainstr);
                            $('#selDeliveryTimeSlot').selectpicker("refresh");
                        }
                        else {
                            $('#selPickupTimeSlot').html(Mainstr);
                            $('#selPickupTimeSlot').selectpicker("refresh");
                        }
                    }
                }
                else {
                    $('#selDeliveryTimeSlot').html(Mainstr);
                    $('#selDeliveryTimeSlot').selectpicker("refresh");

                    $('#selPickupTimeSlot').html(Mainstr);
                    $('#selPickupTimeSlot').selectpicker("refresh");
                }
                //ev.preventDefault();
                //$(".main-content").animate({ scrollTop: '+=350px' }, 600);
            }
            else {
                $("#alertTitle").html("");
                $("#alertMessage").html(msgerrorval);
                $("#alertModal").modal()
            }
        }
    });
}

function deliveryAddressSelect(obj, Index) {
    debugger;
    //remove selected order wise branch selection
    $('.clSelectedDeliveryAddress').each(function (index) {
        $(this).removeClass('active');
    });

    if (!$(obj).hasClass('active')) {
        $(obj).addClass('active');
    }
    //else {
    //    $(obj).removeClass('active');
    //}
}

function pickupBranchSelect(obj, BranchID) {
    debugger;
    //remove selected order wise branch selection
    $('.clrbranchList').each(function (index) {
        $(this).removeClass('active');
    });

    if (!$(obj).hasClass('active')) {
        $(obj).addClass('active');
    }
}

//function bindSelectedAddressValue(indexid) {
//    debugger;
//    if (customerAddresses != null) {

//    }
//}


