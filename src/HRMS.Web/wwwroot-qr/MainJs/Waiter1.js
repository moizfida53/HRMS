$(document).ready(function () {
    
   // BindCategory();
});

function btnScanQRCodeClick()
{

}

function backFromItemListClick()
{
    $('#btnbackFromItemList').hide();
    $('#CartView').hide();
    $('#cartFooter').hide();
    $('#MenuList').show();
}

function openQRCamera(node) {
    debugger;
  var reader = new FileReader();
  reader.onload = function() {
    node.value = "";
    qrcode.callback = function(res) {
        debugger;
      if(res instanceof Error) {
        alert("No QR code found. Please make sure the QR code is within the camera's frame and try again.");
      } else {
        //node.parentNode.previousElementSibling.value = res;
        alert(res);
        $('#btnbackFromItemList').show();
        $('#CartView').show();
        $('#cartFooter').show();
        $('#MenuList').hide();
      }
    };
    qrcode.decode(reader.result);
  };
  reader.readAsDataURL(node.files[0]);
}