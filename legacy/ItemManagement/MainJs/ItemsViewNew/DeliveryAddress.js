function DeliveryAddressPrevious() {
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

    debugger;
    //set customer info cookies
    setDeliveryAddressCookies();
}

function DeliveryAddressNext() {
    debugger;
    var areaid = 0;
    if (!$("#formDeliveryAddress").hasClass("was-validated")) {
        $("#formDeliveryAddress").addClass("was-validated");
    }
    var flgerror = 0;
    if (!(parseInt($('#hdnBranchId').val()) > 0 && $('#hdnIsDeliveryEnable').val() == "false")) {
        if (!$('#formDeliveryAddress').valid()) {
            flgerror = 1;
            if ($('#AddressArea').val() == "") {
                var elmnt = document.getElementById("divDeliveryAddress");
                elmnt.scrollTop = 0;
            }
        }
        areaid = $('#AddressArea').val();
        $('#mainDivDeliveryInfo').show();
    }
    else {
        areaid = 1; // set as pickup
        $('#mainDivDeliveryInfo').hide();
    }

    debugger;
    if (flgerror == 0) {
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
        $('#divPaymentView').show();
        $('#divOrderConfirmView').hide();

        //$('#lblPaymentBillAmountVal').html("");
        //$('#hdnSubtotal').val(FinalTotal);
        //var redirectOnPayment = 0;

        var deliverycharges = 0.000;
        $("#AddressArea option").filter(function () {
            if (parseInt($(this).val()) == parseInt(areaid) && parseInt(areaid) > 0) {
                deliverycharges = round($(this).attr('data-val'), decimalPlace).toFixed(decimalPlace);
            }
        });
        $('#lblPaymentDeliveryChargeCurrency').html(selectedCurrency + ". ");
        $('#lblPaymentDeliveryCharge').html(round(deliverycharges, decimalPlace).toFixed(decimalPlace));

        $('#lblPaymentDiscountChargeCurrency').html(selectedCurrency + ". ");
        //$('#lblPaymentDiscountCharge').html(0.000);


        var finalamount = parseFloat(deliverycharges) + parseFloat($('#lblPaymentBillAmountVal').html());
        $('#lblPaymentNetAmountCurrency').html(selectedCurrency + ". ");
        $('#lblPaymentNetAmountVal').html(round(finalamount, decimalPlace).toFixed(decimalPlace));
        $('#lblfinalAmount').html(round(finalamount, decimalPlace).toFixed(decimalPlace));

        onViewDetailsItemsOnPaymentView();

        //bind address lables
        FillCustinfoAndAddressInfo();

        debugger;
        //set customer info cookies
        setDeliveryAddressCookies();
    }
}

function setDeliveryAddressCookies() {

    if (CustomerDetails != null) {
        //CustomerDetails["AreaId"] = areaid;
        //CustomerDetails["DeliveryDate"] = $("#txtDeliveryServiceDate").val();
        //CustomerDetails["DeliveryTime"] = $("#selDeliveryTimeSlot").val();
        //CustomerDetails["SelectedAddressIndex"] = selectedAddressIndex;

        //if ($("#delivery").hasClass("active")) {
        //    CustomerDetails["DeliveryType"] = "Delivery";
        //}
        //else {
        //    CustomerDetails["DeliveryType"] = "Pickup";
        //}

        if ($('#CustAddressHome').hasClass("active")) {
            CustomerDetails["DeliveryAddressType"] = "Home";
            CustomerDetails["Block"] = $('#txtHomeBlock').val();
            CustomerDetails["Street"] = $('#txtHomeStreet').val();
            CustomerDetails["Flat"] = $('#txtHomeFlat').val();
            CustomerDetails["AddressRemarks"] = $('#txtHouseLandmark').val();
            //Custinfo["Building"] = $('#Building').val();
        }

        else if ($('#CustAddressApartment').hasClass("active")) {
            CustomerDetails["DeliveryAddressType"] = "Apartment";
            CustomerDetails["Block"] = $('#txtApartmentBlock').val();
            CustomerDetails["Street"] = $('#txtApartmentStreet').val();
            CustomerDetails["Building"] = $('#txtApartmentBuilding').val();
            CustomerDetails["Floor"] = $('#txtApartmentFloor').val();
            CustomerDetails["Flat"] = $('#txtApartmentFlatNo').val();
            CustomerDetails["AddressRemarks"] = $('#txtApartmentLandmark').val();
        }
        else if ($('#CustAddressOffice').hasClass("active")) {
            CustomerDetails["DeliveryAddressType"] = "Office";
            CustomerDetails["Block"] = $('#txtOfficeBlock').val();
            CustomerDetails["Street"] = $('#txtOfficeStreet').val();
            CustomerDetails["Building"] = $('#txtOfficeBuilding').val();
            CustomerDetails["Floor"] = $('#txtOfficeFloor').val();
            CustomerDetails["Flat"] = $('#txtOfficeFlat').val();
            CustomerDetails["AddressRemarks"] = $('#txtOfficeLandmark').val();
        }

        CustomerDetails["Latitude"] = $('#hdnlat').val();
        CustomerDetails["Longitude"] = $('#hdnlong').val();
        /*CustomerDetails["BranchID"] = $('#hdnBranchId').val();*/


        //set areaid 
        if ($('#pickup').hasClass("active")) {
            $('.clrbranchList').each(function (index) {
                if ($(this).hasClass("active")) {
                    CustomerDetails["BranchID"] = parseInt($(this).attr("data-brId"));
                    CustomerDetails["AreaID"] = parseInt($(this).attr("data-arId"));
                    //Custinfo["BranchID"] = parseInt($(this).attr("data-brId"));
                    //Custinfo["AreaID"] = parseInt($(this).attr("data-arId"));
                    //areaName = $(this).attr("data-arName");
                }
            });
        }
        else {
            CustomerDetails["AreaID"] = $('#AddressArea').val();
        }



        var val = JSON.stringify(CustomerDetails);
        createCookie("CustomerDetailsCookie", val, 365);
    }
}

