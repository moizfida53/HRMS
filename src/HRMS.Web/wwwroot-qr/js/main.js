// CSS Which needs to add
var css = [
    "../cssNew/bootstrap.min.css",
    "../cssNew/jquery.gridstrap.min.css",
    "../cssNew/BsMultiSelect.min.css",
    "../cssNew/bootstrap-select.min.css",
    "../cssNew/datepicker.css",
    "../cssNew/admin.css",
    //"../cssNew/style.css",
    "https://fonts.googleapis.com/css?family=Poppins:300,300i,400,400i,500,600,700,900&display=swap"
];

// JS Which needs to add
//var js = [
//"../vendor/jquery/jquery-ui.min.js",
//"../js/popper.min.js",
//"../js/bootstrap.bundle.min.js",
//"../js/jquery.gridstrap.min.js",
//"../js/BsMultiSelect.min.js",
//"../js/bootstrap-select.min.js",
//"../js/custom.js"
//];


// Add All css and js to head in HTML page
var headID = document.getElementsByTagName('head')[0];
for (i = 0; i < css.length; i++) {
    var link = document.createElement('link');
    link.href = css[i];
    link.type = "text/css";
    link.rel = "stylesheet";
    headID.appendChild(link);
};

//var script = document.createElement('script');
//script.src = "js/jquery.js";
//script.type = "text/javascript";
//script.onload = function () {
//    for (j = 0; j < js.length; j++) {
//        var script = document.createElement('script');
//        script.src = js[j];
//        script.type = "text/javascript";
//        headID.appendChild(script);
//    };
//}
//headID.appendChild(script);