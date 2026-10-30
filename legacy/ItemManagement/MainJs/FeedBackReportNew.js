var DataGridData;
var dataAdapter1;
var dataAdapter2;
var dataAdapter3;
var dataAdapter4;
$(function() {

            var start = moment().subtract(0, 'days');
            var end = moment();

            function cb(start, end) {
                $('#reportrange span').html(start.format('MMMM D, YYYY') + ' - ' + end.format('MMMM D, YYYY'));
                $('#FromDate').val(start.format('YYYY-M-DD'));
                $('#ToDate').val(end.format('YYYY-M-DD'));
                GetData(start.format('YYYY-M-DD'),end.format('YYYY-M-DD'));
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
        var today = new Date();
        var FromDate=today.getFullYear() + '-' + ('0' + (today.getMonth() + 1)).slice(-2) + '-' + ('0' + today.getDate()).slice(-2);
        var ToDate=FromDate;
        $('#FromDate').val(FromDate);
        $('#ToDate').val(ToDate);

       GetData(FromDate,ToDate);
      
        /*setInterval(function () { 
            var CurrentDate = new Date();
            CurrentDate = CurrentDate.getFullYear() + "-" + ('0' + (CurrentDate.getMonth() + 1)).slice(-2)  + "-" + ('0' + CurrentDate.getDate()).slice(-2);
            
            var SelectedFromDate = new Date($('#FromDate').val());
            SelectedFromDate = SelectedFromDate.getFullYear() + "-" + ('0' + (SelectedFromDate.getMonth() + 1)).slice(-2) + "-" + ('0' + SelectedFromDate.getDate()).slice(-2);
            
            var SelectedToDate = new Date($('#ToDate').val());
            SelectedToDate = SelectedToDate.getFullYear() + "-" + ('0' + (SelectedToDate.getMonth() + 1)).slice(-2) + "-" +  ('0' + SelectedToDate.getDate()).slice(-2);
           
            if(CurrentDate == SelectedFromDate  || CurrentDate == SelectedToDate){
                GetData(SelectedFromDate,SelectedToDate);
            }
        }, 50000);*/

    });
    
    function GetData(FromDate,ToDate) {
        $.ajax({
            type: "GET",
            cache: false,
            data: {
			    FromDate: $('#FromDate').val(),
                ToDate: $('#ToDate').val()
		    },
            url: "/FeedBackReport/GetDashboardData",
            success: function (result) {
                if (result.Message == "Success") {
                    //$('#divAllBranchTotalSales').html(result.ActualSales + " <small>KD</small>")
                    //$('#divAllBranchTotalWaste').html(result.TotalWaste + " <small>KD</small>")
                    //$('#divAllBranchTotalCancellation').html(result.TotalCancellation + " <small>KD</small>")
                    //$('#divAllBranchTotalDiscount').html(result.TotalDiscount + " <small>KD</small>")

                    BindCharts(result);
                }

            }
        });
    }

    function BindCharts(resultData)
    {
        BindFirstChart(resultData.FirstChart);
        BindSecondChart(resultData.SecondChart);
        BindThirdChart(resultData.ThirdChart);
        BindFourthDataGrid(resultData.FourthDataGrid);
        DataGridData =resultData.FourthDataGrid;
    }
    function getMax(arr, prop) {
        var max;
        for (var i=0 ; i<arr.length ; i++) {
            if (max == null || parseInt(arr[i][prop]) > parseInt(max[prop]))
                max = arr[i];
        }
        return max;
    }
    function getMin(arr, prop) {
        var max;
        for (var i=0 ; i<arr.length ; i++) {
            if (max == null || parseInt(arr[i][prop]) < parseInt(max[prop]))
                max = arr[i];
        }
        return max;
    }
    function BindFirstChart(JsonData)
    {
        debugger;
        var data = JSON.parse(JsonData);
        if (data.length == 0)
        {
            $('#FirstChart').html("");
            return false;
        }
        var maxval = getMax(data,"Total");
        var Minval = getMin(data,"Total");
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
		               dataFields: [{
                            name: 'Response',
		               		type: 'string'
		               	},
		               	{
                            name: 'Total',
		               		type: 'number'
		               	}
                        ,{
                            name: 'QuestionId',
		               		type: 'number'
		               	}
                        ,{
                            name: 'Questions',
		               		type: 'string'
		               	}
		               ],
		               //id: "QuestionId",
		               localdata: data,
		               //sortcolumn: 'ITEM_NAME',
	            };
                dataAdapter1 = new $.jqx.dataAdapter(TableT);

            // prepare jqxChart settings
            var settings = {
                title: "Rate Food Quality",
                description: "",
                enableAnimations: true,
                showLegend: false,
                padding: { left: 2, top: 2, right: 2, bottom: 2 },
                titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
                source: dataAdapter1,
                colorScheme: 'scheme05',
                
                xAxis: {
                    //dataField: 'Day',
                    dataField: 'Response',
                    //unitInterval: 1,
                    tickMarks: { visible: true, interval: 1 },
                    gridLinesInterval: { visible: true, interval: 1 },
                    valuesOnTicks: false,
                    padding: { bottom: 2 },
                    gridLinesColor: 'white',
                    textRotationAngle: 0
                },
                valueAxis: {
                    //flip: true,
                    //unitInterval: 250,
                    //minValue: Minval,
                    //maxValue: maxval,
                    axisSize: 'auto',
                    gridLinesColor: 'white',
                    visible :false,
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
                                    dataField: 'Total',
                                    symbolType: 'square',
                                    color: '#66bb6a',
                                    labels:
                                    {
                                        visible: true,
                                        backgroundColor: '#FEFEFE',
                                        backgroundOpacity: 0.2,
                                        borderColor: '#7FC4EF',
                                        borderOpacity: 0.7,
                                        padding: { left: 2, right: 2, top: 0, bottom: 0 },

                                    }
                                },
                            ],
                            click: myChildHandler1
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
    

    function BindSecondChart(JsonData)
    {

            var data = JSON.parse(JsonData);
            if (data.length == 0)
            {
                $('#SecondChart').html("");
                return false;
            }
            var maxval = getMax(data,"Total");
            var Minval = getMin(data,"Total");
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
                dataFields: [{
                    name: 'Response',
                    type: 'string'
                },
                 {
                     name: 'Total',
                     type: 'number'
                 },
                {
                    name: 'QuestionId',
		            type: 'number'
		        }
                ,{
                    name: 'Questions',
		            type: 'string'
		        }
                ,{
                    name: 'Questions',
		            type: 'string'
		        }
                ],
                //id: "QuestionId",
                localdata: data,
                //sortcolumn: 'ITEM_NAME',
            };
            dataAdapter2 = new $.jqx.dataAdapter(TableT);



         var settings = {
             title: "How did we serve you Today?",
             description: "",
             enableAnimations: true,
             showLegend: false,
             padding: { left: 2, top: 2, right: 2, bottom: 2 },
             titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
             source: dataAdapter2,
             colorScheme: 'scheme05',
             xAxis: {
                 //dataField: 'Day',
                 dataField: 'Response',
                 //unitInterval: 1,
                 tickMarks: { visible: true, interval: 1 },
                 gridLinesInterval: { visible: true, interval: 1 },
                 valuesOnTicks: false,
                 padding: { bottom: 2 },
                 gridLinesColor: 'white',
                 textRotationAngle: 0
             },
             valueAxis: {
                //flip: true,
                 //unitInterval: 250,
                 //minValue: Minval,
                 //maxValue: maxval,

                 axisSize: 'auto',
                 gridLinesColor: 'white',
                 visible :false,
                 //  title: { text: 'Time in minutes<br><br>' },
                 //labels: { horizontalAlignment: 'left' }
             },
             seriesGroups:
                 [
                     {
                         type: 'column',
                         orientation: 'vertial',
                         series:
                         [
                             {
                                 //dataField: 'Swimming',
                                 dataField: 'Total',
                                 symbolType: 'square',
                                 labels:
                                 {
                                     visible: true,
                                     backgroundColor: '#FEFEFE',
                                     backgroundOpacity: 0.2,
                                     borderColor: '#7FC4EF',
                                     borderOpacity: 0.7,
                                     padding: { left: 2, right: 2, top: 0, bottom: 0 }
                                 }
                             },
                         ],
                        click: myChildHandler2
                     }
                 ]
         };
            // prepare jqxChart settings
            // setup the chart
        $('#SecondChart').jqxChart(settings);

        //function addhandler() {
        //    $('#SecondChart .jqx-chart-legend-text').eq(0).parent().hide();
        //    $('#SecondChart .jqx-chart-legend-text').parent().click(function () {
        //        addhandler();
        //    });
        //}

        //$('#SecondChart .jqx-chart-legend-text').eq(0).parent().hide();
        //$('#SecondChart .jqx-chart-legend-text').parent().click(function () {
        //    addhandler();
        //});

    }
    function BindThirdChart(JsonData) {
        var data = JSON.parse(JsonData);
        if (data.length == 0) {
            $('#ThirdChart').html("");
            return false;
        }
        var maxval = getMax(data, "Total");
        var Minval = getMin(data, "Total");

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
            dataFields: [{
                name: 'Response',
                type: 'string'
            },
            {
                name: 'Total',
                type: 'number'
            },
            {
                name: 'QuestionId',
		        type: 'number'
		    }
            ,{
                name: 'Questions',
		        type: 'string'
		    }
            ],
            //id: "QuestionId",
            localdata: data,
            //sortcolumn: 'ITEM_NAME',
        };
        dataAdapter3 = new $.jqx.dataAdapter(TableT);



        // prepare jqxChart settings
        var settings = {
            title: "Is it your First Time in Masgouf?",
            description: "",
            enableAnimations: true,
            showLegend: true,
            padding: { left: 2, top: 2, right: 2, bottom: 2 },
            titlePadding: { left: 5, top: 5, right: 0, bottom: 2 },
            source: dataAdapter3,
            colorScheme: 'scheme05',
            legendLayout: {
                left: 5,
                top: 5,
                width: 300,
                height: 700,
                flow: 'vertical'
            },
            xAxis: {
                //dataField: 'Day',
                dataField: 'Response',
                //unitInterval: 1,
                tickMarks: { visible: true, interval: 1 },
                gridLinesInterval: { visible: true, interval: 1 },
                valuesOnTicks: false,
                padding: { bottom: 2 },
                gridLinesColor: 'white',
                textRotationAngle: 90,
            },
            valueAxis: {
                flip: true,
                //unitInterval: 250,
                //minValue: Minval,
                //maxValue: maxval,
                axisSize: 'auto',
                gridLinesColor: 'white',
                visible: false,
                //title: { text: 'Time in minutes<br><br>' },
                //labels: { horizontalAlignment: 'right' },
            },
            seriesGroups:
                [
                    {
                        type: 'pie',
                        showLabels: true,
                        orientation: 'horizontal',
                        series:
                            [
                                {
                                    //dataField: 'Swimming',
                                    dataField: 'Total',
                                    displayText: 'Response',
                                    symbolType: 'square',
                                    labelRadius: 100,
                                    initialAngle: 15,
                                    radius: 130,
                                    //color: '#26c6da',
                                    //labels:
                                    //{
                                    //    visible: true,
                                    //    //backgroundColor: '#FEFEFE',
                                    //    //backgroundOpacity: 0.2,
                                    //    //borderColor: '#7FC4EF',
                                    //    //borderOpacity: 0.7,
                                    //    padding: { left: 2, right: 2, top: 0, bottom: 0 }
                                    //}
                                },
                            ],
                            click: myChildHandler3
                    }
                ]
        };
        // setup the chart
        $('#ThirdChart').jqxChart(settings);
    }
    function BindFourthDataGrid(JsonData)
    {
        debugger;
        var MasterEntry = {
            datafields: [{
                name: 'id',
                type: 'number'
            },
            {
                name: 'Customer_name',
                type: 'string'
            },
            {
                name: 'Customer_mobile',
                type: 'string'
            },
            {
                name: 'Customer_email',
                type: 'string'
            },
            {
                name: 'Response',
                type: 'string'
            },
            {
                name: 'Datetime',
                type: 'string'
            },
            ],
            localdata: JsonData,
            datatype: "json"
        };
        var dataAdapter4 = new $.jqx.dataAdapter(MasterEntry);
        $("#FourthDataGrid").jqxGrid({
            source: dataAdapter4,
            theme: 'Orange',
            pageSize: 10,
            height: 400,
            pageable: true,
            sortable: true,
            showfilterrow: true,
            filterable: true,
            autorowheight: true,
            columnsresize: true,
            autoshowloadelement: false,
            selectionmode: 'singlerow',
            columns: [{
                dataField: 'id',
                text: 'id',
                hidden: true
            },
            {
                dataField: 'Customer_name',
                text: 'Customer Name',
                width: '20%'
            },
             {
                dataField: 'Customer_mobile',
                text: 'Customer Mobile',
                width: '10%'
            },
            {
                dataField: 'Customer_email',
                text: 'Customer Email',
                width: '20%'
            },
            {
                dataField: 'Response',
                text: 'Response',
                width: '30%'
            },
            {
                dataField: 'Datetime',
                text: 'Response Datetime',
                width: '20%'
            },
            ]
        });
        //FourthDataGrid
    }

