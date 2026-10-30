//==============================================================================
//  Areas/POS/Scripts/Dashboard.js
//------------------------------------------------------------------------------
//  DATE SCOPE
//  The dashboard is scoped by the selected date range and nothing else.
//
//  The old Operation Day dropdown was the end-day / end-shift selector: it
//  posted its till sessions as @EndDates, and sp_DashbordSalesData applies
//  @EndDates INSTEAD OF the range whenever @IsDefaultLoad is 0. Two controls
//  answering the same question, and the one the user was not looking at usually
//  won. It is gone from the page, endDates is no longer posted, and
//  IsDefaultLoad is always true - that flag is the procedure's own switch for
//  "the date range decides".
//
//  GetEndDates on the controller and sp_GetEndDatesForRptDashboard are left in
//  place, simply unused: nothing calls them from here any more.
//==============================================================================

var selectedTabName = "";
var BranchWiseSalesChart;
var grd_DetailsSummarytable = null;

// One ready handler, where there were two. The old pair fought each other - the
// first wrote a formatted range into #StartDate, the second overwrote it a
// moment later with a bare yyyy-MM-dd - so the picker's caption and the value
// actually posted disagreed from the first paint.
$(document).ready(function () {

    InitDateRangePicker();
    BindFilters();

});

// Writes a picked range to the caption and the two hidden inputs. It does not
// reload: the range takes effect on Apply, so a new range and a handful of
// dropdown changes reach the server as one request instead of one per click.
function ApplyDateRangeToInputs(start, end) {
    $('#reportrange span').html(start.format('DD MMM YYYY, h:mm A') + '  -  ' + end.format('DD MMM YYYY, h:mm A'));
    $('#StartDate').val(start.format('YYYY-MM-DD HH:mm:ss'));
    $('#EndDate').val(end.format('YYYY-MM-DD HH:mm:ss'));
}

function InitDateRangePicker() {

    // Guarded rather than assumed. If a plugin failed to load the page still
    // reports on today instead of dying on the first line of ready() and
    // taking the filter binding down with it - which is exactly what used to
    // happen when the layout's jQuery replaced the one daterangepicker
    // attached to.
    if (typeof moment === 'undefined') { return; }

    var start = moment().startOf('day');
    var end = moment().endOf('day');

    if (typeof $.fn.daterangepicker !== 'function') {
        ApplyDateRangeToInputs(start, end);
        return;
    }

    $('#reportrange').daterangepicker({
        timePicker: true,
        timePickerIncrement: 15,
        startDate: start,
        endDate: end,
        locale: {
            format: 'DD/MM/YYYY h:mm A',
            applyLabel: 'Select',
            cancelLabel: 'Cancel'
        },
        ranges: {
            'Today': [moment().startOf('day'), moment().endOf('day')],
            'Yesterday': [moment().subtract(1, 'days').startOf('day'), moment().subtract(1, 'days').endOf('day')],
            'Last 7 Days': [moment().subtract(6, 'days').startOf('day'), moment().endOf('day')],
            'Last 30 Days': [moment().subtract(29, 'days').startOf('day'), moment().endOf('day')],
            'This Month': [moment().startOf('month'), moment().endOf('month')],
            'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')]
        }
    });

    // apply.daterangepicker hands over the picker itself, so what is read here
    // is what the user confirmed. The original passed a callback to the
    // constructor and then called it by hand with a start and end that had
    // nothing to do with the picker's own state - which is how the caption and
    // the picker came apart before anyone had clicked anything.
    $('#reportrange').on('apply.daterangepicker', function (ev, picker) {
        ApplyDateRangeToInputs(picker.startDate, picker.endDate);
    });

    ApplyDateRangeToInputs(start, end);
}

function OnReloadFilterClick() {
    InitDateRangePicker();
    BindFilters();
}
function BindFilters() {
    bindCountryDropdown();
    GetFilterData();
}

// Rebuilds a bootstrap-select from scratch around a <select> that has just been
// repopulated. See the long note on BindFilterDropdowns for why nothing here
// uses .selectpicker('refresh').
function RebuildSelectPicker($drp) {
    if ($drp.data('selectpicker')) {
        $drp.selectpicker('destroy');
    }
    // destroy() strips the class the plugin's own data-api keys off, so put it
    // back. Constructing a widget that already exists is a no-op inside the
    // plugin (it only merges options), so this cannot double-build.
    $drp.addClass('selectpicker').selectpicker();
}

function bindCountryDropdown() {
    var CountryData = JSON.parse('[{"val":1,"txt":"Kuwait"},{"val":2,"txt":"KSA"}]');
    $("#drpCountry").html("");
    $.each(CountryData, function (data, value) {
        if (value.val == "Kuwait") {
            $("#drpCountry").append($("<option selected='selected'></option>").val(value.val).html(value.txt));
        }
        else {
            $("#drpCountry").append($("<option></option>").val(value.val).html(value.txt));
        }
    });
    RebuildSelectPicker($("#drpCountry"));
}

