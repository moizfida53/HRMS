function grdStockExporttoExcel() {
    debugger;
    $("#output").jqxGrid("exportdata", 'xls', 'Stock_Data');
}
function Search() {
    var date1 = $("#StartDate").val();
    var date2 = $("#EndDate").val();
   

    if ((new Date(date1) <= new Date(date2))) { }
    else {
        alert('Start Date Cannot be more than End Date');
        return;
    }

    //var formattedDate1 = $.jqx.dataFormat.formatdate(date1, 'yyyy-MM-dd HH:mm:ss');
    //var formattedDate2 = $.jqx.dataFormat.formatdate(date2, 'yyyy-MM-dd 23:59:59');

    var File = {
        "StartDate": date1,
        "EndDate": date2
    };

    $.ajax({
        type: "GET",
        url: "../../Pivot/GetPivot",
        contentType: 'application/json',
        data: File,
        success: function (result) {
            var Pivot = result.dtPivot;
            FillPivot(Pivot);

        }
    })

}
function FillPivot(Pivot) {


    var nrecoPivotExt = new NRecoPivotTableExtensions({
        wrapWith: '<div class="pvtTableRendererHolder">>/div>',
        fixedHeaders: true
    });
    var nrecoPivotExt = new NRecoPivotTableExtensions({
        fixedHeaders: true
    });

    var stdRendererNames = ["Table", "Table Barchart",
        "Heatmap", "Row Heatmap", "Col Heatmap", "Bar Chart"];
    var wrappedRenderers = $.extend({}, $.pivotUtilities.renderers, $.pivotUtilities.c3_renderers);
    $.each(stdRendererNames, function () {
        var rName = this;
        wrappedRenderers[rName] =
            nrecoPivotExt.wrapTableRenderer(wrappedRenderers[rName]);
    });

    $('#output').pivotUI(Pivot, {
        renderers: wrappedRenderers,
        rendererOptions: {},
        vals: ["TotalPrice"],
        rows: ["BranchName"],
        exportCSV: true,
        aggregatorName: "Sum",
        //onRefresh: function (pivotUIOptions) {
        //    nrecoPivotExt.initFixedHeaders(
        //        $('#output table.pvtTable'));
        //}
    });

}


