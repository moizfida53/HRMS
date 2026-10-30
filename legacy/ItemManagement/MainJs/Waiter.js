//var CartDetails = [];
$(document).ready(function () {
    BindCategory();
    //$('#MenuList').hide();
});

function btnScanQRCodeClick()
{
    $('#CartView').hide();
    $('#cartFooter').hide();
    $('#QRScanView').show();
    $('#btnMenu').hide();
    $('#MenuList').hide();
    $('#btnMenuDesktop').hide();
    //$('#btncart').hide();
    $('#result').html("- scanning -");
    //setwebcam();
    //load();
    $('#scrolldiv').scrollTop(0);
    $('#kt_wizard_v4').scrollTop(0);

    $('#divCartView').hide();
    debugger;
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } }).then(function (stream) {
        video.srcObject = stream;
        video.setAttribute("playsinline", true); // required to tell iOS safari we don't want fullscreen
        video.play();
        requestAnimationFrame(tick);
    });
}

//function ShowMenuclick()
//{
//    /*$('#ItemDetails').hide();
//    $('#btnContinueShopping').hide();
//    $('#cartFooter').hide();
//    $('#CartView').hide();
//    $('#MenuList').show();*/
//    $('#ItemDetails').hide();
//    $('#btnMenu').hide();
//    $('#cartFooter').hide();
//    $('#CartView').hide();
//    $('#MenuList').show();
//    $('#btncart').show();
//}
//function displaycartview()
//{
//    BindCart(CartDetails, CartComments, CartExtraItems, false, false);
    
//    $('#CartView').show();
//    $('#btnMenu').show();
//    $('#cartFooter').show();
//    $('#MenuList').hide();
//    $('#btnbackFromQccode').hide();
//    $('#divQRCodeMain').hide();
   
//}

//function displaycartview() {
//    //showLoading();
//    var cartdetails = CartDetails;
//    BindCart(cartdetails, CartComments, CartExtraItems, false, false);
//    $('#CartView').show();
//    $('#btnMenu').show();
//    $('#cartFooter').show();
//    $('#MenuList').hide();
//    $('#btnbackFromQccode').hide();
//    $('#divQRCodeMain').hide();
//    $('#desktopview').hide();
//    $('#TrackingOrder').hide();
//    //hideLoading();
//}


//common function but use only custermer side not waiter side 
function createCookie()
{

}

function accessCookie(cookieName)
{
    
}