function GetFilterData() {
    $.ajax({
        type: "POST",
        cache: false,
        data: {
            CountryId: $('#drpCountry').val()
        },
        url: DASH.filter,
        // The original compared with a single "=", which assigns rather than
        // tests and is therefore always true. A NoData reply fell straight
        // through into JSON.parse(undefined) and threw, leaving every dropdown
        // empty with nothing on screen to say why. Same typo appeared at three
        // more call sites and is corrected at each of them.
        success: function (result) {
            if (result.Message !== "Success") {
                ShowDashboardMessage("Filters could not be loaded. Please contact your administrator.");
                return;
            }

            var BranchData      = JSON.parse(result.dtBranch);
            var BrandData       = JSON.parse(result.dtBrand);
            var InvoiceTypeData = JSON.parse(result.dtInvoiceType);
            var PaymentTypeData = JSON.parse(result.dtPaymentType);

            // All four lists come back complete from sp_DashboardFilter - every
            // branch, every brand, every invoice type, every payment type - and
            // every entry starts selected behind an "All" option.
            BindFilterDropdowns(BranchData,      'drpLocations');
            BindFilterDropdowns(BrandData,       'drpBrands');
            BindFilterDropdowns(InvoiceTypeData, 'drpOrdertypes');
            BindFilterDropdowns(PaymentTypeData, 'drpPaymenttypes');

            // A single-brand operator has no choice to make, so the choice is
            // made for them: the brand itself is selected, "All" is not. The
            // control stays enabled - selecting one of one is not a decision
            // worth taking away, and locking it would only look broken.
            if (BrandData && BrandData.length === 1) {
                var $brands = $('#drpBrands');
                $brands.find('option').prop('selected', false);
                $brands.find('option[value="' + BrandData[0].val + '"]').prop('selected', true);
                $brands.data('0', false);
                $brands.selectpicker('refresh');
            }

            ApplyFilter();
        },
        error: function () {
            ShowDashboardMessage("Filters could not be loaded. Please try again.");
        }
    });
}

// The page has a Bootstrap modal for this; alert() blocks the tab and looks
// like a crash on a counter screen.
function ShowDashboardMessage(text) {
    $("#message").html(text);
    $('#alert').modal("show");
}

function ApplyFilter() {
    var SelectedTab = "sales-tab-md";
    $(".dash_tab").each(function (index) {
        if ($(this).hasClass("active")) {
            SelectedTab = $(this).attr("id");
        }
    });
    selectedTabName = SelectedTab;
    //if ($('#SalesTabDetailsView').css('display') == 'none')
    GetReportDashboardData();
}


// Fills one filter with an "All" row followed by every row the server returned,
// all of them selected.
//
// value="0" is the "All" marker the rest of the stack already agrees on: the
// .clsfilter handler below keys off option[value="0"], and the controller strips
// "0" from branches and brands before it reaches SQL. For payment types 0 is
// deliberately NOT stripped, because 0 is how a cash sale is stored - so "All"
// selected still sweeps cash in, which is what it should do.
//
// The extra hard-coded <option value='0'>Cash</option> that used to be appended
// for payment types is gone. It duplicated the "All" row's value, so selecting
// one silently selected the other and the select-all logic counted a phantom
// entry; cash arrives from the server in dtPaymentType like everything else.
function BindFilterDropdowns(data, ControllerName) {

    var $drp = $("#" + ControllerName);

    $drp.prop('disabled', false).html("");
    $drp.append($("<option selected='selected'></option>").val("0").text("All"));

    $.each(data, function (index, value) {
        $drp.append($("<option selected='selected'></option>").val(value.val).text(value.txt));
    });

    // Keeps the "was All selected last time" bookkeeping in the change handler
    // honest across a rebind, which is what Reload does.
    $drp.data('0', true);

    // Rebuild, do NOT refresh.
    //
    // bootstrap-select constructs itself off its own "load.bs.select.data-api"
    // handler - window's load event - against whatever <option>s exist at that
    // instant. That is a race with this AJAX call, and window load usually wins
    // here, because this page pulls Chart.js, Highcharts, pdfmake and the
    // DataTables export bundle off CDNs before it fires. So the widget is
    // normally built around an EMPTY select.
    //
    // .selectpicker('refresh') does not undo that. Compare the plugin's own
    // init() with refresh(): init() runs createDropdown(), clickListener() and
    // liveSearchListener(); refresh() runs none of the three. A widget first
    // built empty is therefore left with menu scaffolding and click wiring that
    // were set up for a list with nothing in it, and re-rendering the <li>s
    // into it afterwards does not put that right - the control takes the click
    // but no list ever drops down, which reads as "the filter is disabled".
    //
    // That was the fault on All Locations / All Order Type / All Payment Types.
    // Brands escaped it by pure accident: the single-brand branch in
    // GetFilterData() above calls refresh a SECOND time, and that second pass
    // lands on internals the first pass had already filled in. One brand in
    // this database, so Brands looked fine and the other three did not.
    //
    // Destroying and constructing again removes the ordering question entirely:
    // the widget is only ever built from a select that is already populated,
    // whichever way the race went. destroy() returns the original <select> to
    // its place in the DOM and drops the wrapper, so this is safe on every
    // rebind - including Reload, which calls straight back through here.
    RebuildSelectPicker($drp);
}

