var curr = "KD. ";

///////////////////Start code for model view////////////////////////////
var modal = document.getElementById("myModal");

// Get the button that opens the modal
var btn = document.getElementById("myBtn");

// Get the <span> element that closes the modal
var span = document.getElementsByClassName("close")[0];
var isfromWaiterTemp = false;
// When the user clicks the button, open the modal 
/*btn.onclick = function() {
  modal.style.display = "block";
}*/

var validationPopup = "Sorry, looks like there are some errors detected, please try again.";
var ValconfirmButtonText = "Ok, got it!";
var validationlblFirstName = 'First name is required';
var validationlblLastName = 'Last Name is required';
var validationlblPhone = 'Phone is required';
var validationlblPhoneMin = 'Minimum 8 numbers';
var validationlblPhoneReq = 'Phone is not valid';
var validationlblEmail = 'Email is required';
var validationlblEmailNotValid = 'The value is not a valid email address';
var validationlblOrderType = 'OrderType is required';
var validationlblArea = 'Area is required';
var validationlblBlock = 'Block is required';
var validationlblStreet = 'Street is required';
var validationlblBuilding = 'Building is required';
var validationlblFlat = 'Flat is required';
var validationlblFloor = 'Floor is required';
var validationlblPaymentType = 'PaymentType is required';

// When the user clicks on <span> (x), close the modal
span.onclick = function () {
    modal.style.display = "none";
}

// When the user clicks anywhere outside of the modal, close it
window.onclick = function (event) {
    if (event.target == modal) {
        modal.style.display = "none";
    }
}


///////////////////End code for model view////////////////////////////

function BindCartCount(objCartDetails) {
    debugger;
    var cartcount = 0;
    $.each(objCartDetails, function (i, obj) {
        cartcount = cartcount + obj.Q;
    });

    $('#cartCount').text(cartcount);
    $('#cartCountDesktop').text(cartcount);
    UpdateCartCountSpan();
}
function selectLanguage(btn) {
    var val = "EN"
    var Displayval = "ع"
    $('#menu_LanguageLabel').html("ARABIC");
    if ($('#selectedLang').val() == "EN") {
        val = "AR"
        Displayval = "EN"
        $('#menu_LanguageLabel').html("ENGLISH");
    }
    //$('.dropdown-content').hide();
    $('#selectedLang').val(val);
    $('#Btnlang').html(Displayval);
    $('#BtnlangDesktop').html(Displayval);
    $('#Btnlang').val(Displayval);
    $('#BtnlangDesktop').val(Displayval);
    BindLangLabels(val);
    BindCategory(selectedCategoryId);
    var IsOnlyConfirmCartBind = false;
    BindCart(CartDetails, CartComments, CartExtraItems,isfromWaiterTemp, IsOnlyConfirmCartBind);
    BindAreaDropdown();
}
function BindLangLabels(val) {
    var objCartDetails = {
        selectedLang: val
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objCartDetails),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetLangLabels",
        success: function (result) {
            if (result.Message == "Success") {
                var objLabels = JSON.parse(result.dtLabels);
                $('#btnMenu').html(objLabels[0].LabelTest);
                //$('#btnMenuDesktop').html(objLabels[0].LabelTest);

                $('#btnCheckOut').html(objLabels[1].LabelTest);
                $('#btnclearCart').html(objLabels[2].LabelTest);
                //$('#btnclearCartConfirm').html(objLabels[2].LabelTest);
                $('#divUserInformation').html(objLabels[3].LabelTest);
                $('#divSetupNameMobileEmail').html(objLabels[4].LabelTest);
                $('#divDeliveryServiceType').html(objLabels[5].LabelTest);
                $('#divSelectDeliveryPickup').html(objLabels[6].LabelTest);
                $('#divYourAddress').html(objLabels[7].LabelTest);
                $('#divSetupYourAddress').html(objLabels[8].LabelTest);
                $('#divMakePayment').html(objLabels[9].LabelTest);
                $('#divSelectPaymentOptions').html(objLabels[10].LabelTest);
                $('#divCompleted').html(objLabels[11].LabelTest);
                $('#divReviewandSubmit').html(objLabels[12].LabelTest);
                $('#divEnteryourAccountDetails').html(objLabels[13].LabelTest);

                $('#lblFirstName').html(objLabels[14].LabelTest);
                $('#fname').attr("placeholder", objLabels[14].LabelTest);
                $('#spnPleaseenteryourfirstname').html(objLabels[15].LabelTest);

                $('#lblLastName').html(objLabels[16].LabelTest);
                $('#lname').attr("placeholder", objLabels[16].LabelTest);
                $('#spnPleaseenteryourlastname').html(objLabels[17].LabelTest);

                $('#lblPhone').html(objLabels[18].LabelTest);
                $('#phone').attr("placeholder", objLabels[18].LabelTest);
                $('#spnPleaseenteryourphonenumber').html(objLabels[19].LabelTest);

                $('#lblEmail').html(objLabels[20].LabelTest);
                $('#email').attr("placeholder", objLabels[20].LabelTest);
                $('#spnPleaseenteryouremailaddress').html(objLabels[21].LabelTest);

                $('#lblArea1').html(objLabels[39].LabelTest);
                $('#divSelectDeleveryType').html(objLabels[22].LabelTest);
                $('#lblOrderType').html(objLabels[23].LabelTest);
                $('#spnPleaseselectOrderType').html(objLabels[24].LabelTest);
                $('#divSetupYourAddress').html(objLabels[25].LabelTest);
                $('#spnPleaseselectyourArea').html(objLabels[26].LabelTest);

                $('#lblBlock').html(objLabels[27].LabelTest);
                $('#Block').attr("placeholder", objLabels[28].LabelTest);
                $('#spnPleaseenteryourBlock').html(objLabels[28].LabelTest);

                $('#lblStreet').html(objLabels[29].LabelTest);
                $('#Street').attr("placeholder", objLabels[29].LabelTest);
                $('#spnPleaseenteryourStreet').html(objLabels[30].LabelTest);

                $('#lblBuilding').html(objLabels[31].LabelTest);
                $('#Building').attr("placeholder", objLabels[31].LabelTest);
                $('#spnPleaseenteryourBuilding').html(objLabels[32].LabelTest);

                $('#lblFloor').html(objLabels[33].LabelTest);
                $('#Floor').attr("placeholder", objLabels[33].LabelTest);
                $('#spnPleaseenteryourFloor').html(objLabels[34].LabelTest);

                $('#lblFlat').html(objLabels[35].LabelTest);
                $('#Flat').attr("placeholder", objLabels[35].LabelTest);
                $('#spnPleaseenteryourFlat').html(objLabels[36].LabelTest);

                $('#lblLandmark').html(objLabels[37].LabelTest);
                $('#Landmark').attr("placeholder", objLabels[37].LabelTest);
                $('#spnPleaseenteryourLandmark').html(objLabels[38].LabelTest);

                $('#lblArea').html(objLabels[39].LabelTest);
                $('#Area').attr("placeholder", objLabels[39].LabelTest);
                $('#spnPleaseselectyourArea').html(objLabels[40].LabelTest);

                $('#divEnteryourPaymentDetails').html(objLabels[41].LabelTest);

                $('#h1PaymentMethod').html(objLabels[42].LabelTest);
                $('#pChooseyourpreferredpaymentmethod').html(objLabels[43].LabelTest);
                $('#pKNET').html(objLabels[44].LabelTest);
                $('#pCreditCard').html(objLabels[45].LabelTest);
                $('#pCashondelivery').html(objLabels[46].LabelTest);
                $('#h4ReviewyourDetailsandSubmit').html(objLabels[47].LabelTest);
                $('#h6UserInformation').html(objLabels[48].LabelTest);
                $('#h6DeliveryServiceType').html(objLabels[49].LabelTest);
                $('#h6AddressInformation').html(objLabels[50].LabelTest);
                $('#h6PaymentDetails').html(objLabels[51].LabelTest);
                $('#btnPrevious').html(objLabels[52].LabelTest);
                $('#btnSubmit').html(objLabels[53].LabelTest);
                $('#btnNext').html(objLabels[54].LabelTest);

                $('#spnTotal').html(objLabels[55].LabelTest);
                $('#spnTotalConfirm').html(objLabels[55].LabelTest);

                $('#OrderType_Delivery').html(objLabels[56].LabelTest);
                $('#OrderType_Pickup').html(objLabels[57].LabelTest);
                $('#optionSelect').html(objLabels[58].LabelTest);
                $('#optionSelect1').html(objLabels[58].LabelTest);

                jQuery.each($('.txtComment'), function (i, val) {
                    $(this).attr("placeholder", objLabels[59].LabelTest);
                });
                $('#snackbar').html(objLabels[60].LabelTest);

                //$('#validationlblFistName').val(objLabels[56].LabelTest);
                validationlblFistName = objLabels[61].LabelTest;
                validationPopup = objLabels[62].LabelTest;
                ValconfirmButtonText = objLabels[63].LabelTest;
                validationlblLastName = objLabels[64].LabelTest;
                validationlblPhone = objLabels[65].LabelTest;
                validationlblPhoneMin = objLabels[66].LabelTest;
                validationlblPhoneReq = objLabels[67].LabelTest;
                validationlblEmail = objLabels[68].LabelTest;
                validationlblEmailNotValid = objLabels[69].LabelTest;
                validationlblOrderType = objLabels[70].LabelTest;
                validationlblArea = objLabels[71].LabelTest;
                validationlblBlock = objLabels[72].LabelTest;
                validationlblStreet = objLabels[73].LabelTest;
                validationlblBuilding = objLabels[74].LabelTest;

                validationlblFlat = objLabels[75].LabelTest;
                validationlblFloor = objLabels[76].LabelTest;
                validationlblPaymentType = objLabels[77].LabelTest;

                $('#txtTrackorderNumber').attr("placeholder", objLabels[78].LabelTest);
                $('#msgTrackOrderBlank').html(objLabels[78].LabelTest);
                $('#msgTrackOrderWrong').html(objLabels[79].LabelTest);
                $('#msgContactManager').html(objLabels[80].LabelTest);
                $('#spnDeliveryChargesConfirm').html(objLabels[81].LabelTest);

                //update summary data with updated language
                BindSummaryTabData();
                if (typeof KTWizard4 !== 'undefined') {
                    KTWizard4.init();
                }


                //$('input[name="fname"]').rules('add', {
                //    messages: {
                //        required: "new message for field 1"
                //    }
                //});
            }
        }
    });
}
function BindCart(objCartDetails, CartComments, CartExtraItems, isfromWaiter, IsOnlyConfirmCartBind) {
    debugger;
    var ObjDataCartDetails = [];

    $.each(objCartDetails, function (i, obj) {
        var item = {}
        item["UID"] = obj.UID;
        item["ItemId"] = obj.I;
        item["HID"] = obj.O;
        item["qty"] = obj.Q;
        item["Comments"] = obj.C;
        item["ChoiceId"] = obj.CH;
        ObjDataCartDetails.push(item);
    });
    debugger;
    isfromWaiterTemp = isfromWaiter;
    $.ajax({
        type: "Post",
        data: JSON.stringify(ObjDataCartDetails),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetCartViewItems",
        success: function (result) {
            if (result.Message == "Success") {
                var Items = result.dtItems;
                //if click on confirm view tab click then not need to bind cartitems
                if (!IsOnlyConfirmCartBind) {
                    BindCartItems(Items, isfromWaiterTemp);
                }
                BindConfirmCartItems(Items, isfromWaiterTemp);
                /*var Items = result.dtItems;
                BindSelectedCategoryItems(Items);*/
            }
        }
    });
}