function BindDeliveryAddressFromCookies() {
    debugger;
    if (CustomerDetails != null) {

        if (CustomerDetails["DeliveryAddressType"] == "Home"
            || CustomerDetails["DeliveryAddressType"] == "Apartment"
            || CustomerDetails["DeliveryAddressType"] == "Office") {
            $('#CustAddressHome').removeClass("active");
            $('#CustAddressApartment').removeClass("active");
            $('#CustAddressOffice').removeClass("active");

            $('#nav-home').removeClass("active show");
            $('nav-apartment').addClass("active show");
            $('nav-office').addClass("active show");

        }


        if (CustomerDetails["DeliveryAddressType"] == "Home") {
            $('#CustAddressHome').addClass("active");
            $('#CustAddressHome').click();
            $('#nav-home').addClass("active show");

            $('#txtHomeBlock').val(CustomerDetails["Block"]);
            $('#txtHomeStreet').val(CustomerDetails["Street"]);
            $('#txtHomeFlat').val(CustomerDetails["Flat"]);
            $('#txtHouseLandmark').val(CustomerDetails["AddressRemarks"]);
            //Custinfo["Building"] = $('#Building').val();
        }

        else if (CustomerDetails["DeliveryAddressType"] == "Apartment") {
            $('#CustAddressApartment').addClass("active");
            $('#CustAddressApartment').click();
            $('#nav-apartment').addClass("active show");

            $('#txtApartmentBlock').val(CustomerDetails["Block"]);
            $('#txtApartmentStreet').val(CustomerDetails["Street"]);
            $('#txtApartmentBuilding').val(CustomerDetails["Building"]);
            $('#txtApartmentFloor').val(CustomerDetails["Floor"]);
            $('#txtApartmentFlatNo').val(CustomerDetails["Flat"]);
            $('#txtApartmentLandmark').val(CustomerDetails["AddressRemarks"]);
        }
        else if (CustomerDetails["DeliveryAddressType"] == "Office") {
            $('#CustAddressOffice').addClass("active");
            $('#CustAddressOffice').click();
            $('#nav-office').addClass("active show");

            $('#txtOfficeBlock').val(CustomerDetails["Block"]);
            $('#txtOfficeStreet').val(CustomerDetails["Street"]);
            $('#txtOfficeBuilding').val(CustomerDetails["Building"]);
            $('#txtOfficeFloor').val(CustomerDetails["Floor"]);
            $('#txtOfficeFlat').val(CustomerDetails["Flat"]);
            $('#txtOfficeLandmark').val(CustomerDetails["AddressRemarks"]);
        }

        $('#hdnlat').val(CustomerDetails["Latitude"]);
        $('#hdnlong').val(CustomerDetails["Longitude"]);

        //set areaid 
        if ($('#pickup').hasClass("active")) {
            $('.clrbranchList').each(function (index) {
                $(this).removeClass("active");
                if (parseInt($(this).attr("data-arId")) == CustomerDetails["AreaID"]) {
                    $(this).addclass("active");
                }
            });
        }
        else {
            if (parseInt(CustomerDetails["AreaID"]) > 0) {
                $('#AddressArea').val(CustomerDetails["AreaID"]);
            }
        }


        if (CustomerDetails["Latitude"] != "" && CustomerDetails["Longitude"] != "") {
            if (marker !== null) {
                CustomerAddressMap.removeLayer(marker);
            }
            marker = L.marker([CustomerDetails["Latitude"], CustomerDetails["Longitude"]]).addTo(CustomerAddressMap);
        }

    }

}