$('.clsfilter').on('change', function () {
    var thisObj = $(this);
    var isAllSelected = thisObj.find('option[value="0"]').prop('selected');
    var lastAllSelected = $(this).data('0');
    var selectedOptions = (thisObj.val()) ? thisObj.val() : [];
    var allOptionsLength = thisObj.find('option[value!="0"]').length;

    console.log(selectedOptions);
    var selectedOptionsLength = selectedOptions.length;

    if (isAllSelected == lastAllSelected) {

        if ($.inArray("0", selectedOptions) >= 0) {
            selectedOptionsLength -= 1;
        }

        if (allOptionsLength <= selectedOptionsLength) {

            thisObj.find('option[value="0"]').prop('selected', true).parent().selectpicker('refresh');
            isAllSelected = true;
        } else {
            thisObj.find('option[value="0"]').prop('selected', false).parent().selectpicker('refresh');
            isAllSelected = false;
        }

    } else {
        thisObj.find('option').prop('selected', isAllSelected).parent().selectpicker('refresh');
    }

    $(this).data('0', isAllSelected);
}).trigger('change');

function GetReportDashboardData() {
    $('#reportView').html("");
    var _LateMinDuration = $('#txtLateMinDuration').val() == undefined ? 70 : parseInt($('#txtLateMinDuration').val());
    if (isNaN(_LateMinDuration)) {
        _LateMinDuration = "0";
    }
    showLoading();

    if (selectedTabName === undefined || selectedTabName === null) {
        //var SelectedTab = "sales-tab-md";
        $(".dash_tab").each(function (index) {
            if ($(this).hasClass("active")) {
                selectedTabName = $(this).attr("id");
            }
        });
    }

    var showDefaultValueflg = $('#ShowDefaultValue').val();
    if (selectedTabName == "SalesDetailsView") {
        showDefaultValueflg = $('#SalesShowDefaultValue').val();
    }
    $.ajax({
        type: "POST",
        cache: false,
        // endDates is not sent and IsDefaultLoad is fixed true: that pair is
        // how sp_DashbordSalesData decides between the operating-day list and
        // the date range, and the range is now the only answer.
        data: {
            CountryId: $('#drpCountry').val(),
            FromDate: $('#StartDate').val(),
            ToDate: $('#EndDate').val(),
            locationIDs: $('#drpLocations').val(),
            BrandIDs: $('#drpBrands').val(),
            orderTypeIDs: $('#drpOrdertypes').val(),
            paymentTypeIDs: $('#drpPaymenttypes').val(),
            LateMinDuration: _LateMinDuration,
            SelectedTab: selectedTabName,
            GroupByFlag: $('#HourlyChartGroupByForMainView').val(),
            ShowDefaultValueFlag: showDefaultValueflg,
            IsDefaultLoad: true
        },
        url: DASH.data,
        beforeSend: function () {
            showLoading();
        },
        success: function (result) {
            hideLoading();
            if (result.Message == "Success") {

                if (selectedTabName == "sales-tab-md") {
                    $('#SalesTabMainView').show();
                    $('#SalesTabDetailsView').hide();
                    $('#SalesTabSalesDetailsView').html("");
                    $('#HoursWiseSalesDataView').hide();
                    $('#LateOrderDetailsView').hide();
                    /*Start Sales Tab Data Bind*/
                    var TotalSales = JSON.parse(result.dtTotalSales);
                    var TotalDiscount = JSON.parse(result.dtTotalDiscount);
                    var CancellationReUse = JSON.parse(result.dtCancellationReUse);
                    var CancellationWaste = JSON.parse(result.dtCancellationWaste);
                    var LateOrders = JSON.parse(result.dtLateOrders);
                    var PaymentTypes = JSON.parse(result.dtPaymentTypes);
                    var OrderTypes = JSON.parse(result.dtOrderTypes);
                    var BranchSales = JSON.parse(result.dtBranchSales);
                    var TopItems = JSON.parse(result.dtTopItems);
                    var CountryData = JSON.parse(result.dtCountryData);
                    $('#hdnCurrancyCode').val(CountryData[0].Currency);

                    
                    $('.currancy').each(function (index) {
                        $(this).text(CountryData[0].Currency);
                        $(this).val(CountryData[0].Currency);
                    })


                    BindTotalSales(TotalSales);
                    BindTotalDiscount(TotalDiscount);
                    BindCancellationReUse(CancellationReUse);
                    BindCancellationWaste(CancellationWaste);
                    BindLateOrders(LateOrders);
                    BindPaymentTypes(PaymentTypes);
                    BindOrderTypes(OrderTypes);
                    BindBranchWiseSalesChart(BranchSales);
                    genHourlyWiseSalesBarGraphForMainView(result.hourlyWiseSalesData);
                    BindTopItems(TopItems);

                    /*End Sales Tab Data Bind*/
                }
                else if (selectedTabName == "PaymentTypeDetails") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#LateOrderDetailsView').hide();
                    var PaymentTypesSummaryData = JSON.parse(result.dtPaymentTypesSummaryData);
                    BindDetailsSummaryDataTable(PaymentTypesSummaryData);
                }
                else if (selectedTabName == "SalesDetailsView") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').hide();
                    $('#LateOrderDetailsView').hide();
                    $('#SalesTabSalesDetailsView').html(result.view);
                    genTotalSalesLineGraph(result.totalSalesLineChartData);
                    $('#SalesShowDefaultValue').val(showDefaultValueflg);
                }
                else if (selectedTabName == "LateOrderDetails") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#HoursWiseSalesDataView').hide();
                    var LateOrdersSummaryData = JSON.parse(result.dtLateOrdersSummaryData);
                    BindDetailsSummaryDataTable(LateOrdersSummaryData);
                }
                else if (selectedTabName == "TopItemsDetails") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#HoursWiseSalesDataView').hide();
                    var dtTopItemsSummaryData = JSON.parse(result.dtTopItemsSummaryData);
                    BindDetailsSummaryDataTable(dtTopItemsSummaryData);
                }



                else if (selectedTabName == "DiscountWiseItems") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#LateOrderDetailsView').hide();
                    var PaymentTypesSummaryData = JSON.parse(result.dtPaymentTypesSummaryData);
                    BindDetailsSummaryDataTable(PaymentTypesSummaryData);
                }
                else if (selectedTabName == "DeletedReUseWiseItems") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#LateOrderDetailsView').hide();
                    var PaymentTypesSummaryData = JSON.parse(result.dtPaymentTypesSummaryData);
                    BindDetailsSummaryDataTable(PaymentTypesSummaryData);
                }
                else if (selectedTabName == "DeletedWasteWiseItems") {
                    $('#SalesTabMainView').hide();
                    $('#SalesTabDetailsView').show();
                    $('#LateOrderDetailsView').hide();
                    var PaymentTypesSummaryData = JSON.parse(result.dtPaymentTypesSummaryData);
                    BindDetailsSummaryDataTable(PaymentTypesSummaryData);
                }
            } else {
                ShowDashboardMessage("No data for the selected filters. Please try again.");
            }
        },
        error: function (xhr) { // if error occured
            hideLoading();
        },
        complete: function () {
            hideLoading();
        },
    });
}