function BindCartItems(Items, isfromWaiter) {
    debugger;
    var Mainstr = "";
    var selectedCat_num = 0;
    //var selectedCate="";
    var categoryidList = [];
    $('#cartitemsMainDiv').html("");
    var Subtotal = 0.000;


    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var CategoryName = "";
        var INGREDIENT = "";
        curr = item.Currency;
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            CategoryName = item.CAT_NAME;
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            CategoryName = item.CAT_NAME_ARABIC;
        }
        $.each(categoryidList, function (i, cat) {
            if (cat != item.CAT_NUM && categoryidList.indexOf(item.CAT_NUM) == -1) {
                var strcategory = "<div id='cartCate_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                    "" + CategoryName + "" +
                    "</div>" +
                    "<div id='cartCateItems_" + item.CAT_NUM + "'>" +
                    "</div>";
                categoryidList.push(item.CAT_NUM)
                $('#cartitemsMainDiv').append(strcategory);
            }
        });

        if (categoryidList.length == 0) {
            var strcategory = "<div id='cartCate_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                "" + CategoryName + "" +
                "</div>" +
                "<div id='cartCateItems_" + item.CAT_NUM + "'>" +
                "</div>";
            categoryidList.push(item.CAT_NUM);
            $('#cartitemsMainDiv').append(strcategory);
        }



        var str = "";
        str = "<div id='CartItem_" + item.id + "' data-val=" + item.CAT_NUM + " class='ng-tns-c0-81 ng-star-inserted'>" +
            "<input id='hdnItemINGREDIENT_" + item.id + "' type='hidden' value='" + INGREDIENT + "'>" +
            "<input id='hdnITEM_NAME_" + item.id + "' type='hidden' value='" + ItemName + "'>" +
            "<input id='hdnItem_IMAGENAME_" + item.id + "' type='hidden' value='" + item.IMAGENAME + "'>" +
            "<input id='hdnItem_PRICE_" + item.id + "' type='hidden' value='" + item.PRICE + "'>" +
            "<input id='hdnItem_TotalPRICE_" + item.id + "' type='hidden' value='" + item.TotalPrice + "'>" +
            "<button id='btnItem_" + item.id + "' class='menu-item-anchor' prevent-double-click=''>" +
            "<div class='menu-Cat-item item item-block' style='background-color: rgb(255, 255, 255); opacity: 1;'>" +
            "<div onclick='OnItemClick(" + item.id + ");' class='menu-item-thumbnail ng-tns-c0-81 ng-star-inserted' item-start='' style='align-self: flex-start;'>" +
            "<img class='ng-tns-c0-81' src='../../ThumbnailImages/" + item.IMAGENAME + "?fit=crop&amp;w=90&amp;h=90&amp;q=100&amp;fm=jpg' width='100' height='100' style='object-fit: cover;'>" +
            "</div>" +
            "<div class='item-inner'>" +
            "<div class='input-wrapper'>" +
            "<div class='label label-ios ng-star-inserted' style=''>" +
            "<div class='ng-tns-c0-81 Itemrightcontent'>" +
            "<div style='width:100% !important;'>" +
            "<h1 onclick='OnItemClick(" + item.id + ");' class='menu-item-header clsitemNameHeaderCart'>" + ItemName + "</h1>" +

            "</div>" +
            "<div style='clear:both !important;'></div>" +
            "<div  class='ng-tns-c0-81'>" +
            "<div class='menu-item-footer ng-star-inserted'>" +
            /*"<span class='item-currency ng-star-inserted' style='color: rgb(230, 3, 75);'>"+
                ""+item.Currency+". "+item.PRICE+""+
                "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>"+
            "</span>"+
            "<span id='ItemTotalamt_"+item.id+"' class='item-currency ng-star-inserted' style='color: rgb(230, 3, 75);float:right; height:30px;'>"+
                ""+item.Currency+". "+item.TotalPrice+""+
                "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>"+
            "</span>"+*/
            "<div onclick='OnItemClick(" + item.id + ");' style='height:30px;float:left;'><span id='ItemTotalamt_" + item.id + "' class='item-currency ng-star-inserted' style='color: var(--primary);'>" +
            "" + item.Currency + ". " + item.TotalPrice + "" +
            "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>" +
            "</span></div>" +

            "<div style='line-height: 30px;float:right !important; margin-right:5px;'>" +
            "<div style='width:32px;float:left;' onclick='Minusecardclick(" + item.id + ");' class='addbutton'>-</div>" +
            "<div id='divItemwiseCount_" + item.id + "' class='clsselectedQty' style=''>" + item.qty + "</div>" +
            "<div style='width:32px;float:left;' onclick='addItemclick(" + item.id + "," + item.HID + ");' class='addbutton'>+</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "<div>" +
            "<input type='text' class='txtComment' id='comments_" + item.id + "' value='" + item.Comments + "' placeholder='Comments' multiple />" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div><div class='button-effect'></div>" +
            "</div>" +
            "</button>" +
            "</div>";
        $('#cartCateItems_' + item.CAT_NUM).append(str);
        Subtotal = Subtotal + Number.parseFloat(item.TotalPrice);
        //Mainstr=Mainstr + str;
    });
    $('#divSubtotal').html(curr + ". " + Subtotal.toFixed(3));
    $('#hdnSubtotal').val(Subtotal.toFixed(3));
}