function ClearFilter()
{
    debugger;
    BindFourthDataGrid(DataGridData);
    $('#BtnClearFilter').hide();
    $('#txtChartType').html("Text");
}
    
function ExportToExcel()
{
    $("#FourthDataGrid").jqxGrid("exportdata", 'xls', 'FeedBackReport');
	//$("#grdStock").jqxGrid("exportdata",{
	//	includeLabels : true,
	//	includeGroupHeader : true,
	//	includeFooter: true,
	//	fileName : "jqGridExport.xlsx",
	//	maxlength : 40 // maxlength for visible string data 
	//});
}

function myChildHandler1(e) {
        debugger;
        var record = dataAdapter1.records[e.elementIndex];
        BindFilterDataGrid(record.QuestionId,record.Response);
        $('#txtChartType').html(record.Questions);
    }
    function myChildHandler2(e) {
        debugger;
        var record = dataAdapter2.records[e.elementIndex];
        BindFilterDataGrid(record.QuestionId,record.Response);
        $('#txtChartType').html(record.Questions);
    }
    function myChildHandler3(e) {
        debugger;
        var record = dataAdapter3.records[e.elementIndex];
        BindFilterDataGrid(record.QuestionId,record.Response);
        $('#txtChartType').html(record.Questions);
    }
    function BindFilterDataGrid(QuestionId,Response)
    {
        debugger;
        $.ajax({
                type: "GET",
                cache: false,
                data: {
			        FromDate: $('#FromDate').val(),
                    ToDate: $('#ToDate').val(),
                    QuestionId: QuestionId,
                    Response: Response
		        },
                url: "/FeedBackReport/GetFeedbackDetailsData",
                success: function (result) {
                    debugger;
                    if (result.Message == "Success") {
                        debugger;
                        BindFourthDataGrid(result.GridData);
                    }
                    $('#BtnClearFilter').show();
                },
                 error: function(error_data){
                        debugger;
                        console.log("error")
                        console.log(error_data)
                    }
            });
    }