/*Start Sales Tab Data Bind*/
function BindTotalSales(objdata) {
    $('#lblTotalSalesAmount').text(objdata[0].TotalSales);
    $('#lblTotalOrderCount').text(objdata[0].OrderCount);
}
function BindTotalDiscount(objdata) {
    $('#lblTotalDiscountAmount').text(objdata[0].TotalDiscount);
    $('#lblTotalDiscountOrderCount').text(objdata[0].OrderCount);
}
function BindCancellationReUse(objdata) {
    $('#lblCancellationReUseAmount').text(objdata[0].TotalDelItems);
    $('#lblCancellationReUseCount').text(objdata[0].CountDelItems);
}
function BindCancellationWaste(objdata) {
    $('#lblCancellationWasteAmount').text(objdata[0].TotalWasteItems);
    $('#lblCancellationWasteCount').text(objdata[0].CountWasteItems);
}
function BindLateOrders(objdata) {
    $('#tbodyLateOrders').html("");
    var strHtml = "";
    $.each(objdata, function (index, value) {
        strHtml += '<tr>' +
            '<td>' + value.BranchName + '</td>' +
            '<td>' + value.LateOrderCount + '</td>' +
            '<td>' + value.TotalOrders + '</td>' +
            '</tr>'
    });
    $('#tbodyLateOrders').html(strHtml);
}
function BindPaymentTypes(objdata) {
    $('#tbodyPaymentTypes').html("");
    var strHtml = "";
    $.each(objdata, function (index, value) {
        strHtml += '<tr>' +
            '<td>' + value.Name + '</td>' +
            '<td>' + value.orders + '</td>' +
            '<td>' + value.Total + '</td>' +
            '</tr>'
    });
    $('#tbodyPaymentTypes').html(strHtml);
}

