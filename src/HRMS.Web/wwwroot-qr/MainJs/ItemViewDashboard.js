var DataGridData;
var dataAdapter1;
var dataAdapter2;
var dataAdapter3;
var dataAdapter4;
$(function () {
    
    var start = moment().subtract(0, 'days');
    var end = moment();

    function cb(start, end) {
        $('#reportrange span').html(start.format('MMMM D, YYYY') + ' - ' + end.format('MMMM D, YYYY'));
        $('#FromDate').val(start.format('YYYY-M-DD'));
        $('#ToDate').val(end.format('YYYY-M-DD'));
        GetData(start.format('YYYY-M-DD'), end.format('YYYY-M-DD'));
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

    cb(start, end);

});
$(document).ready(function () {
    debugger;
    var today = new Date();
    var FromDate = today.getFullYear() + '-' + ('0' + (today.getMonth() + 1)).slice(-2) + '-' + ('0' + today.getDate()).slice(-2);
    var ToDate = FromDate;
    $('#FromDate').val(FromDate);
    $('#ToDate').val(ToDate);

    GetData(FromDate, ToDate);

});

function GetData(FromDate, ToDate) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: {
            BrandId: $('#hdnBrandId').val(),
            FromDate: $('#FromDate').val(),
            ToDate: $('#ToDate').val()
        },
        url: "/ItemViewDashboard/GetAuditReportsData",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                BindCharts(result);
            }
        }
    });

    BindCategoryVisitListData();
    BindItemsVisitListData();
}

function BindCharts(ChartData) {
    BindTopCards(ChartData.TopCardsDetails);
    BindFirstChart(ChartData.FirstChart);
    BindSecondChart(ChartData.SecondChart);
    BindThirdChart(ChartData.ThirdChart);
    BindFourthChart(ChartData.FourthChart);
}

