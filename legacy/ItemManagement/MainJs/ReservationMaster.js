$(document).ready(function () {
    BindTableData();
});

function BindTableData() {
    debugger;
    $('#inner').html("");
    $('#outer').html("");
    $('#ulTimeSlotList').html("");
    $.ajax({
        type: "POST",
        cache: false,
        url: "/ReservationMaster/GetDataList",
        success: function (result) {
            debugger;
            if (result.dtresult != "") {
                var Tabledata = JSON.parse(result.dtTableresult);
                var TimeSlotdata = JSON.parse(result.dtTimeSlotresult);
                BindTableViewHtml(Tabledata);
                BindTimeSlotViewHtml(TimeSlotdata);
            }
        }
    });
}
function BindTableViewHtml(tabldata) {
    debugger;
    $.each(tabldata, function (index, value) {
        debugger;
        var x1 = value.Xaxis;
        var y1 = value.Yaxis;
        //var htmlstr = $('<div>');
        //var btnstring = "<a id='divContainer_'" + value.id + "' class='card table-popover m-2' href = '#' onmouseup='mouseUp(" + value.id + ");'>";

        //if (value.Seating == 2) {
        //    btnstring = btnstring + "<img src='../Images/1-2New.png' class='card-img img-responsive' alt='Tableimage'>";
        //}
        //else if (value.Seating == 4) {
        //    btnstring = btnstring + "<img src='../Images/3-4New.png' class='card-img img-responsive' alt='Tableimage'>";
        //}
        //else {
        //    btnstring = btnstring + "<img src='../Images/5plusNew.png' class='card-img img-responsive' alt='Tableimage'>";
        //}

        //btnstring = btnstring + "<div class='card-body'>" +
        //    "</div>" +
        //    "</a>";
        //var btn = $(btnstring)
        //    .draggable({
        //        drag: function () {
        //            var offset1 = $(this).offset();
        //            var xPos1 = offset1.left.toFixed(10);
        //            var yPos1 = offset1.top.toFixed(10);
        //            $('#posX').html(xPos1);
        //            $('#posY').html(yPos1);
        //        }
        //    }).css({
        //        position: 'absolute',
        //        top: y1,
        //        left: x1,

        //    });
        //htmlstr.append(btn);

        var imagename = "";
        if (value.Seating == 2) {
            imagename = "../Images/1-2New.png";
        }
        else if (value.Seating == 4) {
            imagename = "../Images/3-4New.png";
        }
        else {
            imagename = "../Images/5plusNew.png";
        }

        var htmlstr = "";
        //if (value.Reservationid > 0 && value.Status == 1) {
        //    htmlstr = htmlstr + "<div id='divContainer_'" + value.id + "' class='card table-popover m-2 reserved' onmouseup='mouseUp(" + value.id + ");' >";
        //    htmlstr = htmlstr + "<div class='d-flex position-relative'>" +
        //        "<a href='#' title='arrived' class='arrived-icon' onclick='Arrivedclick(" + value.Reservationid + ");'><img src='../Images/arrived.svg' alt=''></a>" +
        //        "<img src='" + imagename + "' class='card-img' alt='...'>" +
        //        "</div>";
        //}
        //else if (value.Reservationid > 0 && value.Status == 2) {
        //    htmlstr = htmlstr + "<div id='divContainer_'" + value.id + "' class='card table-popover m-2 arrived' onmouseup='mouseUp(" + value.id + ");' >";
        //    htmlstr = htmlstr + "<div class='d-flex position-relative'>" +
        //        "<img src='" + imagename + "' class='card-img' alt='...'>" +
        //        "</div>";
        //}
        //else {
            htmlstr = htmlstr + "<div id='divContainer_'" + value.id + "' class='card table-popover m-2' onmouseup='mouseUp(" + value.id + ");' >";
            htmlstr = htmlstr + "<div class='d-flex position-relative'>" +
                "<img src='" + imagename + "' class='card-img' alt='...'>" +
                "</div>";
        //}

        var customerName = value.customerName == null ? "" : value.customerName;
        var customerMobile = value.customerMobile == null ? "" : value.customerMobile;
        htmlstr = htmlstr + "<div class='card-body d-flex justify-content-between'>" +
            "<div>" +
            "<p class='customer-name'>" + customerName + "</p>" +
            "<span class='time'>" + customerMobile + "</span>" +
            "</div>";

        if (value.Reservationid > 0 && value.Status == 2) {
            htmlstr = htmlstr + "<a href='#' class='edit-btn' data-toggle='modal' data-target='#add-item'><img src='../Images/text-edit.svg' alt=''></a>";
        }

        htmlstr = htmlstr + "</div>" +
            "</div>";
        var btn = $(htmlstr)
            .draggable({
                drag: function () {
                    var offset1 = $(this).offset();
                    var xPos1 = offset1.left.toFixed(10);
                    var yPos1 = offset1.top.toFixed(10);

                    $('#posX').text(xPos1);
                    $('#posY').text(yPos1);
                }
            })
            .css({
                position: 'absolute',
                top: y1,
                left: x1,
            });

        if (value.DiningArea == "Inner Area") {
            $("#inner").append(btn);
        }
        else {
            $("#outer").append(btn);
        }
    });
}