function BindConfirmCartItems(Items, isfromWaiter) {
    var Mainstr = "";
    var selectedCat_num = 0;
    //var selectedCate="";
    var categoryidList = [];
    $('#cartitemsMainDivConfirm').html("");
    var Subtotal = 0.000;


    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var CategoryName = "";
        var INGREDIENT = "";
        curr = item.Currency;
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
            CategoryName = item.CAT_NAME;
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
            CategoryName = item.CAT_NAME_ARABIC;
        }
        $.each(categoryidList, function (i, cat) {
            if (cat != item.CAT_NUM && categoryidList.indexOf(item.CAT_NUM) == -1) {
                var strcategory = "<div id='cartCate_Confirm_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                    "" + CategoryName + "" +
                    "</div>" +
                    "<div id='cartCateItems_Confirm_" + item.CAT_NUM + "'>" +
                    "</div>";
                categoryidList.push(item.CAT_NUM)
                $('#cartitemsMainDivConfirm').append(strcategory);
            }
        });

        if (categoryidList.length == 0) {
            var strcategory = "<div id='cartCate_Confirm_" + item.CAT_NUM + "' class='cart_catHeader'>" +
                "" + CategoryName + "" +
                "</div>" +
                "<div id='cartCateItems_Confirm_" + item.CAT_NUM + "'>" +
                "</div>";
            categoryidList.push(item.CAT_NUM);
            $('#cartitemsMainDivConfirm').append(strcategory);
        }



        var str = "";
        str = "<div id='Item_Confirm_" + item.id + "' data-val=" + item.CAT_NUM + " class='ng-tns-c0-81 ng-star-inserted'>" +
            "<input id='hdnItemINGREDIENT_Confirm_" + item.id + "' type='hidden' value='" + INGREDIENT + "'>" +
            "<input id='hdnITEM_NAME_Confirm_" + item.id + "' type='hidden' value='" + ItemName + "'>" +
            "<input id='hdnItem_IMAGENAME_Confirm_" + item.id + "' type='hidden' value='" + item.IMAGENAME + "'>" +
            "<input id='hdnItem_PRICE_Confirm_" + item.id + "' type='hidden' value='" + item.PRICE + "'>" +
            "<input id='hdnItem_TotalPRICE_Confirm_" + item.id + "' type='hidden' value='" + item.TotalPrice + "'>" +
            "<button id='btnItem_Confirm_" + item.id + "' class='menu-item-anchor' prevent-double-click=''>" +
            "<div class='menu-Cat-item item item-block' style='background-color: rgb(255, 255, 255); opacity: 1;'>" +
            "<div onclick='OnItemClick(" + item.id + ");' class='menu-item-thumbnail ng-tns-c0-81 ng-star-inserted' item-start='' style='align-self: flex-start;'>" +
            "<img class='ng-tns-c0-81' src='../../ThumbnailImages/" + item.IMAGENAME + "?fit=crop&amp;w=90&amp;h=90&amp;q=100&amp;fm=jpg' width='100' height='100' style='object-fit: cover;'>" +
            "</div>" +
            "<div class='item-inner'>" +
            "<div class='input-wrapper'>" +
            "<div class='label label-ios ng-star-inserted' style=''>" +
            "<div class='ng-tns-c0-81 Itemrightcontent'>" +
            "<div style='width:100% !important;'>" +
            "<h1 onclick='OnItemClick(" + item.id + ");' class='menu-item-header clsitemNameHeaderCart'>" + ItemName + "</h1>" +

            "</div>" +
            "<div style='clear:both !important;'></div>" +
            "<div  class='ng-tns-c0-81'>" +
            "<div class='menu-item-footer ng-star-inserted'>" +
            /*"<span class='item-currency ng-star-inserted' style='color: rgb(230, 3, 75);'>"+
                ""+item.Currency+". "+item.PRICE+""+
                "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>"+
            "</span>"+
            "<span id='ItemTotalamt_"+item.id+"' class='item-currency ng-star-inserted' style='color: rgb(230, 3, 75);float:right; height:30px;'>"+
                ""+item.Currency+". "+item.TotalPrice+""+
                "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>"+
            "</span>"+*/
            "<div onclick='OnItemClick(" + item.id + ");' style='height:30px;float:left;padding-top:5px;'><span id='ItemTotalamt_Confirm_" + item.id + "' class='item-currency ng-star-inserted' style='color: var(--primary);'>" +
            "" + item.Currency + ". " + item.TotalPrice + "" +
            "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'></span>" +
            "</span></div>" +

            "<div style='line-height: 30px;float:right !important; margin-right:5px;'>" +
            "<div style='width:32px;float:left;' onclick='Minusecardclick(" + item.id + ");' class='addbutton'>-</div>" +
            "<div id='divItemwiseCount_Confirm_" + item.id + "' class='clsselectedQty' style=''>" + item.qty + "</div>" +
            "<div style='width:32px;float:left;' onclick='addItemclick(" + item.id + "," + item.HID + ");' class='addbutton'>+</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "<div>" +
            "<input type='text' class='txtComment' id='comments_Confirm_" + item.id + "' value='" + item.Comments + "' placeholder='Comments' multiple />" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div><div class='button-effect'></div>" +
            "</div>" +
            "</button>" +
            "</div>";
        $('#cartCateItems_Confirm_' + item.CAT_NUM).append(str);
        Subtotal = Subtotal + Number.parseFloat(item.TotalPrice);
        //Mainstr=Mainstr + str;
    });
    $('#hdnSubtotal').val(Subtotal.toFixed(3));
    $('#divSubTotalConfirm').html(curr + ". " + Subtotal.toFixed(3));
    var deliveryCharges = Number.parseFloat($('#hdnAreaDeliveryCharges').val());
    Subtotal = Subtotal + deliveryCharges;
    $('#divtotalConfirm').html(curr + ". " + Subtotal.toFixed(3));
    $('#cartFooterConfirm').show();
    $('#divDeliveryChargesConfirm').html(curr + ". " + deliveryCharges.toFixed(3));
}

