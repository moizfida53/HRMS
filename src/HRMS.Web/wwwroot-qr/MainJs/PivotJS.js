
var uri = 'data:application/vnd.ms-excel;base64,'
    , template = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40"><head><!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet><x:Name>{worksheet}</x:Name><x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]--><meta http-equiv="content-type" content="text/plain; charset=UTF-8"/></head><body><table>{table}</table></body></html>'
    , base64 = function (s) { return window.btoa(unescape(encodeURIComponent(s))) }
    , format = function (s, c) { return s.replace(/{(\w+)}/g, function (m, p) { return c[p]; }) };


function saveAs(uri, filename) {
    var link = document.createElement('a');
    if (typeof link.download === 'string') {
        link.href = uri;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    } else {
        window.open(uri);
    }
}

function exportPivotToExcel(pivotBlockId, name) {
    var tbl = $('#' + pivotBlockId).find('.pvtTable');
    var ctx = { worksheet: name || 'Worksheet', table: tbl.html() };
    var uriFile = uri + base64(format(template, ctx));
    saveAs(uriFile, name + '.xls');
}

function Search() {

   
    $.ajax({
        type: "GET",
        url: "../../items/GetFeedbackReport",
        contentType: 'application/json',
        //data: File,
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
        "Heatmap", "Row Heatmap", "Col Heatmap",  "Bar Chart"];
    var wrappedRenderers = $.extend({}, $.pivotUtilities.renderers, $.pivotUtilities.c3_renderers);
    $.each(stdRendererNames, function () {
        var rName = this;
        wrappedRenderers[rName] =
            nrecoPivotExt.wrapTableRenderer(wrappedRenderers[rName]);
    });

    $('#output').pivotUI(Pivot, {
        renderers: wrappedRenderers,
        rendererOptions: {}, 
        rows: ["Question"],
        cols: ["Response","ResponseType"],
        exportCSV: true,   
    });
}