function BindTimeSlotViewHtml(Timedata) {
    debugger;
    $.each(Timedata, function (index, value) {
        debugger;
        var strTimeSlotLi = ""
        strTimeSlotLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="branch_td2">' + value.slotName + '</td>\
                                    <td class="branch_td3" >\
                                        <input id="hdnslotName_'+ value.id + '" type="hidden" value="' + value.slotName + '" />\
                                        <input id="hdnslotNameArab_'+ value.id + '" type="hidden" value="' + value.slotNameArabic + '" />\
                                        <input id="hdnslotFromTime_'+ value.id + '" type="hidden" value="' + value.fromTime + '" />\
                                        <input id="hdnslotToTime_'+ value.id + '" type="hidden" value="' + value.toTime + '" />\
                                        <a href="#" class="edit-btn" data-val-Eng="' + value.slotName + '" data-val-Arb="' + value.slotNameArabic + '" \
                                            data-target="WindowTimeSlot" onclick="OnEditTimeSlot(this,' + value.id + ')";><img src="../Images/text-edit.svg" alt=""></a>\
												</td>\
								</tr>	\
							</table>\
						</li>';
        $("#ulTimeSlotList").append(strTimeSlotLi);


    });
    var strTimeSlotAddButton = '<li>\
                            <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowTimeSlot" onclick="AddTimeSlot()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Time Slot</span></a>\
                        </li>';
    $("#ulTimeSlotList").append(strTimeSlotAddButton);
}

function mouseUp(TableID) {
    debugger;
    var value = {
        "TableID": TableID,
        "X": $('#posX').html(),
        "Y": $('#posY').html()
    };
    var obji = {
        value: value
    }
    $.ajax({
        type: "POST",
        cache: false,
        url: "/ReservationMaster/ArrangeTable",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            $('#posX').html('');
            $('#posY').html('');
        }
    });
}


//////////////////Start Table Add Update ///////////////
function ClearTableAddForm() {
    $('#txtTableName').val("");
    $('#ddDiningArea').val("");
    //$('#txtSeatingCount').val("0");
    var value = 2;
    $("input[name=seatingCount][value=" + value + "]").attr('checked', 'checked');
    $('#hdnSelectedTableid').val("0");
}
function AddTable() {
    ClearTableAddForm();
    $("#WindowTable").modal('show');
}
function EditTable(obj, ID) {
    ClearTableAddForm();
    $("#WindowTable").modal('show');
    $('#hdnSelectedTableid').val(ID);
}
function SaveTable() {
    debugger;
    if ($('#txtTableName').val() == "") {
        $("#warningMessage").html("Please insert table name.");
        $('#warning').modal("toggle");
        return false;
    }

    var selectedDiningArea = "Inner Area";
    if ($('#inner-areas').hasClass("active")) {
        selectedDiningArea = "Inner Area";
    }
    else {
        selectedDiningArea = "Out Area";
    }

    var tableid = $('#hdnSelectedTableid').val();
    var obji = {
        id: tableid,
        TableName: $('#txtTableName').val(),
        //DiningArea: $("#ddDiningArea option:selected").text(),
        DiningArea: selectedDiningArea,
        Seating: $("input[name='seatingCount']:checked").val(),
        Xaxis: 0,
        Yaxis: 0,
    }
    debugger;
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        url: "/ReservationMaster/AddEditTable",
        success: function (result) {
            $("#WindowTable").modal('hide');
            //url: "/Category/ChangePassword?
            if (result.message == "Fail") {
                $("#warningMessage").html(result.alert);
                $('#warning').modal("toggle");
            }
            else {
                if (tableid > 0) {
                    $("#message").html("Table Update successfully.");
                    BindData();
                }
                else {
                    $("#message").html("Table Added successfully.");
                    BindData();
                }
                $('#alert').modal("toggle");
            }
        }
    });
}
function InActiveTable() {
    debugger
    var tableid = $('#hdnSelectedTableid').val();
    var obji = {
        id: tableid,
    }
    debugger;
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        url: "/ReservationMaster/DeleteTable",
        success: function (result) {
            $("#WindowTable").modal('hide');
            //url: "/Category/ChangePassword?
            if (result.message == "Fail") {
                $("#warningMessage").html(result.alert);
                $('#warning').modal("toggle");
            }
            else {
                $("#message").html("Table deleted successfully.");
                $('#alert').modal("toggle");
                BindData();
            }
        }
    });
}
//////////////////End Table Add Update ///////////////