function addItemclick(itemid, HID) {
    var tempqty = 1;
    var totalcnt = 0;
    var IsExists = 0;
    var tempCartDetails = CartDetails;

    $.each(tempCartDetails, function (i, obj) {
        if (obj.I == itemid) {
            obj.Q = obj.Q + 1;
            $('#divItemwiseCount_' + itemid).html(obj.Q);
            if ($('#divItemwiseCount_Confirm_' + itemid).length > 0) {
                $('#divItemwiseCount_Confirm_' + itemid).html(obj.Q);
            }
            IsExists = 1;
        }
        totalcnt = totalcnt + obj.Q;
    });
    if (IsExists == 0) {
        var item = {}
        //item["ItemId"] = itemid;
        //item["HID"] = HID;
        //item["qty"] = tempqty;
        //item["Comments"] = "";
        //item["ChoiceId"] = obj.CH;

        item["I"] = itemid;
        item["O"] = HID;
        item["Q"] = tempqty;
        item["C"] = "";
        item["CH"] = 0;
        tempCartDetails.push(item);
        totalcnt = totalcnt + 1;
    }

    $('#cartCount').text(totalcnt);
    $('#cartCountDesktop').text(totalcnt);

    //update ItemTotal
    var selectedItemPrice = Number.parseFloat($('#hdnItem_PRICE_' + itemid).val());
    if (isNaN(selectedItemPrice)) {
        var selectedItemPrice = 0;
    }
    var curtotal = Number.parseFloat($('#hdnItem_TotalPRICE_' + itemid).val());
    $('#hdnItem_TotalPRICE_' + itemid).val((curtotal + selectedItemPrice).toFixed(3));
    $('#ItemTotalamt_' + itemid).text(curr + ". " + (curtotal + selectedItemPrice).toFixed(3));
    if ($('#ItemTotalamt_Confirm_' + itemid).length > 0) {
        $('#ItemTotalamt_Confirm_' + itemid).text(curr + ". " + (curtotal + selectedItemPrice).toFixed(3));
    }
    //update subtotal 
    var curSubtotal = Number.parseFloat($('#hdnSubtotal').val());
    $('#hdnSubtotal').val((curSubtotal + selectedItemPrice).toFixed(3));
    $('#divSubtotal').text(curr + ". " + (curSubtotal + selectedItemPrice).toFixed(3));
    if ($('#divSubTotalConfirm').length > 0) {
        $('#divSubTotalConfirm').text(curr + ". " + (curSubtotal + selectedItemPrice).toFixed(3));
    }

    //code for confirm view update Final total amount with deliverycharges
    //code for confirm view update Final total amount with deliverycharges
    var TotalAmt = Number.parseFloat(curSubtotal + selectedItemPrice);
    UpdateConfirmViewFinalAmounts(curr, TotalAmt);


    var val = JSON.stringify(tempCartDetails);
    createCookie("OrderCookie", val, 365);
    ShowNotification("Item Added in Cart..");
    CartDetails = tempCartDetails;
    UpdateCartCountSpan();
    console.log(CartDetails);
}
function UpdateCartCountSpan() {
    if ($('#cartCount').html() == "0") {
        $('#cartCount').hide();
        $('#cartCountDesktop').hide();
    }
    else {
        $('#cartCount').show();
        $('#cartCountDesktop').show();
    }
}

function ShowNotification(message) {
    // Get the snackbar DIV
    $('#snackbar').html(message);
    var x = document.getElementById("snackbar");
    // Add the "show" class to DIV
    x.className = "show";
    // After 3 seconds, remove the show class from DIV
    setTimeout(function () { x.className = x.className.replace("show", ""); }, 1000);
}

function Minusecardclick(itemid) {
    var qty = parseInt($('#divItemwiseCount_' + itemid).html());
    if (qty == 1) {
        $.confirm({
            title: 'Confirm',
            content: 'Are you sure you want to remove?',
            icon: 'fa fa-question',
            closeAnimation: 'scale',
            opacity: 0.2,
            theme: 'bootstrap',
            closeIcon: true,
            animation: 'scale',
            type: 'orange',
            buttons: {
                'confirm': {
                    text: 'Yes',
                    btnClass: 'btn-orange',
                    action: function () {
                        UpdateSubTotal(itemid);
                        minuseItem(itemid, CartDetails, true);
                    },
                    Cancel: function () {
                        //retval=false;
                    },
                }
            }
        });
    }
    else {
        UpdateSubTotal(itemid);
        minuseItem(itemid, CartDetails, false);
    }
}
function minuseItem(itemid, objCartDetails, isitlastitem) {
    var totalcnt = 0;
    var catnumb = $('#CartItem_' + itemid).attr("data-val");
    var tempCartDetails = objCartDetails;
    $.each(tempCartDetails, function (i, obj) {
        if (obj.I == itemid) {
            obj.Q = obj.Q - 1;
            $('#divItemwiseCount_' + itemid).html(obj.Q);
            if ($('#divItemwiseCount_Confirm_' + itemid).length > 0) {
                $('#divItemwiseCount_Confirm_' + itemid).html(obj.Q);
            }
            if (obj.Q == 0) {
                $('#CartItem_' + itemid).remove();
                jQuery.each($('#CartItem_' + itemid), function (i, val) {
                    $(this).remove();
                });

                if ($('#Item_Confirm_' + itemid).length > 0) {
                    $('#Item_Confirm_' + itemid).remove();
                    jQuery.each($('#Item_Confirm_' + itemid), function (i, val) {
                        $(this).remove();
                    });
                }
            }
            if (isitlastitem) {
                tempCartDetails = jQuery.grep(tempCartDetails, function (value) {
                    return value != obj;
                });
            }
        }
        totalcnt = totalcnt + obj.Q;
    });
    $('#cartCount').text(totalcnt);
    $('#cartCountDesktop').text(totalcnt);
    var val = JSON.stringify(tempCartDetails);
    createCookie("OrderCookie", val, 365);
    ShowNotification("Item Removed from Cart..");

    checkcategoryItemExist(catnumb);
    CartDetails = tempCartDetails;
    UpdateCartCountSpan();
    console.log(CartDetails);
}