function BindTopCards(data) {
    var dets = JSON.parse(data);

    $("#TotalCustomers").text(dets[0].TotalCustomers);
    //$('#TotalCustomers').val(dets[0].TotalCustomers);

    $('#TopCategory').text(dets[0].TopCategory);
    $('#TopCategoryCount').text(dets[0].TopCategoryCount);

    $('#TopItem').text(dets[0].TopItem);
    $('#TopItemCount').text(dets[0].TopItemCount);
}
function BindFirstChart(JsonData) {
    debugger;
    var data = JSON.parse(JsonData);
    if (data.length == 0) {
        $('#FirstChart').html("");
        return false;
    }
    var maxval = getMax(data, "VisitorsCount");
    var Minval = getMin(data, "VisitorsCount");
    var dataAdapter = new $.jqx.dataAdapter(data, {
        contentType: 'application/json; charset=utf-8',
        async: false,
        autoBind: true,
        loadError: function (xhr, status, error) {
            alert('loading "' + source.url + '" : ' + error);
        }
    });
    var TableT = {
        dataType: "json",
        //cache: false,
        datafields: [{
            name: 'branchName',
            type: 'string'
        },
        {
            name: 'VisitorsCount',
            type: 'number'
        }
        ],
        //id: "QuestionId",
        localdata: data,
        //sortcolumn: 'ITEM_NAME',
    };
    dataAdapter1 = new $.jqx.dataAdapter(TableT);

    // prepare jqxChart settings
    var settings = {
        title: "Branch wise visit",
        description: "",
        enableAnimations: true,
        showLegend: true,
        padding: { left: 2, top: 2, right: 2, bottom: 2 },
        titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
        source: dataAdapter1,
        colorScheme: 'scheme01',

        xAxis: {
            //dataField: 'Day',
            dataField: 'branchName',
            //unitInterval: 1,
            tickMarks: { visible: true, interval: 1 },
            gridLinesInterval: { visible: true, interval: 1 },
            valuesOnTicks: false,
            padding: { bottom: 2 },
            gridLinesColor: 'white',
            //textRotationAngle: 90
        },
        valueAxis: {
            //flip: true,
            //unitInterval: 250,
            minValue: Minval,
            maxValue: maxval,
            axisSize: 'auto',
            gridLinesColor: 'white',
            visible: true,
            //  title: { text: 'Time in minutes<br><br>' },
            //labels: { horizontalAlignment: 'left' }
            //labels: { horizontalAlignment: 'left' }
        },

        seriesGroups:
            [
                {
                    type: 'column',
                    orientation: 'vertical',
                    //orientation: 'horizontal',
                    series:
                        [
                            {
                                //dataField: 'Swimming',
                                dataField: 'VisitorsCount',
                                symbolType: 'square',
                                //color: '#66bb6a',
                                labels:
                                    {
                                        visible: true,
                                        //backgroundColor: '#FEFEFE',
                                        backgroundOpacity: 0.2,
                                        //borderColor: '#7FC4EF',
                                        borderOpacity: 0.7,
                                        padding: { left: 2, right: 2, top: 0, bottom: 0 },

                                    }
                            },
                        ],
                    //click: myChildHandler1
                }
            ]

    };
    //click: myChildHandler, 
    // setup the chart
    $('#FirstChart').jqxChart(settings);

    /*function myEventHandler(event) {
        debugger;
        var eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, Value: </b>' + event.args.elementValue + "</div>";
        //if (event.type == 'toggle')
        //    eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, visible: </b>' + event.args.state + "</div>";
        //$('#eventText').html(eventData);
        alert(eventData);
    };
    $('#FirstChart').on('click toggle', function (event) {
    if (event.args)
        myEventHandler(event); 
    });*/


}
function BindSecondChart(JsonData) {
    debugger;
    var data = JSON.parse(JsonData);
    if (data.length == 0) {
        $('#SecondChart').html("");
        return false;
    }
    //var maxval = getMax(data, "VisitorsCount");
    //var Minval = getMin(data, "VisitorsCount");
    var dataAdapter = new $.jqx.dataAdapter(data, {
        contentType: 'application/json; charset=utf-8',
        async: false,
        autoBind: true,
        loadError: function (xhr, status, error) {
            alert('loading "' + source.url + '" : ' + error);
        }
    });

    //var columns = data.columns;
    //var datafieldsc = new Array();
    //for (var i = 0; i < columns.length; i++) {
    //    datafieldsc.push({ name: columns[i].datafield });
    //}

    var TableT = {
        dataType: "json",
        //cache: false,

        //datafields: [{
        //    name: 'DeviceModal',
        //    type: 'string'
        //},
        //{
        //    name: 'VisitorsCount',
        //    type: 'number'
        //}
        //],
        datafields: data.datafields,
        localdata: data,
        //sortcolumn: 'ITEM_NAME',
    };
    dataAdapter1 = new $.jqx.dataAdapter(TableT);

    var dfcols = new Array();

    for (var i = 1; i < data.datafields.length - 1; i++) {
        dfcols.push({ name: data.datafields[i].name });
    }

    // prepare jqxChart settings
    var settings = {
        title: "Device wise visitors",
        description: "",
        enableAnimations: true,
        showLegend: true,
        padding: { left: 2, top: 2, right: 2, bottom: 2 },
        titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
        source: dataAdapter1,
        colorScheme: 'scheme01',

        xAxis: {
            //dataField: 'Day',
            dataField: 'DeviceModal',
            //unitInterval: 1,
            tickMarks: { visible: true, interval: 1 },
            gridLinesInterval: { visible: true, interval: 1 },
            valuesOnTicks: false,
            padding: { bottom: 2 },
            gridLinesColor: 'white',
            //textRotationAngle: 90
        },
        valueAxis: {
            //flip: true,
            //unitInterval: 250,
            minValue: 0,
            //maxValue: maxval,
            //unitInterval: 1,
            axisSize: 'auto',
            gridLinesColor: 'white',
            visible: true,
            //  title: { text: 'Time in minutes<br><br>' },
            //labels: { horizontalAlignment: 'left' }
            //labels: { horizontalAlignment: 'left' }
        },

        seriesGroups:
            [
                {
                    type: 'column',
                    orientation: 'vertical',
                    series:
                        [
                            {
                                //dataField: 'Swimming',
                                //dataField: 'VisitorsCount',
                                dataField: dfcols[0].name,
                                symbolType: 'square',
                                //color: '#66bb6a',
                                labels:
                                    {
                                        visible: true,
                                        //backgroundColor: '#FEFEFE',
                                        backgroundOpacity: 0.2,
                                        //borderColor: '#7FC4EF',
                                        borderOpacity: 0.7,
                                        padding: { left: 2, right: 2, top: 0, bottom: 0 },

                                    }
                            },
                        ],

                    //click: myChildHandler1
                }
            ]

    };
    //click: myChildHandler, 
    // setup the chart
    $('#SecondChart').jqxChart(settings);

    var groups = $('#SecondChart').jqxChart('seriesGroups');
    //groups[0].series[0].dataField = dfcols;

    for (var i = 1; i < dfcols.length; i++) {

        groups[0].series.push({
            //dataField: 'Swimming',
            //dataField: 'VisitorsCount',
            dataField: dfcols[i].name,
            symbolType: 'square',
            //color: dfcolscolor[i].name, //'#66bb6a',
            labels:
                {
                    visible: true,
                    //backgroundColor: dfcolscolor[i].name, //'#FEFEFE',
                    backgroundOpacity: 0.2,
                    //borderColor: '#7FC4EF',
                    borderOpacity: 0.7,
                    padding: { left: 2, right: 2, top: 0, bottom: 0 },

                }
        });
    }

    $('#SecondChart').jqxChart("refresh");

    /*function myEventHandler(event) {
        debugger;
        var eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, Value: </b>' + event.args.elementValue + "</div>";
        //if (event.type == 'toggle')
        //    eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, visible: </b>' + event.args.state + "</div>";
        //$('#eventText').html(eventData);
        alert(eventData);
    };
    $('#FirstChart').on('click toggle', function (event) {
    if (event.args)
        myEventHandler(event); 
    });*/


}
function BindThirdChart(JsonData) {
    debugger;
    var data = JSON.parse(JsonData);
    if (data.length == 0) {
        $('#ThirdChart').html("");
        return false;
    }
    var maxval = getMax(data, "VisitorsCount");
    var Minval = getMin(data, "VisitorsCount");
    var dataAdapter = new $.jqx.dataAdapter(data, {
        contentType: 'application/json; charset=utf-8',
        async: false,
        autoBind: true,
        loadError: function (xhr, status, error) {
            alert('loading "' + source.url + '" : ' + error);
        }
    });
    var TableT = {
        dataType: "json",
        //cache: false,
        datafields: [{
            name: 'CAT_NAME',
            type: 'string'
        },
        {
            name: 'VisitorsCount',
            type: 'number'
        }
        ],
        //id: "QuestionId",
        localdata: data,
        //sortcolumn: 'ITEM_NAME',
    };
    dataAdapter1 = new $.jqx.dataAdapter(TableT);

    // prepare jqxChart settings
    var settings = {
        title: "Category Wise visitors",
        description: "",
        enableAnimations: true,
        showLegend: true,
        padding: { left: 2, top: 2, right: 2, bottom: 2 },
        titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
        source: dataAdapter1,
        colorScheme: 'scheme01',

        xAxis: {
            //dataField: 'Day',
            dataField: 'CAT_NAME',
            //unitInterval: 1,
            tickMarks: { visible: true, interval: 1 },
            gridLinesInterval: { visible: true, interval: 1 },
            valuesOnTicks: false,
            padding: { bottom: 2 },
            gridLinesColor: 'white',
            textRotationAngle: 90
        },
        valueAxis: {
            flip: true,
            //unitInterval: 250,
            minValue: Minval,
            maxValue: maxval,
            axisSize: 'auto',
            gridLinesColor: 'white',
            visible: false,
            //  title: { text: 'Time in minutes<br><br>' },
            //labels: { horizontalAlignment: 'left' }
            //labels: { horizontalAlignment: 'left' }
        },

        seriesGroups:
            [
                {
                    type: 'column',
                    orientation: 'horizontal',
                    //orientation: 'horizontal',
                    series:
                        [
                            {
                                //dataField: 'Swimming',
                                dataField: 'VisitorsCount',
                                symbolType: 'square',
                                //color: '#66bb6a',
                                labels:
                                    {
                                        visible: true,
                                        //backgroundColor: '#FEFEFE',
                                        backgroundOpacity: 0.2,
                                        //borderColor: '#7FC4EF',
                                        borderOpacity: 0.7,
                                        padding: { left: 2, right: 2, top: 0, bottom: 0 },

                                    }
                            },
                        ],
                    //click: myChildHandler1
                }
            ]

    };
    //click: myChildHandler, 
    // setup the chart
    $('#ThirdChart').jqxChart(settings);

    /*function myEventHandler(event) {
        debugger;
        var eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, Value: </b>' + event.args.elementValue + "</div>";
        //if (event.type == 'toggle')
        //    eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, visible: </b>' + event.args.state + "</div>";
        //$('#eventText').html(eventData);
        alert(eventData);
    };
    $('#FirstChart').on('click toggle', function (event) {
    if (event.args)
        myEventHandler(event); 
    });*/


}
function BindFourthChart(JsonData) {
    debugger;
    var data = JSON.parse(JsonData);
    if (data.length == 0) {
        $('#FourthChart').html("");
        return false;
    }
    var maxval = getMax(data, "VisitorsCount");
    var Minval = getMin(data, "VisitorsCount");
    var dataAdapter = new $.jqx.dataAdapter(data, {
        contentType: 'application/json; charset=utf-8',
        async: false,
        autoBind: true,
        loadError: function (xhr, status, error) {
            alert('loading "' + source.url + '" : ' + error);
        }
    });
    var TableT = {
        dataType: "json",
        //cache: false,
        datafields: [{
            name: 'ITEM_NAME',
            type: 'string'
        },
        {
            name: 'VisitorsCount',
            type: 'number'
        }
        ],
        //id: "QuestionId",
        localdata: data,
        //sortcolumn: 'ITEM_NAME',
    };
    dataAdapter1 = new $.jqx.dataAdapter(TableT);

    // prepare jqxChart settings
    var settings = {
        title: "Top 5 visited Items ",
        description: "",
        enableAnimations: true,
        showLegend: true,
        padding: { left: 2, top: 2, right: 2, bottom: 2 },
        titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
        source: dataAdapter1,
        colorScheme: 'scheme01',

        xAxis: {
            //dataField: 'Day',
            dataField: 'ITEM_NAME',
            //unitInterval: 1,
            tickMarks: { visible: true, interval: 1 },
            gridLinesInterval: { visible: true, interval: 1 },
            valuesOnTicks: false,
            padding: { bottom: 2 },
            gridLinesColor: 'white',
            textRotationAngle: 90
        },
        valueAxis: {
            flip: true,
            //unitInterval: 250,
            minValue: Minval,
            maxValue: maxval,
            axisSize: 'auto',
            gridLinesColor: 'white',
            visible: false,
            //  title: { text: 'Time in minutes<br><br>' },
            //labels: { horizontalAlignment: 'left' }
            //labels: { horizontalAlignment: 'left' }
        },

        seriesGroups:
            [
                {
                    type: 'column',
                    orientation: 'horizontal',
                    //orientation: 'horizontal',
                    series:
                        [
                            {
                                //dataField: 'Swimming',
                                dataField: 'VisitorsCount',
                                symbolType: 'square',
                                //color: '#66bb6a',
                                verticalTextAlignment: "center",
                                labels:
                                    {
                                        visible: true,
                                        //backgroundColor: '#FEFEFE',
                                        backgroundOpacity: 0.2,
                                        //borderColor: '#7FC4EF',
                                        borderOpacity: 0.7,
                                        padding: { left: 2, right: 2, top: 0, bottom: 0 },

                                    }
                            },
                        ],
                    //click: myChildHandler1
                }
            ]

    };
    //click: myChildHandler, 
    // setup the chart
    $('#FourthChart').jqxChart(settings);

    /*function myEventHandler(event) {
        debugger;
        var eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, Value: </b>' + event.args.elementValue + "</div>";
        //if (event.type == 'toggle')
        //    eventData = '<div><b>Last Event: </b>' + event.type + '<b>, Serie DataField: </b>' + event.args.serie.dataField + '<b>, visible: </b>' + event.args.state + "</div>";
        //$('#eventText').html(eventData);
        alert(eventData);
    };
    $('#FirstChart').on('click toggle', function (event) {
    if (event.args)
        myEventHandler(event); 
    });*/


}
function getMax(arr, prop) {
    var max;
    debugger;
    for (var i = 0; i < arr.length; i++) {
        if (parseInt(arr[i][prop] || 0) > parseInt(max || 0))
            max = parseInt(arr[i][prop]);
    }
    max = max + (20 * max / 100)
    return max;
}
function getMin(arr, prop) {
    //var min;
    //for (var i = 0; i < arr.length; i++) {
    //    if (min == null || parseInt(arr[i][prop]) < parseInt(min[prop]))
    //        min = arr[i];
    //}
    //return min;

    var min = 0;
    for (var i = 0; i < arr.length; i++) {
        if (parseInt(arr[i][prop] || 0) < parseInt(min || 0))
            min = parseInt(arr[i][prop]);
    }
    if (min > 0) {
        min = min - 1
    }
    return min;
}