function BindOrderTypes(objdata) {
    $('#tbodyOrderTypes').html("");
    var strHtml = "";
    $.each(objdata, function (index, value) {
        //sorting not working proper db side 
        if (value.Name == "zzzzzTotal") {
            value.Name = "Total";
        }
        strHtml += '<tr>' +
            '<td>' + value.Name + '</td>' +
            '<td>' + value.TotalOrders + '</td>' +
            '<td>' + value.TotalSales + '</td>' +
            '</tr>'
    });
    $('#tbodyOrderTypes').html(strHtml);
}
function BindBranchWiseSalesChart(BranchWiseSalesData) {
    if (BranchWiseSalesData.length > 0) {
        //$('#chartBranchSales').empty();
        var _data = [], labels = [], orders = [];
        for (var i = 0; i < BranchWiseSalesData.length; i++) {
            var name = BranchWiseSalesData[i].BranchName;
            var value = BranchWiseSalesData[i].OrderTotalAmt;
            var order = BranchWiseSalesData[i].OrderCount;
            _data.push(value);
            labels.push(name);
            orders.push(order);
        }
        const data = {
            labels: labels,
            datasets: [{
                axis: 'y',
                label: 'Total Sales Amount',
                data: _data,
                fill: false,
                backgroundColor: [
                    'rgba(54, 215, 183, 1)',

                ],
                borderColor: [
                    'rgb(255, 99, 132)',
                    'rgb(255, 159, 64)',
                    'rgb(255, 205, 86)',
                    'rgb(75, 192, 192)',
                    'rgb(54, 162, 235)',
                    'rgb(153, 102, 255)',
                    'rgb(201, 203, 207)'
                ],
                borderWidth: 1
            }, {
                axis: 'y',
                label: 'Total Orders',
                data: orders,
                fill: false,
                backgroundColor: [
                    'rgba(241, 169, 160, 1)',
                ],
                borderColor: [
                    'rgb(255, 99, 132)',
                    'rgb(255, 159, 64)',
                    'rgb(255, 205, 86)',
                    'rgb(75, 192, 192)',
                    'rgb(54, 162, 235)',
                    'rgb(153, 102, 255)',
                    'rgb(201, 203, 207)'
                ],
                borderWidth: 1
            }]
        };
        Chart.register(ChartDataLabels);
        const config = {
            type: 'bar',
            data: data,
            options: {
                indexAxis: 'y',
                plugins: {
                    datalabels: {
                        align: 'end',
                        formatter: (val) => (`${val}`),
                    }
                },
                responsive: true
            }
        };

        var ctx = $('#chartBranchSales');
        //myChart.destroy();
        //if (window.chartBranchSales instanceof Chart) {
        //    window.chartBranchSales.destroy();
        //}
        //const myChart = new Chart(
        //    ctx,
        //    config
        //);

        if (BranchWiseSalesChart != undefined)
            BranchWiseSalesChart.destroy();
        BranchWiseSalesChart = new Chart(
            ctx,
            config
        );
    }
    else {
        if (BranchWiseSalesChart != undefined)
            BranchWiseSalesChart.destroy();
    }

}
function BindTopItems(objdata) {
    $('#tbodyTopItems').html("");
    var strHtml = "";
    $.each(objdata, function (index, value) {
        strHtml += '<tr>' +
            '<td>' + value.itemName + '</td>' +
            '<td>' + value.SoldItems + '</td>' +
            '<td>' + value.Total + '</td>' +
            '</tr>'
    });
    $('#tbodyTopItems').html(strHtml);
}
function BindDetailsSummaryDataTable(lateOrderData) {

    if (lateOrderData.length > 0) {
        var dynamicColumns = [];
        var i = 0;
        $.each(lateOrderData[0], function (key, value) {
            var obj = { sTitle: key };
            dynamicColumns[i] = obj;
            i++;
        });

        var rowDataSet = [];
        var i = 0;
        $.each(lateOrderData, function (key, value) {
            var rowData = [];
            var j = 0;
            $.each(lateOrderData[i], function (key, value) {
                rowData[j] = value;
                j++;
            });
            rowDataSet[i] = rowData;
            i++;
        });


        $('#detailsviewdatatableMainDiv').html('<table class="table table - bordered table - checkable dataTable no - footer dtr - inline mt - 0" id="grd_PaymentTypesSummary"></table>');


        if ($.fn.DataTable.isDataTable('#grd_PaymentTypesSummary')) {
            $('#grd_PaymentTypesSummary').DataTable().destroy();
        }

        //$('#grd_PaymentTypesSummary tbody').empty();
        //$('#grd_PaymentTypesSummary').html("");
        grd_DetailsSummarytable = $('#grd_PaymentTypesSummary');
        // begin first table
        grd_DetailsSummarytable.DataTable({
            responsive: true,
            "lengthChange": false,
            //"processing": true,
            //"serverSide": true,
            "drawCallback": function (settings) {
                //setSelectedInvoices();
                $('.comments-popover').popover({
                    container: 'body'
                });
            },
            dom: 'Bfrtip',
            buttons: [
                'copy', 'excel', 'pdf', 'print'
            ],
            columns: dynamicColumns,
            data: rowDataSet,
            select: {
                style: 'os',
                selector: 'td:first-child'
            },
            //"order": [[15, "asc"]],
        });
    }
    else {
        $('#grd_PaymentTypesSummary').html("");
        $('#grd_PaymentTypesSummary').empty();
        if ($.fn.DataTable.isDataTable('#grd_PaymentTypesSummary')) {
            $('#grd_PaymentTypesSummary').DataTable().destroy();
        }

        $('#grd_PaymentTypesSummary tbody').empty();
    }

}
/*End Sales Tab Data Bind*/



