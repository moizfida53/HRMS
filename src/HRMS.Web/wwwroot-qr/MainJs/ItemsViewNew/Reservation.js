//$(document).ready(function () {
//    $('#dtReservation').datepicker({
//        format: "yyyy-mm-dd",
//    }).change(dateChanged).on('changeDate', dateChanged);
//});

//function dateChanged(ev) {
//    alert("asdfasdfasdf");
//}

$(document).ready(function () {
    // Datepicker ===========================
    var dateToday = new Date();
    $('#dtReservation').datepicker({
        //inline: true,
        autoclose: true,
        format: "dd M yyyy",
        minDate: dateToday,
        //startDate: "+0d",
        startDate: dateToday,
        //setDate: null,
        //rtl: true,
        daysOfWeekDisabled: [0, 1, 2, 3],
        ignoreReadonly: true,
    }).change(dateChanged).on('changeDate', dateChanged);
    function dateChanged(ev) {
        $('#ulAvailableSlotsInner').html("");
        $('#ulAvailableSlotsOuter').html("");
        //$('#divAvailableTimeList').hide();
        $('#divAreaAndTimeslot').show();
        onCheckAvailability();
    }

    // Datepicker ===========================
});
//$('.datepicker').change(function (event) {
//    alert('!!!');
//});


//$('.table-condensed tbody tr td').on(function (event) {
//    alert('!!!dfdasfafda');
//});
var selectedDate = null;
function onCheckAvailability() {
    debugger;
    $('#ulAvailableSlotsInner').html("");
    $('#ulAvailableSlotsOuter').html("");

    selectedDate = $(".datepicker").datepicker("getDate");

    debugger;
    //var tableStID = 1
    //if ($('#hdnSelectedDiningArea').val() =="Inner Area") {
    //    tableStID = $('#hdnSelectedtableId').val();
    //}
    //else {
    //    if ($('#hdnSelectedtableId').val() == 1) {
    //        tableStID = 4;
    //    }
    //    else if ($('#hdnSelectedtableId').val() == 2) {
    //        tableStID = 5;
    //    }
    //    else {
    //        tableStID = 6;
    //    }
    //}
    var objdata = {
        //guestCnt: $('#txtReservationGuestCount').val(),
        //reservationDate: selectedDate
        TableSeatingCount: $('#hdnSelectedtableSeating').val(),
        reservationDate: selectedDate,
        DiningArea: $('#hdnSelectedDiningArea').val(),
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/BranchReservation/GetAvailability",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Mainstr = "";
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

                        var str = "";
                        str = '<a id="rdSlot_' + data.id + '" data-value="' + data.id + '" class="times-zone rdSlot" onclick="onSlotclick(this);">' + slotName + '</a>';
                        Mainstr = Mainstr + str;
                        cntcat = cntcat + 1;
                    });
                    //if (cntcat > 0) {
                    //    $('#btnReservationConfirm').show();
                    //}
                    //$('#ulAvailableSlots').html(Mainstr);
                    //if ($('#inner').hasClass("active")) {
                    if ($('#hdnSelectedDiningArea').val() == 'Inner Area') {
                        $('#ulAvailableSlotsInner').html(Mainstr);
                    }
                    else {
                        $('#ulAvailableSlotsOuter').html(Mainstr);
                    }
                    //$('#divAvailableTimeList').show();
                }


                //ev.preventDefault();
                $(".main-content").animate({ scrollTop: '+=350px' }, 600);
            }
            else {
                $("#alertTitle").html("");
                $("#alertMessage").html(msgerrorval);
                $("#alertModal").modal()
            }
        }
    });


}
function onReservationConfirmClick() {
    debugger;

    //var selectedSlotId = $("input:radio.rdSlot:checked").val();
    var selectedSlotId = $('#hdnSelectedSlotId').val();
    if (selectedSlotId > 0) {
        ShowDivReservationCustomerInfo();
    }
    else {
        $("#alertTitle").html("");
        $("#alertMessage").html(msgPleaseSelectValidSlot);
        $("#alertModal").modal();
    }
}
function AddReservationGuest() {
    var cnt = parseInt($('#txtReservationGuestCount').val());
    $('#txtReservationGuestCount').val(cnt + 1);
}

function MinusReservationGuest() {
    var cnt = parseInt($('#txtReservationGuestCount').val());
    if (cnt > 1) {
        $('#txtReservationGuestCount').val(cnt - 1);
    }
}