function UpdateSubTotal(itemid) {
    //update ItemTotal
    var selectedItemPrice = Number.parseFloat($('#hdnItem_PRICE_' + itemid).val());
    if (isNaN(selectedItemPrice)) {
        var selectedItemPrice = 0;
    }
    var curtotal = Number.parseFloat($('#hdnItem_TotalPRICE_' + itemid).val());
    $('#hdnItem_TotalPRICE_' + itemid).val((curtotal - selectedItemPrice).toFixed(3));
    $('#ItemTotalamt_' + itemid).text(curr + ". " + (curtotal - selectedItemPrice).toFixed(3));
    if ($('#ItemTotalamt_Confirm_' + itemid).length > 0) {
        $('#ItemTotalamt_Confirm_' + itemid).text(curr + ". " + (curtotal - selectedItemPrice).toFixed(3));
    }


    //update subtotal 
    var curSubtotal = Number.parseFloat($('#hdnSubtotal').val());
    $('#hdnSubtotal').val((curSubtotal - selectedItemPrice).toFixed(3));
    $('#divSubtotal').text(curr + ". " + (curSubtotal - selectedItemPrice).toFixed(3));
    if ($('#divSubTotalConfirm').length > 0) {
        $('#divSubTotalConfirm').text(curr + ". " + (curSubtotal - selectedItemPrice).toFixed(3));
    }

    //code for confirm view update Final total amount with deliverycharges
    var TotalAmt = Number.parseFloat(curSubtotal - selectedItemPrice);
    UpdateConfirmViewFinalAmounts(curr, TotalAmt);
}
function UpdateConfirmViewFinalAmounts(curr, TotalAmt) {
    var deliveryCharges = Number.parseFloat($('#hdnAreaDeliveryCharges').val());
    var Subtotal = Number.parseFloat(TotalAmt + deliveryCharges).toFixed(3);
    if ($('#divtotalConfirm').length > 0) {
        $('#divtotalConfirm').html(curr + ". " + Subtotal);
        $('#cartFooterConfirm').show();
        $('#divDeliveryChargesConfirm').html(curr + ". " + Number.parseFloat(deliveryCharges).toFixed(3));
    }
}
function checkcategoryItemExist(catnumb) {
    if ($('#cartCateItems_' + catnumb).children().length == 0) {
        $('#cartCateItems_' + catnumb).remove();
        $('#cartCate_' + catnumb).remove();
    }

    if ($('#cartCateItems_Confirm_' + catnumb).children().length == 0) {
        $('#cartCateItems_Confirm_' + catnumb).remove();
        $('#cartCate_Confirm_' + catnumb).remove();
    }
}
///////////////////////////// menu bind methods
function BindCategory(selectedCategoryId) {

    $('#categoryList').html("");
    $('#itemlist').html("");
    var obji = {
        BrandId: $('#hdnbrandId').val(),
        Branchid: $('#hdnBranchId').val(),
        CategoryId: selectedCategoryId,
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        //url: "/ItemsView/GetCategoryList?BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
        url: "/ItemsView/GetCategoryList",
        success: function (result) {

            if (result.Message == "Success") {
                var Category = result.dtCategory;
                var selectedCatItems = result.dtItems;
                CreateCategoryHtml(Category);
                BindSelectedCategoryItems(selectedCatItems);
            }
        }
    });
}

function CreateCategoryHtml(Category) {

    var Mainstr = "";
    var cntcat = 0;
    $.each(Category, function (i, item) {
        var catname = "";

        if ($('#selectedLang').val() == "EN") {
            catname = item.CAT_NAME;
        }
        else {
            catname = item.CAT_NAME_ARABIC;
        }

        var str = "";
        str = " <div id='Cat_" + item.CAT_NUM + "' onclick='OnCategoryClick(" + item.CAT_NUM + ");' data-val='" + item.CAT_NUM + "' data-text='" + cntcat + "' class='menu-segment-container'>" +
            "<img class='segment-img' src='../../ThumbnailImages/" + item.ImageName + "' style='object-fit: cover;'>" +
            "<div id='Cat_label_" + item.CAT_NUM + "' class='master-menu-segment-button segment-button' role='button' tappable='' aria-pressed='false'>" +
            "<span class='menu-category' style=''>" + catname + "</span>" +
            "<div class='button-effect'></div>" +
            "</div>" +
            "</div> ";
        Mainstr = Mainstr + str;
        cntcat = cntcat + 1;
    });
    $('#categoryList').html(Mainstr);
}
function BindSelectedCategoryItems(Items) {
    var Mainstr = "";
    var selectedCat_num = 0;
    //var selectedCate="";
    $.each(Items, function (i, item) {
        selectedCat_num = item.CAT_NUM;
        var ItemName = "";
        var INGREDIENT = "";
        if ($('#selectedLang').val() == "EN") {
            //selectedCate=item.CAT_NAME;
            ItemName = item.ITEM_NAME;
            INGREDIENT = item.INGREDIENT;
        }
        else {
            // selectedCate=item.CAT_NAME_ARABIC;
            ItemName = item.ITEM_NAME_ARABIC;
            INGREDIENT = item.INGREDIENT_ARABIC;
        }

        var str = "";
        str = "<div id='Item_" + item.id + "' data-val=" + item.CAT_NUM + " class='ng-tns-c0-81 ng-star-inserted'>" +
            "<input id='hdnItemINGREDIENT_" + item.id + "' type='hidden'  value='" + INGREDIENT + "'/>" +
            "<input id='hdnITEM_NAME_" + item.id + "' type='hidden'  value='" + ItemName + "'/>" +
            "<input id='hdnItem_IMAGENAME_" + item.id + "' type='hidden'  value='" + item.IMAGENAME + "'/>" +
            "<input id='hdnItem_PRICE_" + item.id + "' type='hidden'  value='" + item.PRICE + "'/>" +
            "<button id='btnItem_" + item.id + "'  class='menu-item-anchor' prevent-double-click=''>" +
            "<div class='menu-Cat-item item item-block' style='background-color: rgb(255, 255, 255); opacity: 1;'>" +
            "<div onclick='OnItemClick(" + item.id + ");' class='menu-item-thumbnail ng-tns-c0-81 ng-star-inserted' item-start='' style='align-self: flex-start;'>" +
            "<img class='ng-tns-c0-81' src='../../ThumbnailImages/" + item.IMAGENAME + "?fit=crop&amp;w=90&amp;h=90&amp;q=100&amp;fm=jpg' width='100' height='100' style='object-fit: cover;'>" +
            "</div><div class='item-inner'>" +
            "<div class='input-wrapper'>" +
            "<div class='label label-ios ng-star-inserted' style=''>" +
            "<div class='ng-tns-c0-81 Itemrightcontent'>" +
            "<div style='width:100% !important'>" +
            "<h1 onclick='OnItemClick(" + item.id + ");' class='menu-item-header clsitemNameHeader'>" +
            "" + ItemName + "" +
            "</h1>";
        if ($('#hdnIsCartVisible').val() == '1') {
            str = str + "<div onclick='addItemclick(" + item.id + "," + item.HID + ");' class='addbutton' style='float:right !important;'>+</div>";
        }
        str = str + "</div><div style='clear:both !important;'></div>" +

            "<label onclick='OnItemClick(" + item.id + ");' class='menu-ingredient' style='color: rgb(87, 89, 98);'>" +
            "" + INGREDIENT + "" +
            "</label>" +
            "<div onclick='OnItemClick(" + item.id + ");' class='ng-tns-c0-81'>" +
            "<div class='menu-item-footer ng-star-inserted'>" +
            "<span class='item-currency ng-star-inserted' style='color: var(--primary);'>" +
            "" + item.Currency + ". " + item.PRICE + "" +
            "<span class='pricing-list-item-price-info' style='color: rgb(87, 89, 98);'>" +
            "</span>" +
            "</span>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div>" +
            "</div><div class='button-effect'></div>" +
            "</div>" +
            "</button>" +
            "</div>";
        Mainstr = Mainstr + str;
    });
    $('#itemlist').html(Mainstr);
    //$('#selectedCateName').html(selectedCate);

    //remove selected category class and set new selected category
    $(".selectedCate").each(function () {
        $(this).removeClass("selectedCate");
    });
    $('#Cat_label_' + selectedCat_num).addClass("selectedCate");

    $(".selectedSpan").each(function () {
        $(this).removeClass("selectedSpan");
    });
    $('#Cat_' + selectedCat_num).addClass("selectedSpan");
    var index = $('#Cat_' + selectedCat_num).attr("data-text");

    $('.swiper-slide').scrollLeft(index * 108);
    /*$('#Cat_'+selectedCat_num).focus();
    $('#Cat_'+selectedCat_num).scroll();*/
}