jQuery(document).on('keydown', 'input.OnlyNumber', function (ev) {

    if (event.shiftKey == true) {
        event.preventDefault();
    }

    if ((event.keyCode >= 48 && event.keyCode <= 57) ||
        (event.keyCode >= 96 && event.keyCode <= 105) ||
        event.keyCode == 8 || event.keyCode == 9 || event.keyCode == 37 ||
        event.keyCode == 39 || event.keyCode == 46 || event.keyCode == 190 || event.keyCode == 110) { } else {
        event.preventDefault();
    }
    //if ($(this).val().indexOf('-') != -1 && (event.keyCode == 189 || event.keyCode == 109)) {
    //    event.preventDefault();
    //}
    //if ($(this).val().indexOf('+') != -1 && (event.keyCode == 187 || event.keyCode == 107)) {
    //    event.preventDefault();
    //}
    //if a decimal has been added, disable the "."-button
});

function bindLateOrderDetailsData() {
    selectedTabName = "LateOrderDetails";
    $('#detailsviewHeader').html("Late Order Details Summary");
    //GetLateOrderDetailsData();
    GetReportDashboardData();
}

function bindTopItemsDetailsData() {
    selectedTabName = "TopItemsDetails";
    $('#detailsviewHeader').html("Top Items Details Summary");
    //GetLateOrderDetailsData();
    GetReportDashboardData();
}

function bindPaymentTypeDetails() {
    selectedTabName = "PaymentTypeDetails";
    $('#detailsviewHeader').html("Payment Type Summary");
    GetReportDashboardData();
}
function bindDiscountWiseDetails() {
    selectedTabName = "DiscountWiseItems";
    $('#detailsviewHeader').html("Discount Wise Items Summary");
    GetReportDashboardData();
}
function bindDeletedReUseWiseItemsDetails() {
    selectedTabName = "DeletedReUseWiseItems";
    $('#detailsviewHeader').html("Deleted Re-Use Wise Items Summary");
    GetReportDashboardData();
}
function bindDeletedWasteWiseItemsDetails() {
    selectedTabName = "DeletedWasteWiseItems";
    $('#detailsviewHeader').html("Deleted Waste Wise Items Summary");
    GetReportDashboardData();
}
// GetEndDates() and the commented-out apply.daterangepicker block that called
// it lived here. Both belonged to the Operation Day / end-shift filter, which
// no longer exists on the page - the live apply handler is in
// InitDateRangePicker() at the top of this file.

function BackToMainTab() {
    selectedTabName = "sales-tab-md";
    GetReportDashboardData();
    //$('#SalesTabMainView').show();
    //$('#SalesTabDetailsView').hide();
}
$(document).on("click", ".reporttotalsales", function () {
    GetTotalSalesData();
});

function GetTotalSalesData() {
    selectedTabName = "SalesDetailsView";
    var _LateMinDuration = $('#txtLateMinDuration').val() == undefined ? 70 : parseInt($('#txtLateMinDuration').val());
    if (isNaN(_LateMinDuration)) {
        _LateMinDuration = "0";
    }
    showLoading();

    $.ajax({
        type: "POST",
        cache: false,
        data: {
            CountryId: $('#drpCountry').val(),
            FromDate: $('#StartDate').val(),
            ToDate: $('#EndDate').val(),
            locationIDs: $('#drpLocations').val(),
            BrandIDs: $('#drpBrands').val(),
            orderTypeIDs: $('#drpOrdertypes').val(),
            paymentTypeIDs: $('#drpPaymenttypes').val(),
            LateMinDuration: _LateMinDuration,
            SelectedTab: selectedTabName,
            GroupByFlag: $('#HourlyChartGroupBy').val(),
            ShowDefaultValueFlag: $('#ShowDefaultValue').val(),
            IsDefaultLoad: true
        },
        url: DASH.data,
        beforeSend: function () {
            showLoading();
        },
        success: function (result) {
            hideLoading();
            if (result.Message == "Success") {
                //debugger;
                $('#SalesTabMainView').hide();
                $('#SalesTabDetailsView').hide();
                $('#SalesTabSalesDetailsView').html(result.view);
                genTotalSalesLineGraph(result.totalSalesLineChartData);
                //$('.totalSalesPivotTable').DataTable();
            }
            else {
                $("#message").html("Please try again.");
                $('#alert').modal("toggle");
            }

        },
        error: function (xhr) { // if error occured
            hideLoading();
        },
        complete: function () {
            hideLoading();
        },
    });
}

function genTotalSalesLineGraph(lineChartData) {
    data = [
        { name: "Hawally", data: { "2021-10-05": 548.600 } },
        { name: "Salhiya", data: { "2021-10-05": 490.700 } },
        { name: "Ardiya", data: { "2021-10-05": 423.600 } },
        { name: "Fintas", data: { "2021-10-05": 303.950 } }
    ] // Example Data
    new Chartkick.LineChart("totalsalelinechart", lineChartData, { adapter: "highcharts" });
}

