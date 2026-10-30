var selectedslotIds = "";
var FromDate = "";
var ToDate = "";
var isdefault = 1;
var ReservationId = 0;




$(document).ready(function () {
    FillReservation();
    //BindTableData();
    //bindGridview();
    //setLabelsFromCookies("CallCenter");
    //InvoiceListingTable.init();
    //window.setInterval(function () {
    //    InvoiceListingTable.init();
    //}, 20000);
    


    //var now = new Date();
    //var day = ("0" + now.getDate()).slice(-2);
    //var month = ("0" + (now.getMonth() + 1)).slice(-2);
    //var today = now.getFullYear() + "-" + (month) + "-" + (day);
    //$('#ddDate').val(today);


    //var today = new Date();
    //var FromDate = today.getFullYear() + '-' + ('0' + (today.getMonth() + 1)).slice(-2) + '-' + ('0' + today.getDate()).slice(-2);
    //var ToDate = FromDate;
    //$('#FromDate').val(FromDate);
    //$('#ToDate').val(ToDate);
    
});

var myintVar=null;
//-------------start Bind Reservation listing Data table--------------------//


function bindGridview() {
    if ($.fn.DataTable.isDataTable('#grd_ReservationData')) {
        $('#grd_ReservationData').DataTable().destroy();
    }
    $('#grd_ReservationData tbody').empty();

    table_ReservationData = $('#grd_ReservationData');
    table_ReservationData.DataTable({
        responsive: true,
        ajax: {
            url: "/BranchReservation/GetReservationData?slotIds=" + selectedslotIds + "&FromDate=" + FromDate + "&ToDate=" + ToDate + "",
            type: 'POST',
            data: {
                //pagination: {
                //    perpage: 50,
                //},
            },
        },
        columns: [
            {
                data: 'id'
            },
            {
                data: 'confirmationId'
            },
            {
                data: 'customerName',
            },
            {
                data: 'customerMobile'
            },
            {
                data: 'customerEmail'
            },
            {
                data: 'slotName'
            },
            {
                data: 'TableName'
            },
            {
                data: 'DiningArea'
            },
            {
                data: 'reservationDate'
            },
            {
                data: 'TransactionDate'
            },
            {
                data: 'status'
            },
            {
                data: 'id',
                responsivePriority: -1
            },
        ],
        "order": [[0, "desc"]],
        columnDefs: [
            {
                "targets": [0],
                "visible": false
            },
            {
                targets: -1,
                title: 'Actions',
                orderable: false,
                render: function (data, type, full, meta) {
                    if (full.status == 1) {
                        return '<button href="#" class="btn btn-warning" title="View" data-toggle="modal" data-target="#ReservationStatus" onclick="grd_Reservation_Arrivedclick(' + full.id + ');">Edit</button>';
                    }
                    else {
                        return '';
                    }
                },
                'createdCell': function (td, cellData, rowData, row, col) {
                    $(td).attr('nowrap', 'nowrap');
                }
            },
            {
                width: '60px',
                targets: -2,
                render: function (data, type, full, meta) {
                    if (data > 10) {
                        data = 1;
                    }
                    var status = {
                        1: {
                            'title': 'Reserve',
                            'class': 'label-light-primary'
                        },
                        2: {
                            'title': 'Arrrived',
                            'class': ' label-light-success'
                        },
                    };
                    if (typeof status[data] === 'undefined') {
                        return data;
                    }
                    return '<span class="label label-lg font-weight-bold' + status[data].class + ' label-inline">' + status[data].title + '</span>';
                },
            }
        ],
        select: {
            style: 'os',
            selector: 'td:first-child'
        },

        dom: 'Bfrtip',
        buttons: [
            'copyHtml5',
            'excelHtml5',
            'csvHtml5',
            'pdfHtml5'
        ]
    });


    var table1 = $('#grd_ReservationData').DataTable();
    myintVar = setInterval(function () {
        console.log(FromDate + ',' + ToDate);
        table1.ajax.reload();
    }, 2000);
}

function grd_Reservation_Arrivedclick(Resid) {
    ReservationId = Resid
}


function FillReservation() {

    debugger
    $.ajax({
        type: "GET",
        data: JSON.stringify(),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/BranchReservation/GetReservationStatus",
        success: function (result) {
            if (result.dtTableresult != "") {
                var ReservationStatus = JSON.parse(result.dtReservationStatus);
                $("#ddReservationStatus").html("");
                $("#ddReservationStatus").append($("<option></option>").val("0").html("Please Select Reservation Status"));
                $.each(ReservationStatus, function (data, value) {
                    $("#ddReservationStatus").append($("<option></option>").val(value.id).html(value.StatusName));
                });

            }
        }
    });

}