function OnCategoryClick(cat_num) {
    selectedCategoryId = cat_num;
    if ($('#hdnIsSubCategoryProject').val() == "true" && IsHaveSubCategory == 1) {
        BindCategory(selectedCategoryId);
    }
    else {
        $('#itemlist').html("");
        //var obji = { Cat_Num : cat_num, BrandId: $('#hdnbrandId').val(),Branchid: $('#hdnBranchId').val()}
        $.ajax({
            type: "Post",
            //data: obji,
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/ItemsView/GetItemList?Cat_Num=" + cat_num + "&BrandId=" + $('#hdnbrandId').val() + "&Branchid=" + $('#hdnBranchId').val(),
            //url: "/ItemsView/GetItemList",
            success: function (result) {

                if (result.Message == "Success") {
                    var Items = result.dtItems;
                    BindSelectedCategoryItems(Items);
                }
            }
        });
    }
}

function OnItemClick(itemid) {
    var modal = document.getElementById("myModal");
    modal.style.display = "block";
    $('#ItemDetailsName').html($('#hdnITEM_NAME_' + itemid).val().trim());
    $('#ItemDetailsPrice').html($('#hdnItem_PRICE_' + itemid).val().trim());
    $('#ItemDescription').html($('#hdnItemINGREDIENT_' + itemid).val().trim());
    $('#itemDetailsImage').attr("src", "../images/" + $('#hdnItem_IMAGENAME_' + itemid).val().trim() + "?w=900&amp;h=600&amp;fit=crop&amp;fm=jpg");
    //modal.attr('Top',$('#Item_'++itemid).clientTop);
    //$('#ItemDetails').show();
    //$('#MenuList').hide();
}

function clearCart() {
    $.confirm({
        title: 'Confirm',
        content: 'Are you sure you want to remove?',
        icon: 'fa fa-question',
        closeAnimation: 'scale',
        opacity: 0.2,
        theme: 'bootstrap',
        closeIcon: true,
        animation: 'scale',
        type: 'orange',
        buttons: {
            'confirm': {
                text: 'Yes',
                btnClass: 'btn-orange',
                action: function () {
                    ClearcartData();
                },
                Cancel: function () {
                    //retval=false;
                },
            }
        }
    });
}
function ClearcartData() {
    debugger;
    var cookieName = "OrderCookie";
    var data = accessCookie(cookieName);
    if (data != "" && data != undefined) {
        document.cookie = cookieName + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }
    checkCookie();
    CartDetails = [];
    $('#cartitemsMainDiv').html("");
    $('#hdnSubtotal').val("0");
    $('#divSubtotal').text(curr + ". " + "0.000");
    UpdateCartCountSpan();


    //new added on 3rd march 2023 , copy from the ItemviewNew/BindCartDetails.js
    var cookieName = "OrderCookie";
    var data = accessCookie(cookieName);
    if (data != "" && data != undefined) {
        document.cookie = cookieName + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }

    var cookieComment = "CommentCookie";
    var dataComment = accessCookie(cookieComment);
    if (dataComment != "" && dataComment != undefined) {
        document.cookie = cookieComment + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }


    var cookieExtraItems = "ExtraItemsCookie";
    var dataExtraItems = accessCookie(cookieExtraItems);
    if (dataExtraItems != "" && dataExtraItems != undefined) {
        document.cookie = cookieExtraItems + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }

    var cookieChoiceItems = "ChoiceItemsCookie";
    var dataChoiceItems = accessCookie(cookieChoiceItems);
    if (dataChoiceItems != "" && dataChoiceItems != undefined) {
        document.cookie = cookieChoiceItems + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }

    debugger;
    //order TPAy Api order confirm cookies clear
    var cookieName1 = "TpayOrderConfirm";
    var cookieData1 = accessCookie(cookieName1);
    if (cookieData1 != "" && cookieData1 != undefined) {
        document.cookie = cookieName1 + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }

    debugger;
    //order TPAy Api order confirm cookies clear
    var cookieName2 = "TpayOrderResponse";
    var cookieData2 = accessCookie(cookieName2);
    if (cookieData2 != "" && cookieData2 != undefined) {
        document.cookie = cookieName2 + "= ; expires = Thu, 01 Jan 2020 00:00:00 GMT"
    }

    checkCookie();


    $('#hdnSubtotal').val("0");
    $('#divSubtotal').text(selectedCurrency + ". " + "0.000");
    if ($('#lblPaymentBillAmountVal').length > 0) {
        $('#lblPaymentBillAmountVal').html("0.000");
        $('#lblPaymentBillAmountCurrency').html(selectedCurrency + ". ");
    }
}
function checkCookie() {
    debugger;
    var data = accessCookie("OrderCookie");
    debugger;
    if (data != "" && data != undefined) {
        var obj = JSON.parse(data);
        CartDetails = obj;
        BindCartCount(CartDetails);
    }
    else {
        $('#cartCount').text(0);
        $('#cartCountDesktop').text(0);
    }
}
function accessCookie(cookieName) {
    debugger;
    var name = cookieName + "=";
    var allCookieArray = document.cookie.split(';');
    for (var i = 0; i < allCookieArray.length; i++) {
        var temp = allCookieArray[i].trim();
        if (temp.indexOf(name) == 0)
            return temp.substring(name.length, temp.length);
    }
    return "";
}