function BindCategoryVisitListData() {
    debugger;
    if ($.fn.DataTable.isDataTable('#grd_CategoryVisit')) {
        $('#grd_CategoryVisit').DataTable().destroy();
    }
    $('#grd_CategoryVisit tbody').empty();

    var table = $('#grd_CategoryVisit');
    // begin first table
    table.DataTable({
        responsive: true,
        "pageLength": 10,
        "order": [[1, "desc"]],
        //"scrollY": "400px",
        //"scrollCollapse": true,
        ajax: {
            url: "/ItemViewDashboard/GetCategoryVisits?BrandId=" + $('#hdnBrandId').val() + "&FromDate=" + $('#FromDate').val() + "&ToDate=" + $('#ToDate').val(),
            type: 'POST',
            data: {
                //pagination: {
                //    perpage: 7,
                //},
            },
        },
        columns: [
            {
                data: 'CategoryName'
            },
            {
                data: 'Visits'
            },
            //{
            //    data: 'InvoiceNo',
            //    responsivePriority: -1
            //},
        ],
        columnDefs: [
            //{
            //    orderable: false,
            //    'targets': 0,
            //    'searchable': false,
            //    'orderable': false,
            //    'className': 'dt-body-center',
            //    'width': '10px',
            //    'render': function (data, type, full, meta) {
            //        return '<input type="checkbox" data-val="' + full.FinalAmount + '" data-val2="' + full.Status + '" onclick="chkInvoiceOnClick(this);" class="clsSelectedInvoice" name="id[]" value="' + $('<div/>').text(data).html() + '">';
            //    }
            //},
        ],
        select: {
            style: 'os',
            selector: 'td:first-child'
        },
    });
}
function BindItemsVisitListData() {
    debugger;
    if ($.fn.DataTable.isDataTable('#grd_ItemsVisit')) {
        $('#grd_ItemsVisit').DataTable().destroy();
    }
    $('#grd_ItemsVisit tbody').empty();


    var table = $('#grd_ItemsVisit');
    // begin first table

    table.DataTable({
        responsive: true,
        "pageLength": 10,
        "order": [[2, "desc"]],
        ajax: {
            url: "/ItemViewDashboard/GetItemsVisits?BrandId=" + $('#hdnBrandId').val()+ "&FromDate=" + $('#FromDate').val() + "&ToDate=" + $('#ToDate').val(),
            type: 'POST',
            data: {
                //pagination: {
                //    perpage: 7,
                //},
            },
        },
        columns: [
            {
                data: 'ItemName'
            },
            {
                data: 'CategoryName'
            },
            {
                data: 'Visits'
            }
        ],
        columnDefs: [
            //{
            //    orderable: false,
            //    'targets': 0,
            //    'searchable': false,
            //    'orderable': false,
            //    'className': 'dt-body-center',
            //    'width': '10px',
            //    'render': function (data, type, full, meta) {
            //        return '<input type="checkbox" data-val="' + full.FinalAmount + '" data-val2="' + full.Status + '" onclick="chkInvoiceOnClick(this);" class="clsSelectedInvoice" name="id[]" value="' + $('<div/>').text(data).html() + '">';
            //    }
            //},
        ],
        select: {
            style: 'os',
            selector: 'td:first-child'
        },
    });
}