function ReservationStatusChange() {
    debugger;
    if (parseInt($("#ddReservationStatus option:selected").val()) > 0) {
        var objdata = {
            ReservationStatusId: $("#ddReservationStatus option:selected").val(),
            ReservationId: ReservationId,
        }
        $("#ddReservationStatus").val(0)
        debugger
        $.ajax({
            type: "POST",
            data: JSON.stringify(objdata),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/BranchReservation/ReservationStatus",
            success: function (result) {
                if (result.Message == "Success") {
                    $('#btnReservationStatusClose').click();
                    $("#ddReservationStatus").val(0)

                    bindGridview();
                }
                else {
                    alert("Error");
                }
            }
        });
    }
    else {
        $("#alertTitle").html("");
        $("#alertMessage").html("Please Select Status");
        $("#alertModal").modal()
    }


}


function ReservationStatusClose() {
    $("#ddReservationStatus").val(0);
}

//function grd_Reservation_Arrivedclick(Resid) {
//    //$("#lblViewBillAmount").html("0.000");
//    //$("#lblViewDiscount").html("0.000");
//    //$("#lblViewDeliveryCharges").html("0.000");
//    //$("#lblViewFinalAmount").html("0.000");
//    //btnViewOrder(rowData.InvoiceNo);

//    var objReservation = {
//        Reservationid: Resid
//    }
//    $.ajax({
//        type: "Post",
//        data: JSON.stringify(objReservation),
//        contentType: "application/json; charset=utf-8",
//        dataType: "json",
//        cache: false,
//        url: "/BranchReservation/SetArrived",
//        success: function (result) {
//            if (result.Message == "Success") {
//                //InvoiceListingTable.init();
//                bindGridview();
//            }
//            else {
//                alert("Error");
//            }
//        }
//    });
//}

//function grd_InvoiceListingPrintclick(rowData) {
//    $("#btnProcessOrder").show();
//    $("#btnCustomerInfo").hide();
//    btnNewItem(rowData.InvoiceNo);
//    $("#lblInvoiceNo").text(rowData.InvoiceNo);
//    $("#txtSearchMobile").val(rowData.Mobile);
//}
//-------------End Reservation listing Data table Actions--------------------//



/////////////////////Start date selection for Filter data /////////////////////////

$(function () {
    var start = moment().subtract(0, 'days');
    var end = moment();

    function cb(start, end) {
        $('#reportrange span').html(start.format('MMMM D, YYYY') + ' - ' + end.format('MMMM D, YYYY'));
        //alert(start.format('YYYY-M-D') + '    ' + end.format('YYYY-M-D'));
        $('#FromDate').val(start.format('YYYY-M-DD'));
        $('#ToDate').val(end.format('YYYY-M-DD'));
        //GetData(start.format('YYYY-M-DD'), end.format('YYYY-M-DD'));
        filterSearch();
    }

    $('#reportrange').daterangepicker({
        startDate: start,
        endDate: end,
        ranges: {
            'Today': [moment(), moment()],
            'Yesterday': [moment().subtract(1, 'days'), moment().subtract(1, 'days')],
            'Last 7 Days': [moment().subtract(6, 'days'), moment()],
            'Last 30 Days': [moment().subtract(29, 'days'), moment()],
            'This Month': [moment().startOf('month'), moment().endOf('month')],
            'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')]
        }
    }, cb);
    //setDatepicker();
    cb(start, end);

});

function filterSearch() {
    FromDate = $('#FromDate').val();
    ToDate = $('#ToDate').val();
    //InvoiceListingTable.init();
    if (myintVar != null) {
        clearInterval(myintVar);
    }
    bindGridview();

}

function filterClear() {
    selectedslotIds = "";
    FromDate = "";
    ToDate = "";
    $('#reportrange input').val('');
    $('#reportrange span').html("");
    //InvoiceListingTable.init();
    if (myintVar != null) {
        clearInterval(myintVar);
    }
    bindGridview();
}
/////////////////////End date selection for Filter data /////////////////////////

function DisplayTableview() {
    //window.location.href = "http://stackoverflow.com";
    window.location.href = '/BranchReservation/IndexNew';
}