/*function myFunction() {
  var elmnt = document.getElementById("scrolldiv");
  var x = elmnt.scrollLeft;
  var y = elmnt.scrollTop;
    if(y >1)
    {
        $("#TopRow").addClass("toprowbackground");
    }
    else
    {
        $("#TopRow").removeClass("toprowbackground");
    }
}*/

$("#OrderType").change(function () {
    if ($(this).val() == "Delivery") {
        $('.clsDelivery').each(function () {
            $(this).show();
        });
        $('.clsPickup').each(function () {
            $(this).hide();
        });
    }
    else {
        $('.clsDelivery').each(function () {
            $(this).hide();
        });
        $('.clsPickup').each(function () {
            $(this).show();
        });

    }
});
//.change();

function BindSummaryTabData() {

    /*var Htmlstr = $('#CartView').html();
    var FinalHtmlstr = Htmlstr.replace("text:test;", "display:none;");
    FinalHtmlstr = FinalHtmlstr.replace("text:test;", "display:none;");
    $('#orderConfirmCart').html(FinalHtmlstr);*/

    //first tab User Information 
    $('#cnfFirstLastName').html($('#fname').val() + ' ' + $('#lname').val());
    $('#cnfPhoneNumber').html($('#phone').val());
    $('#cnfEmail').html($('#email').val());

    //Second tab Delivery Service Type 
    $('#cnfOrderType').html($('#OrderType').val());

    //Third tab Delivery Service Type 
    if ($('#OrderType').val() == "Delivery") {
        var str = $('#lblArea').html() + ' : ' + $('#AddressArea').children("option:selected").text() + ', '
            + $('#lblBlock').html() + ' : ' + $('#Block').val() + ', ' +
            $('#lblStreet').html() + ' : ' + $('#Street').val() + ', ' +
            $('#lblBuilding').html() + ' : ' + $('#Building').val() + ', ' +
            $('#lblFloor').html() + ' : ' + $('#Floor').val() + ', ' +
            $('#lblFlat').html() + ' : ' + $('#Flat').val() + ', ' +
            $('#lblLandmark').html() + ' : ' + $('#Landmark').val();

        $('#cnfAddressarea').html(str);
        /*$('#cnfBlock').html();
        $('#cnfStreet').html();
        $('#cnfBuilding').html();
        $('#cnfFlat').html();
        $('#cnfLandmark').html();*/
    }
    else {
        $('#cnfAddressarea').html('Area : ' + $('#ddrPickupArea').children("option:selected").text());
    }
}

function setSelected(selecteddiv) {
    $('#divKNET').css('background-color', '');
    $('#divELECTRONIC_CARD').css('background-color', '');
    $('#divCASH').css('background-color', '');
    $('#' + selecteddiv).css('background-color', '#eeeeef');

    if (selecteddiv == "divKNET") {
        $('#selectedPayementType').html("KNET");
    }
    else if (selecteddiv == "divELECTRONIC_CARD") {
        $('#selectedPayementType').html("Credit Card");
    }
    else {
        $('#selectedPayementType').html("Cash on delivery");
    }
}

function SubmitOrder() {
    debugger;
    var customerInfo = {}
    
    customerInfo["id"] = 0;
    customerInfo["CustomerName"] = $('#fname').val() + ' ' + $('#lname').val();
    customerInfo["Mobile"] = $('#phone').val();
    //customerInfo["Mobile2"] = $('#phone').val();
    customerInfo["CivilID"] = $('#txtCustomerCivilID').val();

    var addressInfo = {}
    addressInfo["id"] = 0;
    addressInfo["CustomerId"] = 0;
    addressInfo["Email"] = $('#email').val();
    if ($('#OrderType').val() == "Delivery") {
        addressInfo["Areaid"] = $('#AddressArea').val();
    }
    else {
        addressInfo["Areaid"] = $('#ddrPickupArea').val();
    }
    //addressInfo["AreaName"] = "";
    addressInfo["Block"] = $('#Block').val();
    addressInfo["Street"] = $('#Street').val();
    addressInfo["Lane"] = $('#Landmark').val();
    addressInfo["Building"] = $('#Building').val();
    addressInfo["Flat"] = $('#Flat').val();
    addressInfo["Floor"] = $('#Floor').val();
    addressInfo["HouseNo"] = "";
    //addressInfo["PACI"] = "";
    addressInfo["AddressRemark"] = "";
    addressInfo["Lat"] = $('#hdnlat').val();
    addressInfo["Long"] = $('#hdnlong').val();

    //use this new object with full key name  //changes on 30-oct-2020
    var objCartDetails = CartDetails;
    var ObjDataCartDetails = [];
    $.each(objCartDetails, function (i, obj) {
        var item = {}
        item["ItemId"] = obj.I;
        item["HID"] = obj.O;
        item["qty"] = obj.Q;
        item["Comments"] = $('#comments_Confirm_' + obj.I).val();
        item["ChoiceId"] = obj.CH;
        /*item["CH"] = obj.CH;*/
        ObjDataCartDetails.push(item);
    });


    var objdata = {
        orderDetails: ObjDataCartDetails,
        customerInfo: customerInfo,
        addressInfo: addressInfo,
        selectedPayementType: $('#selectedPayementType').html(),
        branchid : 1
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(objdata),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/SubmitOrder",
        success: function (result) {
            if (result.Message == "Success") {
                $.confirm({
                    title: 'Order No: ' + result.InvoiceNo + '',
                    //content: 'Your order has been successfully process. Your order no is ' + result.InvoiceNo + '.',
                    content: 'Your order has been successfully been processed. An Invoice has been emailed to you.',
                    //icon: 'fa fa-question',
                    closeAnimation: 'scale',
                    opacity: 0.2,
                    theme: 'bootstrap',
                    //closeIcon: true,
                    animation: 'scale',
                    type: 'orange',
                    buttons: {
                        'confirm': {
                            text: 'Continue Shopping',
                            btnClass: 'btn-orange',
                            action: function () {
                                //ShowNotification("Your order has been successfully process. Your order no is " + result.InvoiceNo + ".");
                                ClearcartData();
                                ShowMenuclick();
                            },
                            Cancel: function () {
                                //retval=false;
                                ClearcartData();
                                ShowMenuclick();
                            },
                        }
                    }
                });

            }
            else {
                ShowNotification(result.Message);
            }
        }
    });
}
var mymap = null;
function TrackOrder() {


    BindTrackorderdata();
}