$(document).on("click", ".hourwisesalesbreakdown", function () {
    $('.daysdropdown').show();
    GetHoursWiseSalesData();
});



function GetHoursWiseSalesData() {
    selectedTabName = "HoursWiseSalesDataView";
    var _LateMinDuration = $('#txtLateMinDuration').val() == undefined ? 70 : parseInt($('#txtLateMinDuration').val());
    if (isNaN(_LateMinDuration)) {
        _LateMinDuration = "0";
    }
    showLoading();

    $.ajax({
        type: "POST",
        cache: false,
        data: {
            CountryId: $('#drpCountry').val(),
            FromDate: $('#StartDate').val(),
            ToDate: $('#EndDate').val(),
            locationIDs: $('#drpLocations').val(),
            BrandIDs: $('#drpBrands').val(),
            orderTypeIDs: $('#drpOrdertypes').val(),
            paymentTypeIDs: $('#drpPaymenttypes').val(),
            LateMinDuration: _LateMinDuration,
            SelectedTab: selectedTabName,
            GroupByFlag: $('#HourlyChartGroupBy').val(),
            ShowDefaultValueFlag: $('#ShowDefaultValue').val(),
            IsDefaultLoad: true
        },
        url: DASH.data,
        beforeSend: function () {
            showLoading();
        },
        success: function (result) {
            hideLoading();
            if (result.Message == "Success") {
                //debugger;
                $('#SalesTabMainView').hide();
                $('#SalesTabDetailsView').hide();
                $('#SalesTabSalesDetailsView').html("");
                $('#HoursWiseSalesDataView').show();
                $('#HoursWiseSalesDataView').html(result.view);
                $('#HourlyChartGroupBy').val(result.GroupByFlag);
                genHourlyWiseSalesBarGraph(result.hourlyWiseSalesData);
            }
            else {
                $("#message").html("Please try again.");
                $('#alert').modal("toggle");
            }

        },
        error: function (xhr) { // if error occured
            hideLoading();
        },
        complete: function () {
            hideLoading();
        },
    });
}

function genHourlyWiseSalesBarGraphForMainView(hourlyWiseSalesData) {
    //data = [{
    //    "name": "Hawally", "data":
    //        [["11-12", 112],
    //        ["12-13", 298],
    //        ["13-14", 118],
    //        ["14-15", 118],
    //        ["15-16", 118],
    //        ["16-17", 118],
    //        ["17-18", 118],
    //        ["18-19", 118],
    //        ["19-20", 118],
    //        ["21-22", 118],
    //        ["22-23", 118],
    //        ["23-00", 118],
    //        ["00-01", 118],
    //        ["01-02", 118],
    //        ["02-03", 118],
    //        ["03-04", 118],
    //        ["04-05", 118],
    //        ["05-06", 118],
    //        ["06-07", 118],
    //        ["07-08", 118],
    //        ["08-09", 118],
    //        ["09-10", 118],
    //        ["10-11", 118]
    //        ]
    //},
    //{
    //    "name": "Salhiya",
    //    "data":
    //        [["11-12", 112],
    //        ["12-13", 298],
    //        ["13-14", 118],
    //        ["14-15", 118],
    //        ["15-16", 118],
    //        ["16-17", 118],
    //        ["17-18", 118],
    //        ["18-19", 118],
    //        ["19-20", 118],
    //        ["21-22", 118],
    //        ["22-23", 118],
    //        ["23-00", 118],
    //        ["00-01", 118],
    //        ["01-02", 118],
    //        ["02-03", 118],
    //        ["03-04", 118],
    //        ["04-05", 118],
    //        ["05-06", 118],
    //        ["06-07", 118],
    //        ["07-08", 118],
    //        ["08-09", 118],
    //        ["09-10", 118],
    //        ["10-11", 118]]
    //}]// Example Data
    new Chartkick.LineChart("hourswisesalesbarchartForMainView", hourlyWiseSalesData, { adapter: "highcharts" }, { discrete: true });
}
function genHourlyWiseSalesBarGraph(hourlyWiseSalesData) {
    new Chartkick.LineChart("hourswisesalesbarchart", hourlyWiseSalesData, { adapter: "highcharts" });
}

$(document.body).on("change", "#HourlyChartGroupBy", function () {
    selectedTabName = "HoursWiseSalesDataView";
    GetHoursWiseSalesData();
});


$(document.body).on("change", "#SalesShowDefaultValue", function () {
    selectedTabName = "SalesDetailsView";
    GetReportDashboardData();
});
//function GetLateOrderDetailsData() {
//    debugger;
//    //$('#reportView').html("");
//    $('#myTabContentMD').hide();
//    $('#LateDeliveryDetailsReport').show();
//    $('#lblHeaderOfDetailsView').text("Late Delivered Orders Data");
//    var _LateMinDuration = $('#txtLateMinDuration').val() == undefined ? 70 : parseInt($('#txtLateMinDuration').val());
//    if (isNaN(_LateMinDuration)) {
//        _LateMinDuration = "0";
//    }