function onReservationiSubmitclick() {
    debugger;
    if (!($('#hdnBranchId').val() > 0)) {
        //$("#alertTitle").html("");
        //$("#alertMessage").html(msgBranchNotSelected);
        //$("#alertModal").modal()
        //return false;
        $('#hdnBranchId').val("1")
    }

    if (!($('#txtCustomerName').val().length > 0)) {
        $("#alertTitle").html("");
        $("#alertMessage").html(msgInsertCustomerName);
        $("#alertModal").modal()
        return false;
    }
    else if (!($('#txtCustomerMobile').val().length > 0)) {
        $("#alertTitle").html("");
        $("#alertMessage").html(msgInsertCustomerMobile);
        $("#alertModal").modal()
        return false;
    }
    else if (!($('#txtCustomerEmail').val().length > 0)) {
        $("#alertTitle").html("");
        $("#alertMessage").html(msgInsertCustomerEmail);
        $("#alertModal").modal()
        return false;
    }

    else {
        debugger;
        //var tableStID=1
        //if ($('#hdnSelectedDiningArea').val() == "Inner Area") {
        //    tableStID = $('#hdnSelectedtableId').val();
        //}
        //else {
        //    if ($('#hdnSelectedtableId').val() == 1) {
        //        tableStID = 4;
        //    }
        //    else if ($('#hdnSelectedtableId').val() == 2) {
        //        tableStID = 5;
        //    }
        //    else {
        //        tableStID = 6;
        //    }
        //}
        //var selectedDate = $(".datepicker").datepicker("getDate");
        var objdata = {
            branchid: $('#hdnBranchId').val(),
            //slotId: $("input:radio.rdSlot:checked").val(),
            slotId: parseInt($('#hdnSelectedSlotId').val()),
            reservationDate: selectedDate,
            customerName: $('#txtCustomerName').val(),
            customerMobile: $('#txtCustomerMobile').val(),
            customerEmail: $('#txtCustomerEmail').val(),
            comments: $('#txtComments').val(),
            TableSeatingCount: $('#hdnSelectedtableSeating').val(),
            DiningArea: $('#hdnSelectedDiningArea').val(),
        }
        debugger;
        $.ajax({
            type: "Post",
            data: JSON.stringify(objdata),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/BranchReservation/SubmitReservationData",
            success: function (result) {
                debugger;
                if (result.Message == "Success" || result.Message == "Email not sent!") {


                    var dtresult = JSON.parse(result.dtresult);
                    var slotName = "";

                    if ($('#selectedLang').val() == "EN") {
                        slotName = dtresult[0].slotName;
                    }
                    else {
                        slotName = dtresult[0].slotName;
                    }

                    $('#lblReservationConfirmationId').html(dtresult[0].confirmationId);
                    $('#lblSelectedTableName').html(dtresult[0].TableName);
                    $('#lblConfirmReservationDate').html(dtresult[0].reservationDate);
                    $('#lblConfirmReservationSlot').html(slotName);

                    var qrcodestring = dtresult[0].confirmationId;
                    //var val = JSON.stringify(CartDetails);
                    if (qrcodestring) {
                        $('#ReservationConfirmQRCode').html("");
                        $('#ReservationConfirmQRCode').qrcode(qrcodestring);
                    }
                    ShowDivReservationConfirm();

                    $('#ulAvailableSlotsInner').html("");
                    $('#ulAvailableSlotsOuter').html("");
                    //$('#divAvailableTimeList').hide();

                    if (result.Message == "Email not sent!") {
                        $("#alertTitle").html("");
                        $("#alertMessage").html("Email not sent!");
                        $("#alertModal").modal()
                    }
                }
                else {
                    $("#alertTitle").html("");
                    $("#alertMessage").html(msgerrorval);
                    $("#alertModal").modal()
                }
            }
        });
    }

}



function OnTableSelect(obj, MaxSeatingCount) {
    debugger;
    if (MaxSeatingCount == 9) {
        $("#alertTitle").html("");
        $("#alertMessage").html("Please contact branch manager.");
        $("#alertModal").modal()
    }
    else {
        $('.table-outer').each(function (val, ind) {
            $(this).removeClass("active");
        })
        $(obj).addClass("active");
        $('#hdnSelectedtableSeating').val(MaxSeatingCount);
        $('#divDatepickerMain').show();
        //$('#divAreaAndTimeslot').show();
        onCheckAvailability();
    }

}

function setSelectedArea(strArea) {
    $('#hdnSelectedDiningArea').val(strArea);
    onCheckAvailability();
}

function onSlotclick(obj) {
    debugger;
    $('.rdSlot').each(function (val, ind) {
        if ($(this).hasClass("active")) {
            $(this).removeClass("active");
        }
    })

    debugger;
    $(obj).addClass("active");
    $('#hdnSelectedSlotId').val($(obj).attr("data-value"));
    $('#btnReservationConfirm').show();
    $('#btnReservationConfirm').focus();
}