function BindTrackorderdata() {
    document.getElementById('mapcontainer').innerHTML = "<div id='mapid' style='width: 100%; height: 100%;' class='top_map_objects'></div>";

    $('.smartcms_ost_timeline').hide();
    $('.smartcms_ost_map').hide();
    $('#msgTrackOrderBlank').hide();
    $('#msgTrackOrderWrong').hide();
    $('#msgContactManager').hide();

    if ($('#txtTrackorderNumber').val() == "") {
        $('#msgTrackOrderBlank').show();
        return false;
    }
    var obj = {
        InoiceNumber: $('#txtTrackorderNumber').val()
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/TrackOrder",
        success: function (result) {
            if (result.Message == "Success") {
                var Status = JSON.parse(result.InvoiceStatus);
                /*$('#OrderReceived').removeClass("last_track");
                $('#OrderShipped').removeClass("last_track");
                $('#OrderEnRoute').removeClass("last_track");
                $('#OrderArrived').removeClass("last_track");*/
                $('.last_track').each(function () {
                    $(this).removeClass("last_track");
                });
                if (Status == "0") { //Order Received
                    $('#OrderReceived').addClass("last_track");
                }
                else if (Status == "1") { //OrderShipped
                    $('#OrderShipped').addClass("last_track");
                }
                else if (Status == "2") { //OrderEnRoute
                    $('#OrderEnRoute').addClass("last_track");
                }
                else if (Status == "3") { //OrderArrived
                    $('#OrderArrived').addClass("last_track");
                }
                $('.smartcms_ost_timeline').show();
                $('.smartcms_ost_map').show();

                debugger;
                mymap = new L.Map('mapid', {
                    center: [0, 0],
                    zoom: 0,
                    layers: [
                        //new L.TileLayer('http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                        //    'attribution': 'Map data © <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
                        //})
                        new L.TileLayer('https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png', {
                            'attribution': '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                        })
                    ]
                }).setView([29.378586, 47.990341], 12);

                $.each(result.dtMapData, function (key, value) {
                    mymap.setView([value.CurrentLat, value.CurrentLong], 15);
                });
                setInterval(function () {
                    setTrackOrderMap();
                }, 3000);
            } else {
                if (result.Message == "Invalid Invoice Number.") {
                    $('#msgTrackOrderWrong').show();
                }
                else if (result.Message == "Error,Contact Your Manager.") {
                    //$('#msgContactManager').show();
                    $('#msgContactManager').show();
                }
            }
        }
    });
}
function BindAreaDropdown() {
    $.ajax({
        type: "Post",
        //data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/GetAreaList",
        success: function (result) {
            debugger;
            $('#AddressArea').html("");
            var areastr = "<option id='optionSelect' value=''>Select</option>";
            if (result.Message == "Success") {
                var ObjAreaList = JSON.parse(result.dtresult);
                $.each(ObjAreaList, function (index, jsonObject) {
                    var AreaName = "";
                    if ($('#selectedLang').val() == "EN") {
                        AreaName = jsonObject.AreaName;
                    }
                    else {
                        AreaName = jsonObject.AreaNameAra;
                    }

                    areastr = areastr + "<option value='" + jsonObject.AreaID + "' data-val='" + jsonObject.DeliveryCharges + "''>" + AreaName + "</option>";
                    //$.each(jsonObject, function (key, val) {
                    //    console.log("key : " + key + " ; value : " + val);
                    //});
                });

            } else {
                if (result.Message == "Invalid Invoice Number.") {
                    $('#msgTrackOrderWrong').show();
                }
                else if (result.Message == "Error,Contact Your Manager.") {
                    //$('#msgContactManager').show();
                    $('#msgTrackOrderWrong').show();
                }
            }
            $('#AddressArea').html(areastr);
            $('#AddressArea').val($('#hdnSelectedArea').val());
        }
    });
}

function ddrAreaChangeBindDelCharg(obj) {
    var selectedDeliveryCharge = $(obj).find(':selected').attr('data-val');
    $('#hdnAreaDeliveryCharges').val(selectedDeliveryCharge);
    $('#hdnSelectedArea').val($(obj).find(':selected').val());
}

$(document).on('click', '.menu-item', function (e) {
    $('#kt_header_mobile_toggle').click()
    //jQuery.each($('.header-navs-on'), function (i, val) {
    //    $(this).removeClass("header-navs-on");
    //    $('.header-navs-overlay').remove();
    //    $('.burge-icon-active').removeClass("burge-icon-active");
    //}); 
});


//////////////////start track order generate map events///////////////////////
var mapboxUrl = 'https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token=__MAPBOX_ACCESS_TOKEN__';
var mapboxAttribution = 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, ' +
    '<a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, ' +
    'Imagery © <a href="https://www.mapbox.com/">Mapbox</a>';

/*var mapboxUrl='http://{s}.tile.osm.org/{z}/{x}/{y}.png';
var mapboxAttribution='&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors';*/
var LeafIcon = L.Icon.extend({
    options: {
        //shadowUrl: 'leaf-shadow.png',
        //iconSize:     [45, 40],
        //shadowSize:   [50, 64],
        iconAnchor: [30, 40],
        //shadowAnchor: [4, 62],
        popupAnchor: [-3, -35]
    }
});



var DriverMarkinlayersToRemove = [];
var polylinelayersToRemove = [];

function setTrackOrderMap() {
    debugger;
    var obj = {
        InoiceNumber: $('#txtTrackorderNumber').val()
    }
    $.ajax({
        type: "Post",
        data: JSON.stringify(obj),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/ItemsView/TrackOrder",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                BindTrackorderMap(result.dtMapData);
            } else {
            }
        }
    });

}
function BindTrackorderMap(objdata) {
    debugger;
    /*var mymap = L.map('mapid', {
        //center: [39.73, -104.99],
       // zoom: 10,
       // layers: [grayscale, cities]
    }).setView([29.378586, 47.990341], 12);*/




    /*L.tileLayer(mapboxUrl, {
       maxZoom: 20,
       attribution: mapboxAttribution,
       id: 'mapbox.streets'
   }).addTo(mymap);*/

    //first remove old driverMarkins
    for (i = 0; i < DriverMarkinlayersToRemove.length; i++) {
        mymap.removeLayer(DriverMarkinlayersToRemove[i]);
    }
    DriverMarkinlayersToRemove = [];

    //first remove old path
    for (i = 0; i < polylinelayersToRemove.length; i++) {
        mymap.removeLayer(polylinelayersToRemove[i]);
    }
    polylinelayersToRemove = [];

    debugger
    $.each(objdata, function (key, value) {
        debugger;
        //var carIcon = new LeafIcon({iconUrl: '../../Content/maps/images/car.png'}),
        //CustomerIcon = new LeafIcon({iconUrl: '../../Content/maps/images/Customer.png'});

        var carIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/' + value.DriverImage }),
            CustomerIcon = new LeafIcon({ iconUrl: '../../Content/maps/images/Customer.png' });

        var DriverMarkin = L.marker([value.CurrentLat, value.CurrentLong], { icon: carIcon }).bindPopup('Driver Name: ' + value.DriverName)
        DriverMarkin.addTo(mymap);
        DriverMarkinlayersToRemove.push(DriverMarkin);


        var CustMarkin = L.marker([value.ToLat, value.ToLong], { icon: CustomerIcon }).bindPopup('Customer : ' + value.CustomerName + '\n,InvoiceNo: ' + value.InvoiceNo)
        CustMarkin.addTo(mymap);

        //mymap.setView([value.ToLat, value.ToLong], 14);

        //draw path
        var pointA = new L.LatLng(value.CurrentLat, value.CurrentLong);
        var pointB = new L.LatLng(value.ToLat, value.ToLong);
        var pointList = [pointA, pointB];
        var firstpolyline = new L.Polyline(pointList, {
            color: value.DriverColor,
            weight: 7,
            opacity: 0.7,
            smoothFactor: 1
        });

        firstpolyline.addTo(mymap);
        polylinelayersToRemove.push(firstpolyline);
    });

    //setClickOnmapclick(mymap);
}
//////////////////End track order generate map events///////////////////////