///////////////Start Timeslot Add Update////////////////////////
function ClearTimeSlotForm() {
    $('#txtSlotNameEng').val("");
    $('#txtSlotNameArab').val("");
    $('#txtFromTime').val("");
    $('#txtToTime').val("");
    $('#hdnSelectedSlotid').val("");
}
function AddTimeSlot() {
    ClearTimeSlotForm();
    $("#WindowTimeSlot").modal('show');

}

function OnEditTimeSlot(obj, ID) {
    debugger;
    ClearTimeSlotForm();
    $("#WindowTimeSlot").modal('show');
    $('#hdnSelectedSlotid').val(ID);

    $('#txtSlotNameEng').val($('#hdnslotName_' + ID).val());
    $('#txtSlotNameArab').val($('#hdnslotNameArab_' + ID).val());
    $('#txtFromTime').val($('#hdnslotFromTime_' + ID).val());
    $('#txtToTime').val($('#hdnslotToTime_' + ID).val());
}

function SaveTimeSlot() {
    debugger
    var selectedSlotid = $('#hdnSelectedSlotid').val();
    var obji = {
        id: selectedSlotid,
        slotName: $('#txtSlotNameEng').val(),
        slotNameArabic: $("#txtSlotNameArab").val(),
        fromTime: $('#txtFromTime').val(),
        toTime: $('#txtToTime').val(),
    }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        url: "/ReservationMaster/AddEditTimeSlot",
        success: function (result) {
            $("#WindowTimeSlot").modal('hide');
            //url: "/Category/ChangePassword?
            if (result.message == "Fail") {
                $("#warningMessage").html(result.alert);
                $('#warning').modal("toggle");
            }
            else {
                if (selectedSlotid > 0) {
                    $("#message").html("Time Slot Update successfully.");
                    BindData();
                }
                else {
                    $("#message").html("Time Slot Added successfully.");
                    BindData();
                }
                $('#alert').modal("toggle");
            }
        }
    });
}
function InActiveTimeSlot() {
    debugger
    var selectedSlotid = $('#hdnSelectedSlotid').val();
    var obji = {
        id: selectedSlotid,
    }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        url: "/ReservationMaster/DeleteTimeSlot",
        success: function (result) {
            $("#WindowTimeSlot").modal('hide');
            //url: "/Category/ChangePassword?
            if (result.message == "Fail") {
                $("#warningMessage").html(result.alert);
                $('#warning').modal("toggle");
            }
            else {
                $("#message").html("Time Slot deleted successfully.");
                $('#alert').modal("toggle");
                BindData();
            }
        }
    });
}
///////////////End Timeslot Add Update////////////////////////


jQuery(document).on('keydown', 'input.numericOnly', function (event) {
    if (event.shiftKey == true) {
        event.preventDefault();
    }

    if ((event.keyCode >= 48 && event.keyCode <= 57) ||
        (event.keyCode >= 96 && event.keyCode <= 105) ||
        event.keyCode == 8 || event.keyCode == 9 || event.keyCode == 37 ||
        event.keyCode == 39 || event.keyCode == 46 || event.keyCode == 190 || event.keyCode == 110) { } else {
        event.preventDefault();
    }
    if ($(this).val().indexOf('.') != -1 && (event.keyCode == 190 || event.keyCode == 110)) {
        event.preventDefault();
    }
    //if a decimal has been added, disable the "."-button
});