//    var _IsDetailsData = false;
//    if ($('#LateDeliveryDetailsReport').css('display') != 'none') {
//        _IsDetailsData = true;
//    }
//    $.ajax({
//        type: "POST",
//        cache: false,
//        data: {
//            FromDate: $('#StartDate').val(),
//            ToDate: $('#EndDate').val(),
//            locationIDs: $('#locations').val(),
//            orderTypeIDs: $('#ordertypes').val(),
//            paymentTypeIDs: $('#paymenttypes').val(),
//            endDates: $('#daysdropdowns').val(),
//            LateMinDuration: _LateMinDuration,
//            IsDetailsData: _IsDetailsData
//        },
//        url: "/ReportDashboard/GetLateOrdersReportData",
//        beforeSend: function () {
//            showLoading();
//        },
//        success: function (result) {
//            debugger;
//            if (result.Message == "Success") {
//                var lateOrderData = JSON.parse(result.lateOrdersBranchWise);
//                BindLateOrdersDataTable(lateOrderData);
//            }
//        },
//        error: function (xhr) { // if error occured
//            hideLoading();
//        },
//        complete: function () {
//            hideLoading();
//        },
//    });
//}
$(document.body).on("change", "#HourlyChartGroupByForMainView,#ShowDefaultValue", function () {
    selectedTabName = "sales-tab-md";
    GetReportDashboardData();
});


$(document.body).on("change", "#drpCountry", function () {
    GetFilterData();
});

// Apply is the only thing that reloads. Changing a dropdown or picking a new
// date range stages the change; this sends the whole filter set at once.
function ApplybuttonClick() {
    GetReportDashboardData();
}

$(document).on("click", ".exportToExcel", function () {
    download_table_as_csv();
});

function download_table_as_csv(separator = ',') {

    var rows = $('.totalSalesPivotTable tr');
    var csv = [];
    var lastrow = []; var repeatrowval = [];
    var tabledata = [];
    var cols = $('.totalSalesPivotTable > thead > tr:last > th').length; $('.totalSalesPivotTable > thead > tr:last > th').attr('rowSpan', '1');
    for (var i = 0; i < cols; i++) { repeatrowval.push(1); lastrow.push('none') }
    for (var i = 0; i < rows.length; i++) {
        console.log("row: " + i)
        var row = []; var col = rows[i].querySelectorAll('td, th');
        var col_len = 0;
        for (var j = 0; j < cols; j++) {
            var a = 0;
            console.log(repeatrowval[j]);
            if (repeatrowval[j] > 1) {
                data = lastrow[j]; repeatrowval[j] = repeatrowval[j] - 1;
                console.log("row: " + i + " reapet_col: " + j + " = " + data);
                row.push('"' + data + '"');
            } else {
                if (col[col_len] === undefined) break;
                var colspan = col[col_len].colSpan ?? 1;
                console.log("col: " + j + ", colspan = " + colspan + ", repeatrowval: " + repeatrowval[j])
                var headerName = "";
                for (var r = 0; r < colspan; r++) {

                    var rowspan = col[col_len].rowSpan ?? 1;
                    if (rowspan == 1) {
                        var data = col[col_len].innerText.replace(/(\r\n|\n|\r)/gm, '').replace(/(\s\s)/gm, ' ')
                        var _headerName = col[col_len].innerText.replace(/(\r\n|\n|\r)/gm, '').replace(/(\s\s)/gm, ' ')
                        data = data.replace(/"/g, '""');
                        if (i == 0 && data == headerName)
                            data = "";
                        repeatrowval[j] = 1;
                        lastrow[j] = data
                    } else {
                        var data = col[col_len].innerText.replace(/(\r\n|\n|\r)/gm, '').replace(/(\s\s)/gm, ' ')
                        var _headerName = col[col_len].innerText.replace(/(\r\n|\n|\r)/gm, '').replace(/(\s\s)/gm, ' ')
                        data = data.replace(/"/g, '""');
                        if (i == 0 && data == headerName)
                            data = "";
                        lastrow[j] = data; repeatrowval[j] = rowspan;
                    }
                    console.log("row: " + i + " col: " + j + " = " + data);
                    row.push('"' + data + '"');
                    headerName = _headerName;
                    if (colspan > 1) { a++ };
                }
                col_len++
            }
            if (a > 0) { j = +a };
        }
        csv.push(row.join(separator));
        tabledata.push(row);
    }
    var csv_string = csv.join('\n');
    var filename = 'totalSales_' + new Date().toLocaleDateString() + '.csv';
    var link = document.createElement('a');
    link.style.display = 'none';
    link.setAttribute('target', '_blank');
    link.setAttribute('href', 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv_string));
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}