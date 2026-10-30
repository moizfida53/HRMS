var ItemsData;
var Category;
var CategoryLock = true;
var DataAdapterCategory;
var IsItemUpdate = '0';
var dataAdapterBrandList;
$(document).ready(function () {
    $('#jqxTabs').jqxTabs({ width: '100%', height: 800, position: 'top' });
    $("#Window").jqxWindow({ height: '100%', width: '70%', theme: 'summer', isModal: true, autoOpen: false });
    $("#WinBrand").jqxWindow({ height: '100%', width: '75%', theme: 'summer', isModal: true, autoOpen: false });
    $("#WinBranch").jqxWindow({ height: '100%', width: '75%', theme: 'summer', isModal: true, autoOpen: false });
    $("#WinGenerateQRcode").jqxWindow({ height: '100%', width: '75%', theme: 'summer', isModal: true, autoOpen: false });
    GetThemes();
    InitializeLoaders();

    var t = "<div> <img src='no_image.png' />  </div>";
    $("#img").html(t);
    $("#imgBrand").html(t);


    hideMainCategory();
    GetWaiter();
    GetBrands();



    GetCategory();
    GetFeedBackLayouts();

    GetRole();
    btnClearItem();

    BindExtraCommentsDdr();
    $('#chkIsExtraItems').change(function () {
        debugger;
        nonExtraItemsControlsHideshow();
    });
});

function nonExtraItemsControlsHideshow() {
    debugger;
    if ($('#chkIsExtraItems').prop("checked")) {
        var els = document.getElementsByClassName("nonExtra");
        Array.prototype.forEach.call(els, function (el) {
            $(el).hide();
        });
        //$('#trExtraItemsAndComments').show();
    }
    else {
        var els = document.getElementsByClassName("nonExtra");
        Array.prototype.forEach.call(els, function (el) {
            $(el).show();
        });
        //$('#trExtraItemsAndComments').hide();
    }
}
function InitializeLoaders() {
    debugger;
    $('#jqxFileUpload,#jqxFileUploadBrand,#jqxCategoryActive,#jqxCategoryInActive,#jqxHomeScreen,#jqxEnglishButton,#jqxArabicButton,#jqxCloseButton,#jqxPopUpBackground').jqxFileUpload({
        width: 300,
        uploadUrl: '/Items/UploadFile',
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        multipleFilesUpload: false,
        localization: { browseButton: 'Select Image', uploadButton: 'Upload Image', cancelButton: 'Cancel' }
    });
    var WebBrandID = $("#ddWebSlideShowBrand").val();
    var MobileBrandID = $("#ddSlideShowBrand").val();
    $('#jqxSlideShows').jqxFileUpload({
        width: 300,
        //  uploadUrl: '/Items/UploadSlideShowImages?isMobile=true&BrandID=' + MobileBrandID,
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        multipleFilesUpload: true,
        localization: { browseButton: 'Select Image', uploadButton: 'Upload Image', cancelButton: 'Cancel' }
    });


    $('#jqxWebSlideShows').jqxFileUpload({
        width: 300,
        // uploadUrl: '/Items/UploadSlideShowImages?isMobile=False&BrandID=' + WebBrandID,
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        multipleFilesUpload: true,
        localization: { browseButton: 'Select Image', uploadButton: 'Upload Image', cancelButton: 'Cancel' }
    });
    $('#jqxPromotion').jqxFileUpload({
        width: 300,
        //  uploadUrl: '/Items/UploadSlideShowImages?isMobile=true&BrandID=' + MobileBrandID,
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        multipleFilesUpload: true,
        localization: { browseButton: 'Select Image', uploadButton: 'Upload Image', cancelButton: 'Cancel' }
    });
    $('#jqxVideoUpload').on('uploadStart', function (event) {
        showLoading();
    });
    $('#jqxVideoUpload').on('uploadEnd', function (event) {
        hideLoading();
        var args = event.args;
        var fileName = args.file;
        var serverResponce = args.response;
        fileName = RenameFile(fileName);
        $("#lblVideo").html(fileName);

        var p = "../../Video/" + fileName;
    });
    $('#jqxVideoUpload').jqxFileUpload({
        width: 300,
        uploadUrl: '/Items/UploadVideo',
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        localization: { browseButton: 'Select Video', uploadButton: 'Upload Video', cancelButton: 'Cancel' }
    });

    $('#jqxFileUpload').on('uploadStart', function (event) {
        debugger;
        showLoading();
    });
    $('#jqxFileUpload').on('uploadEnd', function (event) {
        debugger;
        hideLoading();
        var args = event.args;
        var fileName = args.file;
        var serverResponce = args.response;
        fileName = RenameFile(fileName);
        $("#lblFileName").html(fileName);

        var p = "../../images/" + fileName;
        var t;
        t = "<div> <img src=" + p + "  width='87' height='58' />  </div>";

        $("#img").html(t);
    });


    $('#jqxFileUploadBrand').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;

        var serverResponce = args.response;
        $("#lblFileNameBrand").html(fileName);
        var p = "../../images/" + fileName;
        var t;
        t = "<div> <img src=" + p + "  width='87' height='58' />  </div>";

        $("#imgBrand").html(t);
    });



    //Themes Loaders


    $('#jqxCategoryActive').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblCategoryActive").html(args.file);
        CreateImage("#imgCategoryActive", fileName)
    });
    $('#jqxCategoryInActive').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblCategoryInActive").html(args.file);
        CreateImage("#imgCategoryInActive", fileName)
    });

    $('#jqxCloseButton').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lbCloseButton").html(args.file);
        CreateImage("#imgCloseButton", fileName)
    });
    $('#jqxHomeScreen').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblHomeScreen").html(args.file);
        CreateImage("#imgHomeScreen", fileName)
    });
    $('#jqxEnglishButton').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblEnglishButton").html(args.file);
        CreateImage("#imgEnglishButton", fileName)
    });


    $('#jqxArabicButton').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblArabicButton").html(args.file);
        CreateImage("#imgArabicButton", fileName)
    });
    $('#jqxPopUpBackground').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblPopUpBackground").html(args.file);
        CreateImage("#imgPopUpBackground", fileName)
    });


    $('#jqxSlideShows').on('uploadEnd', function (event) {
        var MobileBrandID = $("#ddSlideShowBrand").val();

        if (MobileBrandID == "") {
            alert("Please Select Brand");
            return;
        }
        var args = event.args;
        var fileName = args.file;
        $("#lblSlideShows").html(args.file);
        CreateImage("#imgSlideShows", fileName)
        CreateImageSequenceTable($("#ddSlideShowBrand").val())
    });

    $('#jqxWebSlideShows').on('uploadEnd', function (event) {
        var WebBrandID = $("#ddWebSlideShowBrand").val();
        if (WebBrandID == "") {
            alert("Please Select Brand");
            return;
        }
        var args = event.args;
        var fileName = args.file;
        $("#lblWebSlideShows").html(args.file);
        CreateImage("#imgWebSlideShows", fileName)
        CreateWebSlideShowTable(WebBrandID)
    });

    $('#jqxPromotion').on('uploadEnd', function (event) {
        var MobileBrandID = $("#ddPromtionBrand").val();

        if (MobileBrandID == "") {
            alert("Please Select Brand");
            return;
        }
        var args = event.args;
        var fileName = args.file;
        $("#lblPromotion").html(args.file);
        CreateImage("#imgPromotion", fileName)
        CreateImagePromotionTable($("#ddPromtionBrand").val())
    });

}
$("#chkIsBrandPromotionShow").change(function () {
    debugger;
    var isselected = false;
    if (this.checked) {
        isselected = true;
    }
    var obj = { brandID: $("#ddPromtionBrand").val(), IsSelected: isselected }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obj),
        url: "/Items/BrandPromotionShowChange",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {

        }

    });

});
//function hide() {
//    if (OtherLanguages == "False") {
//        document.getElementById("Languageingr").style.display = 'none';
//        document.getElementById("itemNameLanguage").style.display = 'none';
//        $("#chklang").hide();
//        $("#CatLanguage").hide();
//        $("#Languageingr").hide();
//        $("#itemNameLanguage").hide();

//    }

//}

function RenameFile(FileName) {
    var file = FileName.toLowerCase();
    for (var i = 0; i < FileName.length; i++) {
        file = file.toLowerCase();
        file = file.trim();
        file = file.replace("-", "_");
        file = file.replace("%", "_");
        file = file.replace("*", "_");
        file = file.replace("&", "_");
        file = file.replace("#", "_");
        file = file.replace("@", "_");
        file = file.replace("'", "_");
        file = file.replace(" ", "_");
    }
    return file;
}
function GetItems(CatNo) {
    $("#btnUpdateItem").hide("slow");
    $("#btnDeleteItem").hide("slow");
    $("#btnAddItem").show("slow");
    ClearItem();
    var obji = { CatNo: CatNo }
    $.ajax({
        type: "Post",
        data: obji,
        cache: false,
        url: "/Items/Item",
        success: function (result) {
            var Items = result.dtItems;
            CreateItemsTable(Items);
            //  FillItems(Items);
        }
    });
}


function CreateItemsTable(Data) {

    var myTableDiv = document.getElementById("ItemsTable");
    t = "";

    $("#ItemsTable").html(myTableDiv);
    var table = document.createElement('TABLE');
    table.border = '1';
    table.classList.add("DragDropCategory");
    table.id = "tblDragDropItems"
    table.className = "DragDropCategory";
    var tableBody = document.createElement('TBODY');
    table.appendChild(tableBody);

    var thead = document.createElement('thead');

    table.appendChild(thead);
    thead.appendChild(document.createElement("th"));

    var orderArrayHeader = ["Category Name", "Item Name", "Ingredient (English)", "Item Name Arabic", "Ingredient (Arabic)", "Unit Price", "Image Name", "Brand Name", "IsExtra"];

    for (var i = 0; i < orderArrayHeader.length; i++) {
        thead.appendChild(document.createElement("th")).
            appendChild(document.createTextNode(orderArrayHeader[i]));
    }


    for (var i = 0; i < Data.length; i++) {
        var tr = document.createElement('TR');
        tableBody.appendChild(tr);

        var Drag = document.createElement('TD');
        Drag.appendChild(document.createTextNode(""));
        Drag.classList.add("sorter");
        tr.appendChild(Drag);
        var CAT_NAME = document.createElement('TD');
        CAT_NAME.appendChild(document.createTextNode(Data[i].CAT_NAME));
        tr.appendChild(CAT_NAME);

        var ITEM_NAME = document.createElement('TD');
        ITEM_NAME.appendChild(document.createTextNode(Data[i].ITEM_NAME));
        tr.appendChild(ITEM_NAME);

        var INGREDIENT = document.createElement('TD');
        INGREDIENT.appendChild(document.createTextNode(Data[i].INGREDIENT));
        tr.appendChild(INGREDIENT);


        var ITEM_NAME_ARABIC = document.createElement('TD');
        ITEM_NAME_ARABIC.appendChild(document.createTextNode(Data[i].ITEM_NAME_ARABIC));
        ITEM_NAME_ARABIC.style.width = '150px';
        tr.appendChild(ITEM_NAME_ARABIC);

        var INGREDIENT_ARABIC = document.createElement('TD');
        INGREDIENT_ARABIC.appendChild(document.createTextNode(Data[i].INGREDIENT_ARABIC));
        tr.appendChild(INGREDIENT_ARABIC);

        var PRICE = document.createElement('TD');
        PRICE.appendChild(document.createTextNode(Data[i].PRICE));
        PRICE.style.width = '20px';
        tr.appendChild(PRICE);

        var IMAGENAME = document.createElement('TD');
        IMAGENAME.appendChild(document.createTextNode(Data[i].IMAGENAME));
        tr.appendChild(IMAGENAME);

        var BrandName = document.createElement('TD');
        BrandName.appendChild(document.createTextNode(Data[i].BrandName));
        BrandName.style.width = '150px';
        tr.appendChild(BrandName);

        var IsExtraItems = document.createElement('TD');
        IsExtraItems.appendChild(document.createTextNode(Data[i].IsExtraItems));
        IsExtraItems.style.width = '10px';
        tr.appendChild(IsExtraItems);

        //Invisible Fields

        var ID = document.createElement('TD');
        ID.appendChild(document.createTextNode(Data[i].ID));
        ID.classList.add("invisible");
        tr.appendChild(ID);
        var CAT_NUM = document.createElement('TD');
        CAT_NUM.appendChild(document.createTextNode(Data[i].CAT_NUM));
        CAT_NUM.classList.add("invisible");
        tr.appendChild(CAT_NUM);
        var Video = document.createElement('TD');
        Video.appendChild(document.createTextNode(Data[i].Video));
        Video.classList.add("invisible");
        tr.appendChild(Video);
        var BrandID = document.createElement('TD');
        BrandID.appendChild(document.createTextNode(Data[i].BrandID));
        BrandID.classList.add("invisible");
        tr.appendChild(BrandID);
        var ShowInTablet = document.createElement('TD');
        ShowInTablet.appendChild(document.createTextNode(Data[i].ShowInTablet));
        ShowInTablet.classList.add("invisible");
        tr.appendChild(ShowInTablet);



        tr.dataset.ID = Data[i].ID;
        tr.dataset.CAT_NUM = Data[i].CAT_NUM;
        tr.dataset.Video = Data[i].Video;
        tr.dataset.CAT_NAME = Data[i].CAT_NAME;
        tr.dataset.ITEM_NAME = Data[i].ITEM_NAME;
        tr.dataset.INGREDIENT = Data[i].INGREDIENT;
        tr.dataset.ITEM_NAME_ARABIC = Data[i].ITEM_NAME_ARABIC;
        tr.dataset.PRICE = Data[i].PRICE;
        tr.dataset.INGREDIENT_ARABIC = Data[i].INGREDIENT_ARABIC;
        tr.dataset.IMAGENAME = Data[i].IMAGENAME;
        tr.dataset.BrandName = Data[i].BrandName;
        tr.dataset.BrandID = Data[i].BrandID;
        tr.dataset.ShowInTablet = Data[i].ShowInTablet;
        tr.dataset.IsExtraItems = Data[i].IsExtraItems;

        tr.onclick = function () {
            CategoryLock = false;
            $('tr').removeClass('high-light');
            $(this).addClass("high-light");
            SetupItemText(this);
        };
    }
    myTableDiv.appendChild(table);

    RowSorter(gebi('tblDragDropItems'), {
        handler: 'td.sorter',
        onDrop: function (tbody, row, new_index, old_index) {
            var table = tbody.nodeName === 'TBODY' ? tbody.parentNode : tbody;
            var value = [];

            for (var i = 0; i < tbody.childNodes.length; i++) {
                value[i] = {
                    "CAT_NUM": tbody.childNodes[i].dataset.CAT_NUM,
                    "ID": tbody.childNodes[i].dataset.ID,
                    "Seq_Num": tbody.childNodes[i].rowIndex,
                };
            }
            var obji = { value: value }
            $.ajax({
                type: "POST",
                url: "/items/UpdateItemSequence",
                data: JSON.stringify(obji),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function (result) {
                    GetItems();
                }
            });
        }
    });
}
function SetupItemText(item) {
    debugger;
    var row = item.dataset;

    $("#btnUpdateItem").show("slow");
    $("#btnDeleteItem").show("slow");
    $("#btnAddItem").hide("slow");
    $('#ddBrands').val(row.BrandID);
    //$('#ddBranchs').val(row.BrandID);
    $('#ddCategory').val(row.CAT_NUM);
    var ID = row.ID;
    var BrandId = row.BrandID;
    var ITEM_NAME = row.ITEM_NAME;
    var ITEM_NAME_ARABIC = row.ITEM_NAME_ARABIC;
    var PRICE = row.PRICE;
    var INGREDIENT = row.INGREDIENT;
    var INGREDIENT_ARABIC = row.INGREDIENT_ARABIC;
    var IMAGENAME = row.IMAGENAME;
    var ITEM_DESC_ENG = row.ITEM_DESC_ENG;
    var Seq_Num = row.Seq_Num;
    $('#txtItemID').val(ID);

    $("#lblVideo").html(row.Video);
    $("#txtItemNameEng").val(ITEM_NAME);
    $("#txtItemNameAra").val(ITEM_NAME_ARABIC);
    $("#txtItemNameRus").val(row.ItemNameRus);
    $("#txtItemNameMan").val(row.ItemNameMan);
    $("#txtPrice").val(PRICE);
    $("#txtIngEng").val(INGREDIENT);
    $("#txtIngAra").val(INGREDIENT_ARABIC);
    $("#txtIngRus").val(row.INGREDIENT_Rus);
    $("#txtIngMan").val(row.INGREDIENT_Man);
    $("#Image").val(IMAGENAME);
    $("#txtDescription").val(ITEM_DESC_ENG);
    //$("#txtSequenceNo").val(Seq_Num);
    $('#lblFileName').html(IMAGENAME);

    debugger;
    if (row.IsExtraItems == "true") {
        $("#chkIsExtraItems").prop("checked", true);
        nonExtraItemsControlsHideshow();
    }
    else {
        $("#chkIsExtraItems").prop("checked", false);
        nonExtraItemsControlsHideshow();
    }

    if (row.ShowInTablet == "true") {
        $('input[name=isItem][value=true]').prop('checked', true);
    } else {
        $('input[name=isItem][value=false]').prop("checked", true)
    }
    if (IMAGENAME == "")
        var p = "../../images/no_image.png"
    else
        var p = "../../images/" + IMAGENAME;

    var t;

    t = "<div> <img src=" + p + "  width='87' height='58'  />  </div>";

    $("#img").html(t);
    $("#ddBrands").val();
    $("#ddBranchs").jqxDropDownList('uncheckAll');
    $("#ddExtraItems").jqxDropDownList('uncheckAll');
    $("#ddExtraComments").jqxDropDownList('uncheckAll');
    // bind brands items wise 
    var value = {
        "ID": ID,
        "BrandID": BrandId
    };
    $.ajax({
        type: "POST",
        cache: false,
        async: false,
        url: "/items/GetAssignedBranchItemsAndComments",
        data: value,
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Branch = result.dtBranch;
                var selectedExtraItems = result.dtExtraitems;
                var selectedComments = result.dtComments;

                //set selected Branches
                $.each(Branch, function (key, val1) {
                    $("#ddBranchs").jqxDropDownList('checkItem', val1.BranchId);
                });

                //set selected Extra Items
                $.each(selectedExtraItems, function (key, val1) {
                    $("#ddExtraItems").jqxDropDownList('checkItem', val1.id);
                });

                //set selected Comments
                $.each(selectedComments, function (key, val1) {
                    $("#ddExtraComments").jqxDropDownList('checkItem', val1.id);
                });
            }
            else {
                alert(result.Message);
            }
        }
    });

}
function AddItem() {
    debugger;
    var PackageData = new Array();
    var SelectedExtraItems = new Array();
    var SelectedComments = new Array();

    if (!$('#chkIsExtraItems').prop("checked")) {
        //Start get selected Branches
        var Package = $("#ddBranchs").jqxDropDownList('getCheckedItems');
        if (Package != undefined) {
            if (Package.length > 0) {
                for (var i = 0; i < Package.length; i++) {
                    var RowData = Package[i].value;
                    PackageData[i] = { "BranchId": RowData };
                }
            }
            else {
                Package = $("#ddBranchs").jqxDropDownList('getItems');
                for (var i = 0; i < Package.length; i++) {
                    var RowData = Package[i].value;
                    PackageData[i] = { "BranchId": RowData };
                }
            }

        } else {
            $("#ddBranchs").notify('Please Select Branch', { position: "right" });
            return;
        }
        //End get selected Branches
       

        //Start get selected Extra items
        var ExtraItems = $("#ddExtraItems").jqxDropDownList('getCheckedItems');
        if (ExtraItems != undefined) {
            if (ExtraItems.length > 0) {
                for (var i = 0; i < ExtraItems.length; i++) {
                    var RowData = ExtraItems[i].value;
                    SelectedExtraItems[i] = { "id": RowData };
                }
            }
        } else {
            $("#ddExtraItems").notify('Please Select Extra Items', { position: "right" });
            return;
        }
        //End get selected Extra items


        //Start get selected Comments
        var Comments = $("#ddExtraComments").jqxDropDownList('getCheckedItems');
        if (Comments != undefined) {
            if (Comments.length > 0) {
                for (var i = 0; i < Comments.length; i++) {
                    var RowData = Comments[i].value;
                    SelectedComments[i] = { "id": RowData };
                }
            }
        } else {
            $("#ddExtraComments").notify('Please Select Extra Items', { position: "right" });
            return;
        }
        //End get selected Comments
    }

    var ImageName = $('#lblFileName').text();
    ImageName = ImageName.replace(" ", "_");
    if ($("#ddCategory").val() == '') {

        $("#ddCategory").notify('Please Select Category', { position: "top" });
        return;
    }
    if ($("#txtItemNameEng").val() == "") {
        $("#txtItemNameEng").notify('Please insert Item Name', { position: "right" });
        return;
    }


    var value = {
        "CAT_NUM": $('#ddCategory').val(),
        "ITEM_NAME": $("#txtItemNameEng").val(),
        "ItemNameRus": $("#txtItemNameRus").val(),
        "ItemNameMan": $("#txtItemNameMan").val(),
        "ITEM_NAME_ARABIC": $("#txtItemNameAra").val(),
        "PRICE": $("#txtPrice").val(),
        "IMAGENAME": ImageName,
        "INGREDIENT": $("#txtIngEng").val(),
        "INGREDIENT_ARABIC": $("#txtIngAra").val(),
        "INGREDIENT_Rus": $("#txtIngRus").val(),
        "INGREDIENT_Man": $("#txtIngMan").val(),
        "ITEM_DESC_ENG": $("#txtDescription").val(),
        // "Seq_Num": $("#txtSequenceNo").val(),
        "Video": $("#lblVideo").text(),
        "ShowInTablet": $("input[name=isItem]:checked").val(),
        "BranchData": PackageData,
        "BrandID": $("#ddBrands").val(),
        "IsExtraItems": $('#chkIsExtraItems').prop("checked"),
        "ExtraItems": SelectedExtraItems,
        "Comments": SelectedComments,
    };


    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddItem",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            IsItemUpdate = '1';
            alert(result.Message);
            GetItems($('#ddCategory').val());
        },
        error: function (data, data2, data3) {
            alert('failed');
        }
    });

}
function UpdateItem() {
    debugger;
    var PackageData = new Array();
    var SelectedExtraItems = new Array();
    var SelectedComments = new Array();
    if (!$('#chkIsExtraItems').prop("checked")) {
        //Start get selected Branches
        var Package = $("#ddBranchs").jqxDropDownList('getCheckedItems');
        if (Package != undefined) {
            if (Package.length > 0) {
                for (var i = 0; i < Package.length; i++) {
                    var RowData = Package[i].value;
                    PackageData[i] = { "BranchId": RowData };
                }
            }
            else {
                Package = $("#ddBranchs").jqxDropDownList('getItems');
                for (var i = 0; i < Package.length; i++) {
                    var RowData = Package[i].value;
                    PackageData[i] = { "BranchId": RowData };
                }
            }

        } else {
            $("#ddBranchs").notify('Please Select Brand', { position: "right" });
            return;
        }
        //End get selected Branches

        //Start get selected Extra items
        var ExtraItems = $("#ddExtraItems").jqxDropDownList('getCheckedItems');
        if (ExtraItems != undefined) {
            if (ExtraItems.length > 0) {
                for (var i = 0; i < ExtraItems.length; i++) {
                    var RowData = ExtraItems[i].value;
                    SelectedExtraItems[i] = { "id": RowData };
                }
            }
        } else {
            $("#ddExtraItems").notify('Please Select Extra Items', { position: "right" });
            return;
        }
        //End get selected Extra items


        //Start get selected Comments
        var Comments = $("#ddExtraComments").jqxDropDownList('getCheckedItems');
        if (Comments != undefined) {
            if (Comments.length > 0) {
                for (var i = 0; i < Comments.length; i++) {
                    var RowData = Comments[i].value;
                    SelectedComments[i] = { "id": RowData };
                }
            }
        } else {
            $("#ddExtraComments").notify('Please Select Extra Items', { position: "right" });
            return;
        }
        //End get selected Comments
    }

    var ImageName = $('#lblFileName').text();
    ImageName = ImageName.replace(" ", "_");
    if ($("#ddCategory").val() == '') {

        $("#ddCategory").notify('Please Select Category', { position: "top" });
        return;
    }
    if ($("#txtItemNameEng").val() == "") {
        $("#txtItemNameEng").notify('Please insert Item Name', { position: "right" });
        return;
    }

    var value = {
        "ID": $('#txtItemID').val(),
        "CAT_NUM": $('#ddCategory').val(),
        "ITEM_NAME": $("#txtItemNameEng").val(),
        "ItemNameRus": $("#txtItemNameRus").val(),
        "ItemNameMan": $("#txtItemNameMan").val(),
        "ITEM_NAME_ARABIC": $("#txtItemNameAra").val(),
        "PRICE": $("#txtPrice").val(),
        "INGREDIENT": $("#txtIngEng").val(),
        "INGREDIENT_ARABIC": $("#txtIngAra").val(),
        "INGREDIENT_Rus": $("#txtIngRus").val(),
        "INGREDIENT_Man": $("#txtIngMan").val(),
        "IMAGENAME": ImageName,
        "Video": $("#lblVideo").text(),
        "ITEM_DESC_ENG": $("#txtDescription").val(),
        //"Seq_Num": $("#txtSequenceNo").val(),
        "ShowInTablet": $("input[name=isItem]:checked").val(),
        "BranchData": PackageData,
        "BrandID": $("#ddBrands").val(),
        "IsExtraItems": $('#chkIsExtraItems').prop("checked"),
        "ExtraItems": SelectedExtraItems,
        "Comments": SelectedComments,
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/UpdateItem",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            CategoryLock = true;
            GetItems($('#ddCategory').val());
        }
    });

}
function DeleteItem() {

    var value = {
        "ID": $('#txtItemID').val(),
    };

    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteItem",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            alert(result.Message);
            CategoryLock = true;
            GetItems($('#ddCategory').val());
        }
    });

}
//this btnClearItem was created to avoid grid clearance upon selecting Category and loading item;
function btnClearItem() {
    CategoryLock = true;
    var myTableDiv = document.getElementById("ItemsTable");
    t = "";

    $("#ItemsTable").html(myTableDiv);
    $("#ddCategory").jqxDropDownList({ selectedIndex: -1 });

    $("#ddBranchs").jqxDropDownList({ selectedIndex: -1 });
    $("#btnUpdateItem").hide("slow");
    $("#btnDeleteItem").hide("slow");
    $("#btnAddItem").show("slow");
    debugger;
    if (dataAdapterBrandList != undefined) {
        if (dataAdapterBrandList.totalrecords == 1) {
            $("#ddBrands").val(1);
        }
        else {
            $("#ddBrands").jqxDropDownList({ selectedIndex: -1 });
        }
    }
    else {
        $("#ddBrands").jqxDropDownList({ selectedIndex: -1 });
    }
    ClearItem();

}
function ClearItem() {
    $('tr').removeClass('high-light');
    $('#lblFileName').text("");
    $("input[type=text]").val('');
    $("textarea").val("");
    var p = "../../images/no_image.png";
    var t;
    $("#Image").val('');
    t = "<div> <img src=" + p + "  width='87' height='58'/>  </div>";

    $("#img").html(t);
    $("#ddBranchs").jqxDropDownList('uncheckAll');

    debugger;
    $("#chkIsExtraItems").prop("checked", false);
    nonExtraItemsControlsHideshow();
    debugger;
    if ($('#ddCategory').val() > 0) {
        BindExtraItesmDdr($('#ddCategory').val());
    }
    else {
        $('#ddExtraItems').jqxDropDownList({
            selectedIndex: -1,
            //searchmode: 'contains',
            //placeHolder: 'All',
            source: null,
            displayMember: "ITEM_NAME",
            checkboxes: true,
            valueMember: "ID",
            width: 270,
            height: 25,
        });
    }
    //$("#trExtraItemsAndComments").hide();
    //$("#ddExtraItems").jqxDropDownList('uncheckAll');
    $("#ddExtraComments").jqxDropDownList('uncheckAll');
}
//-------------------------------------Image Slide SHows Details-------------------------------------
function CreateImageSequenceTable(BrandID) {
    if (BrandID == "") {
        alert("Please Select Brand");
        return;
    }
    var Data;
    var obj = { brandID: BrandID }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obj),
        url: "/mobile/GetImageSlideShow",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            Data = result.dtItems;

            var myTableDiv = document.getElementById("SlideShowsTable");
            t = "";

            $("#SlideShowsTable").html(myTableDiv);
            var table = document.createElement('TABLE');
            table.border = '1';
            table.classList.add("DragDropCategory");
            table.id = "tblSlideShows"
            table.className = "DragDropCategory";
            var tableBody = document.createElement('TBODY');
            table.appendChild(tableBody);

            var thead = document.createElement('thead');

            table.appendChild(thead);
            thead.appendChild(document.createElement("th"));

            var orderArrayHeader = ["Image Name", "Delete"];

            for (var i = 0; i < orderArrayHeader.length; i++) {
                thead.appendChild(document.createElement("th")).
                    appendChild(document.createTextNode(orderArrayHeader[i]));
            }


            for (var i = 0; i < Data.length; i++) {
                var tr = document.createElement('TR');
                tableBody.appendChild(tr);

                var Drag = document.createElement('TD');
                Drag.appendChild(document.createTextNode(""));
                Drag.classList.add("sorter");
                tr.appendChild(Drag);

                var IMAGENAME = document.createElement('TD');
                IMAGENAME.appendChild(document.createTextNode(Data[i].IMAGENAME));
                tr.appendChild(IMAGENAME);
                tr.dataset.IMAGENAME = Data[i].IMAGENAME;
                tr.dataset.ImageId = Data[i].ID;

                var Delete = document.createElement('TD');
                var btn = document.createElement('input');
                btn.type = "button";
                btn.value = "Delete Image";
                btn.id = Data[i].ID;
                btn.onclick = (function () {
                    var txt;
                    var r = confirm("Are you sure you want to Delete the Image!");
                    if (r == true) {
                        var Imageid = this.id;

                        var value = {
                            "CAT_NUM": Imageid,
                        };

                        //            var obj = JSON.stringify(value);
                        $.ajax({
                            type: "GET",
                            url: "/Items/DelteSlideShow",
                            contentType: 'application/json',
                            data: value,
                            success: function (result) {
                                CreateImageSequenceTable(BrandID);
                            }
                        });

                    } else {

                    }
                    document.getElementById("demo").innerHTML = txt;


                })
                Delete.appendChild(btn);
                tr.appendChild(Delete);


                tr.onclick = function () {
                    $('tr').removeClass('high-light');
                    $(this).addClass("high-light");
                    CreateSlideShowImage("#imgSlideShows", this.dataset.IMAGENAME);
                };
            }
            myTableDiv.appendChild(table);

            RowSorter(gebi('tblSlideShows'), {
                handler: 'td.sorter',
                onDrop: function (tbody, row, new_index, old_index) {
                    var table = tbody.nodeName === 'TBODY' ? tbody.parentNode : tbody;
                    var value = [];

                    for (var i = 0; i < tbody.childNodes.length; i++) {
                        value[i] = {
                            "CAT_NUM": tbody.childNodes[i].dataset.ImageId,
                            "SEQ_NUM": tbody.childNodes[i].rowIndex,
                        };
                    }
                    var obji = { value: value }
                    $.ajax({
                        type: "POST",
                        url: "/items/updateSlideShowSequence",
                        data: JSON.stringify(obji),
                        contentType: "application/json; charset=utf-8",
                        dataType: "json",
                        success: function (result) {
                            CreateImageSequenceTable(BrandID);
                        }
                    });
                }
            });
            //end of Ajax Call
        }

    });
}
function CreateWebSlideShowTable(BrandID) {
    debugger;
    if (BrandID == "") {
        alert("Please Select Brand");
        return;
    }
    var Data;
    var obji = { brandID: BrandID }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obji),
        url: "/mobile/GetWebImageSlideShow",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            Data = result.dtItems;

            var myTableDiv = document.getElementById("WebSlideShowsTable");
            t = "";

            $("#WebSlideShowsTable").html(myTableDiv);
            var table = document.createElement('TABLE');
            table.border = '1';
            table.classList.add("DragDropCategory");
            table.id = "tblWebSlideShows"
            table.className = "DragDropCategory";
            var tableBody = document.createElement('TBODY');
            table.appendChild(tableBody);

            var thead = document.createElement('thead');

            table.appendChild(thead);
            thead.appendChild(document.createElement("th"));

            var orderArrayHeader = ["Image Name", "Delete"];

            for (var i = 0; i < orderArrayHeader.length; i++) {
                thead.appendChild(document.createElement("th")).
                    appendChild(document.createTextNode(orderArrayHeader[i]));
            }


            for (var i = 0; i < Data.length; i++) {
                var tr = document.createElement('TR');
                tableBody.appendChild(tr);

                var Drag = document.createElement('TD');
                Drag.appendChild(document.createTextNode(""));
                Drag.classList.add("sorter");
                tr.appendChild(Drag);

                var IMAGENAME = document.createElement('TD');
                IMAGENAME.appendChild(document.createTextNode(Data[i].IMAGENAME));
                tr.appendChild(IMAGENAME);
                tr.dataset.IMAGENAME = Data[i].IMAGENAME;
                tr.dataset.ImageId = Data[i].ID;

                var Delete = document.createElement('TD');
                var btn = document.createElement('input');
                btn.type = "button";
                btn.value = "Delete Image";
                btn.id = Data[i].ID;
                btn.onclick = (function () {
                    var txt;
                    var r = confirm("Are you sure you want to Delete the Image!");
                    if (r == true) {
                        var Imageid = this.id;

                        var value = {
                            "CAT_NUM": Imageid,
                        };

                        //            var obj = JSON.stringify(value);
                        $.ajax({
                            type: "GET",
                            url: "/Items/DelteWebSlideShow",
                            contentType: 'application/json',
                            data: value,
                            success: function (result) {
                                CreateWebSlideShowTable(BrandID);
                            }
                        });

                    } else {

                    }
                    document.getElementById("demo").innerHTML = txt;


                })
                Delete.appendChild(btn);
                tr.appendChild(Delete);


                tr.onclick = function () {
                    $('tr').removeClass('high-light');
                    $(this).addClass("high-light");
                    CreateSlideShowImage("#imgSlideShows", this.dataset.IMAGENAME);
                };
            }
            myTableDiv.appendChild(table);

            RowSorter(gebi('tblWebSlideShows'), {
                handler: 'td.sorter',
                onDrop: function (tbody, row, new_index, old_index) {
                    debugger;
                    var table = tbody.nodeName === 'TBODY' ? tbody.parentNode : tbody;
                    var value = [];

                    for (var i = 0; i < tbody.childNodes.length; i++) {
                        value[i] = {
                            "CAT_NUM": tbody.childNodes[i].dataset.ImageId,
                            "SEQ_NUM": tbody.childNodes[i].rowIndex,
                        };
                    }
                    var obji = { value: value }
                    $.ajax({
                        type: "POST",
                        url: "/items/updateWebSlideShowSequence",
                        data: JSON.stringify(obji),
                        contentType: "application/json; charset=utf-8",
                        dataType: "json",
                        success: function (result) {
                            CreateWebSlideShowTable(BrandID);
                        }
                    });
                }
            });
            //end of Ajax Call
        }

    });
}
function CreateImage(imageid, image) {
    try {
        var p = "../../images/" + image;
        var t;
        t = "<div> <img src=" + p + "  width='87' height='58' />  </div>";
        $(imageid).html(t);
    } catch (err) {
    }

}
function CreateSlideShowImage(imageid, image) {
    try {
        var p = "../../images/" + image;
        var t;
        t = "<div> <img src=" + p + "  width='400' height='250' />  </div>";
        $(imageid).html(t);
    } catch (err) {
    }

}

//-------------------------------------Image Promotion Details-------------------------------------
function CreateImagePromotionTable(BrandID) {
    if (BrandID == "") {
        alert("Please Select Brand");
        return;
    }
    var Data;
    var obj = { brandID: BrandID }
    $.ajax({
        type: "POST",
        cache: false,
        data: JSON.stringify(obj),
        url: "/mobile/GetImagePromotion",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            var IsShowPromotion = result.IsShowPromotion;
            if (IsShowPromotion == 1) {
                $('#chkIsBrandPromotionShow').prop('checked', true);
            }
            else {
                $('#chkIsBrandPromotionShow').prop('checked', false);
            }

            Data = result.dtItems;

            var myTableDiv = document.getElementById("PromotionTable");
            t = "";

            $("#PromotionTable").html(myTableDiv);
            var table = document.createElement('TABLE');
            table.border = '1';
            table.classList.add("DragDropCategory");
            table.id = "tblPromotion"
            table.className = "DragDropCategory";
            var tableBody = document.createElement('TBODY');
            table.appendChild(tableBody);

            var thead = document.createElement('thead');

            table.appendChild(thead);
            thead.appendChild(document.createElement("th"));

            var orderArrayHeader = ["Image Name", "Delete"];

            for (var i = 0; i < orderArrayHeader.length; i++) {
                thead.appendChild(document.createElement("th")).
                    appendChild(document.createTextNode(orderArrayHeader[i]));
            }


            for (var i = 0; i < Data.length; i++) {
                var tr = document.createElement('TR');
                tableBody.appendChild(tr);

                var Drag = document.createElement('TD');
                Drag.appendChild(document.createTextNode(""));
                Drag.classList.add("sorter");
                tr.appendChild(Drag);

                var IMAGENAME = document.createElement('TD');
                IMAGENAME.appendChild(document.createTextNode(Data[i].IMAGENAME));
                tr.appendChild(IMAGENAME);
                tr.dataset.IMAGENAME = Data[i].IMAGENAME;
                tr.dataset.ImageId = Data[i].ID;

                var Delete = document.createElement('TD');
                var btn = document.createElement('input');
                btn.type = "button";
                btn.value = "Delete Image";
                btn.id = Data[i].ID;
                btn.onclick = (function () {
                    var txt;
                    var r = confirm("Are you sure you want to Delete the Image!");
                    if (r == true) {
                        var Imageid = this.id;

                        var value = {
                            "CAT_NUM": Imageid,
                        };

                        //            var obj = JSON.stringify(value);
                        $.ajax({
                            type: "GET",
                            url: "/Items/DeltePromotion",
                            contentType: 'application/json',
                            data: value,
                            success: function (result) {
                                CreateImagePromotionTable(BrandID);
                            }
                        });

                    } else {

                    }
                    document.getElementById("demo").innerHTML = txt;


                })
                Delete.appendChild(btn);
                tr.appendChild(Delete);


                tr.onclick = function () {
                    $('tr').removeClass('high-light');
                    $(this).addClass("high-light");
                    CreateSlideShowImage("#imgPromotion", this.dataset.IMAGENAME);
                };
            }
            myTableDiv.appendChild(table);

            RowSorter(gebi('tblPromotion'), {
                handler: 'td.sorter',
                onDrop: function (tbody, row, new_index, old_index) {
                    var table = tbody.nodeName === 'TBODY' ? tbody.parentNode : tbody;
                    var value = [];

                    for (var i = 0; i < tbody.childNodes.length; i++) {
                        value[i] = {
                            "CAT_NUM": tbody.childNodes[i].dataset.ImageId,
                            "SEQ_NUM": tbody.childNodes[i].rowIndex,
                        };
                    }
                    var obji = { value: value }
                    $.ajax({
                        type: "POST",
                        url: "/items/updatePromotionSequence",
                        data: JSON.stringify(obji),
                        contentType: "application/json; charset=utf-8",
                        dataType: "json",
                        success: function (result) {
                            CreateImagePromotionTable(BrandID);
                        }
                    });
                }
            });
            //end of Ajax Call
        }

    });
}


//-------------------------------------Category Details-------------------------------------

function GetCategory() {
    ClearCategory();
    $.ajax({
        type: "POST",
        cache: false,
        url: "/Items/Category",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            Category = result.dtCategory;
            FillCategory(Category);

        }
    });
}
function FillddCategory(Category) {


    var Category =
    {
        dataType: "json",
        dataFields: [
            { name: 'CAT_NUM', type: 'number' },
            { name: 'CAT_NAME', type: 'string' }
        ],

        id: 'CAT_NUM',
        localdata: Category
    };


    DataAdapterCategory = new $.jqx.dataAdapter(Category);


    $("#ddCategory").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'Select Category',
        source: DataAdapterCategory,
        displayMember: "CAT_NAME",
        valueMember: "CAT_NUM",
        width: 270,
        height: 22
    });
    // subscribe to the select event.

}
function OpenCategory() {

    $("#Window").jqxWindow('open');

}
function gebi(id) {
    return document.getElementById(id);
}
function CreateTable(id, Data, Columns) {

    var myTableDiv = document.getElementById("CategoryTable");
    t = "";

    $("#CategoryTable").html(myTableDiv);
    var table = document.createElement('TABLE');
    table.border = '1';
    table.classList.add("DragDropCategory");
    table.id = "tbldragdropCategory"
    table.className = "DragDropCategory";
    var tableBody = document.createElement('TBODY');
    table.appendChild(tableBody);

    var thead = document.createElement('thead');

    table.appendChild(thead);
    thead.appendChild(document.createElement("th"));

    var orderArrayHeader = ["Category Name", "Category Name Arabic", "Brand Name", "ShowInTablet"];

    for (var i = 0; i < orderArrayHeader.length; i++) {
        thead.appendChild(document.createElement("th")).
            appendChild(document.createTextNode(orderArrayHeader[i]));
    }


    for (var i = 0; i < Data.length; i++) {
        var tr = document.createElement('TR');
        tableBody.appendChild(tr);

        var Drag = document.createElement('TD');
        Drag.appendChild(document.createTextNode(""));
        Drag.classList.add("sorter");
        tr.appendChild(Drag);

        var CAT_NAME = document.createElement('TD');
        CAT_NAME.appendChild(document.createTextNode(Data[i].CAT_NAME));
        tr.appendChild(CAT_NAME);

        var CAT_NAME_ARABIC = document.createElement('TD');
        CAT_NAME_ARABIC.appendChild(document.createTextNode(Data[i].CAT_NAME_ARABIC));
        tr.appendChild(CAT_NAME_ARABIC);

        var CAT_BrandName = document.createElement('TD');
        CAT_BrandName.appendChild(document.createTextNode(Data[i].BrandName));
        tr.appendChild(CAT_BrandName);

        var ShowInTablet = document.createElement('TD');
        ShowInTablet.appendChild(document.createTextNode(Data[i].ShowInTablet));
        tr.appendChild(ShowInTablet);

        var MainCategory = document.createElement('TD');
        MainCategory.appendChild(document.createTextNode(Data[i].MainCategory));
        MainCategory.classList.add("invisible");
        tr.appendChild(MainCategory);

        var BrandID = document.createElement('TD');
        BrandID.appendChild(document.createTextNode(Data[i].BrandID));
        BrandID.classList.add("invisible");
        tr.appendChild(BrandID);

        var CAT_NUM = document.createElement('TD');
        CAT_NUM.appendChild(document.createTextNode(Data[i].CAT_NUM));
        CAT_NUM.classList.add("invisible");
        tr.appendChild(CAT_NUM);

        tr.dataset.ShowInTablet = Data[i].ShowInTablet;
        tr.dataset.BrandID = Data[i].BrandID;
        tr.dataset.MainCategory = Data[i].MainCategory;
        tr.dataset.CAT_NAME_ARABIC = Data[i].CAT_NAME_ARABIC;
        tr.dataset.CAT_NAME = Data[i].CAT_NAME;
        tr.dataset.CAT_NUM = Data[i].CAT_NUM;
        tr.onclick = function () {
            $('tr').removeClass('high-light');
            $(this).addClass("high-light");
            SetupCategoryText(this);
        };
    }
    myTableDiv.appendChild(table);

    RowSorter(gebi('tbldragdropCategory'), {
        handler: 'td.sorter',
        onDrop: function (tbody, row, new_index, old_index) {
            var table = tbody.nodeName === 'TBODY' ? tbody.parentNode : tbody;
            var value = [];

            for (var i = 0; i < tbody.childNodes.length; i++) {
                value[i] = {
                    "CAT_NUM": tbody.childNodes[i].dataset.CAT_NUM,
                    "SEQ_NUM": tbody.childNodes[i].rowIndex,
                };
            }
            var obji = { value: value }
            $.ajax({
                type: "POST",
                url: "/items/updateCategorySequence",
                data: JSON.stringify(obji),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function (result) {
                    GetCategory();
                }
            });
        }
    });
}
function SetupCategoryText(item) {

    var row = item.dataset;

    $("#btnUpdateCategory").show("slow");
    $("#btnDeleteCategory").show("slow");
    $("#btnAddCategory").hide("slow");
    $("#ddBrands2").jqxDropDownList('uncheckAll');

    /*var value = {
        "CAT_NUM": row.CAT_NUM,
    };
    $.ajax({
        type: "POST",
        cache: false,
        async: false,
        url: "/items/GetAssignedBrand",
        data: value,
        success: function (result) {
            var BrandiD = result.dtBrand;
            $.each(BrandiD, function (key, val1) {
                $("#ddBrands2").jqxDropDownList('checkItem', val1.BrandID);

            });
        }
    });*/
    //$("#ddBranchsCategoryView").val(0);
    //$("#ddBranchsCategoryView").jqxListBox('uncheckAll');
    $("#ddBranchsCategoryView").jqxDropDownList('uncheckAll');
    var value = {
        "CAT_NUM": row.CAT_NUM,
    };
    $.ajax({
        type: "POST",
        cache: false,
        async: false,
        url: "/items/GetAssignedBranch",
        data: value,
        success: function (result) {
            var BrandiD = result.dtBrand;
            $.each(BrandiD, function (key, val1) {
                $("#ddBranchsCategoryView").jqxDropDownList('checkItem', val1.BranchId);
            });
        }
    });
    debugger;
    $("#ddBrands2").val(row.BrandID);

    $('#txtCategoryNo').val(row.CAT_NUM);
    $('#txtCategoryName').val(row.CAT_NAME);
    $("#txtCategoryNameAra").val(row.CAT_NAME_ARABIC);
    $("#txtPrinter").val(row.ShowInTablet);
    $("#txtSeqNo").val(row.SEQ_NUM);

    debugger;
    if (row.ShowInTablet == "true") {
        $('input[name=isImage][value=true]').prop('checked', true);
    } else {
        $('input[name=isImage][value=false]').prop("checked", true)
    }

    if (row.MainCategory == 0) {
        hideMainCategory();
        $('input[name=isSubCategory][value=true]').prop('checked', true);
    } else {
        ShowMainCategory();
        $('#ddMainCategory').val(row.MainCategory);
        $('input[name=isSubCategory][value=false]').prop("checked", true)

    }
}
function FillCategory(CategoryData) {
    var Category =
    {
        dataType: "json",
        dataFields: [
            { name: 'CAT_NUM', type: 'int' },
            { name: 'BrandID', type: 'int' },
            { name: 'BrandName', type: 'string' },
            { name: 'CAT_NAME', type: 'string' },
            { name: 'CAT_NAME_ARABIC', type: 'string' },
            { name: 'CatNameRus', type: 'string' },
            { name: 'CatNameMan', type: 'string' },
            { name: 'ShowInTablet', type: 'string' },
            { name: 'SEQ_NUM', type: 'number' },
            { name: 'MainCategory', type: 'number' },
        ],

        id: 'CAT_NUM',
        localdata: CategoryData
    };

    CreateTable("tbldragdropCategory", CategoryData, 7)



    var dataAdapterCategory = new $.jqx.dataAdapter(Category);
    $("#ddCategory,#ddMainCategory").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'Select Category',
        source: dataAdapterCategory,
        displayMember: "CAT_NAME",
        valueMember: "CAT_NUM",
        width: 270,
        height: 22
    });
    //$("#grdCategory").on('rowselect', function (event) {
    $("#ddCategory").on('select', function (event) {
        if (event.args) {
            var item = event.args.item;
            if (item) {
                if (CategoryLock) {
                    var valueelement = $("<div></div>");
                    valueelement.text("Value: " + item.value);
                    GetItems(item.value);
                    var labelelement = $("<div></div>");
                    labelelement.text("Label: " + item.label);
                    $("#selectionlog").children().remove();
                    $("#selectionlog").append(labelelement);
                    $("#selectionlog").append(valueelement);
                    BindExtraItesmDdr(item.value);
                }
            }

        }
    });
}
function AddCategory() {

    debugger
    if ($("#ddBrands2").val() == '') {

        $("#ddBrands2").notify('Please Select Brand', { position: "right" });
        return;
    }
    var Package = $("#ddBranchsCategoryView").jqxDropDownList('getCheckedItems');
    var PackageData = new Array();
    if (Package != undefined) {
        if (Package.length > 0) {
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i].value;
                PackageData[i] = { "BranchId": RowData };
            }
        }
        else {
            Package = $("#ddBranchsCategoryView").jqxDropDownList('getItems');
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i].value;
                PackageData[i] = { "BranchId": RowData };
            }
        }
        /*for (var i = 0; i < Package.length; i++) {
            var RowData = Package[i].value;
            PackageData[i] = { "BrandID": RowData };

        }*/
    } else {
        $("#ddBranchsCategoryView").notify('Please Select branch', { position: "right" });
        return;
    }

    if ($('#txtCategoryName').val() == "") {
        $("#txtCategoryName").notify('Please insert Category Name', { position: "right" });
        return;
    }
    // initially it is aasume that for main category the value for MainCateogry in DB is = so  MainCategory=0 
    // if it is sub category then the value of main category for this sub category is taken from ddMainCategory 
    var MainCategory = 0;
    var isSubCategory = $("input[name=isSubCategory]:checked").val()
    if (isSubCategory) {
        MainCategory = $('#ddMainCategory').val()
    }

    var value = {
        "CAT_NAME": $('#txtCategoryName').val(),
        "BrandID": $('#ddBrands2').val(),
        "BranchData": PackageData,
        "CAT_NAME_ARABIC": $("#txtCategoryNameAra").val(),
        "CatNameMan": $("#txtCategoryNameMan").val(),
        "CatNameRus": $("#txtCategoryNameRus").val(),
        "ShowInTablet": $("input[name=isImage]:checked").val(),
        "SEQ_NUM": $("#txtSeqNo").val(),
        "MainCategory": MainCategory
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddCategory",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            ClearCategory();
            GetCategory();
            GetddCategory()
        }
    });

}
function UpdateCategory() {
    if ($("#ddBrands2").val() == '') {

        $("#ddBrands2").notify('Please Select Brand', { position: "right" });
        return;
    }
    var Package = $("#ddBranchsCategoryView").jqxDropDownList('getCheckedItems');
    var PackageData = new Array();
    if (Package != undefined) {
        if (Package.length > 0) {
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i].value;
                PackageData[i] = { "BranchId": RowData };
            }
        }
        else {
            Package = $("#ddBranchsCategoryView").jqxDropDownList('getItems');
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i].value;
                PackageData[i] = { "BranchId": RowData };
            }
        }
        /*for (var i = 0; i < Package.length; i++) {
            var RowData = Package[i].value;
            PackageData[i] = { "BrandID": RowData };

        }*/
    } else {
        $("#ddBranchsCategoryView").notify('Please Select branch', { position: "right" });
        return;
    }

    var MainCategory = 0;
    var isSubCategory = $("input[name=isSubCategory]:checked").val()
    if (isSubCategory) {
        MainCategory = $('#ddMainCategory').val()
    }

    var value = {
        "CAT_NUM": $('#txtCategoryNo').val(),
        "BrandID": $('#ddBrands2').val(),
        "BranchData": PackageData,
        "CAT_NAME": $('#txtCategoryName').val(),
        "CAT_NAME_ARABIC": $("#txtCategoryNameAra").val(),
        "CatNameMan": $("#txtCategoryNameMan").val(),
        "CatNameRus": $("#txtCategoryNameRus").val(),
        "ShowInTablet": $("input[name=isImage]:checked").val(),
        "SEQ_NUM": $("#txtSeqNo").val(),
        "MainCategory": MainCategory
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/UpdateCategory",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            ClearCategory();
            GetCategory();

        }
    });

}
function DeleteCategory() {

    var value = {
        "CAT_NUM": $('#txtCategoryNo').val(),
    };

    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteCategory",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            alert(result.Message);
            ClearCategory();
            GetCategory();

        }
    });

}
function ClearCategory() {
    hideMainCategory();
    //$("#ddBrands2").jqxDropDownList('uncheckAll');
    // $("#grdCategory").jqxGrid('clearselection');
    $("#btnUpdateCategory").hide("slow");
    $("#btnDeleteCategory").hide("slow");
    $("#btnAddCategory").show("slow");
    debugger;
    if (dataAdapterBrandList != undefined) {
        if (dataAdapterBrandList.totalrecords == 1) {
            $("#ddBrands2").val(1);
        }
        else {
            $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
        }
    }
    else {
        $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
    }
    $("#ddBranchsCategoryView").jqxDropDownList('uncheckAll');
    $("input[type=text]").val('');
}
function ShowMainCategory() {
    $("#mainCatDisplay").show();
}
function hideMainCategory() {
    $("#mainCatDisplay").hide();
    $("#ddMainCategory").jqxDropDownList({ selectedIndex: -1 });
    $('input[name=isSubCategory][value=true]').prop('checked', true);
}


//------------------------------------Branch details ----------------------------------
function BindBranchs(BrandId, obj) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: { brandid: BrandId },
        url: "/Items/GetBranchsBrandWise",
        success: function (result) {
            var Branchs = result.dtgrdBranch;
            FillBranchsBrandWise(Branchs, obj);
        }
    });
}
function FillBranchsBrandWise(Branchs, obj) {
    var Branchs =
    {
        dataType: "json",
        dataFields: [
            { name: 'BranchId', type: 'number' },
            { name: 'branchName', type: 'string' },
        ],

        id: 'BranchId',
        localdata: Branchs
    };


    var dataAdapterBranchs = new $.jqx.dataAdapter(Branchs);
    debugger;
    //"#ddBranchs,#dropdownlistWrapperddBranchsCopy"
    if (obj == "#ddBranchsCopy" || obj == "#ddGenerateQrBranchList") {
        $(obj).jqxDropDownList({
            selectedIndex: -1,
            placeHolder: 'select Branch',
            source: dataAdapterBranchs,
            displayMember: "branchName",
            //checkboxes: true,
            valueMember: "BranchId",
            width: 270,
            height: 25,
        });
    }
    else {
        $(obj).jqxDropDownList({
            selectedIndex: -1,
            placeHolder: 'All',
            source: dataAdapterBranchs,
            displayMember: "branchName",
            checkboxes: true,
            valueMember: "BranchId",
            width: 270,
            height: 25,
        });
    }
}


//-------------------------------------Brand Details-------------------------------------
function GetBrands() {
    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetBrands",
        success: function (result) {
            var Brands = result.dtgrdBrand;
            FillBrands(Brands);
            debugger;
            // var aaa=dataAdapterBrandList;
            if (dataAdapterBrandList != undefined) {
                if (dataAdapterBrandList.totalrecords == 1) {
                    /*$("#ddBrands").val(1);
                    $("#ddBrands2").val(1);
                    $("#ddBrandsAddBranchPopup").val(1);*/

                    $("#ddBrands").jqxDropDownList({ selectedIndex: 0 });
                    $("#ddGenerateQrBrands").jqxDropDownList({ selectedIndex: 0 });
                    $("#ddBrands2").jqxDropDownList({ selectedIndex: 0 });
                    $("#ddBrandsAddBranchPopup").jqxDropDownList({ selectedIndex: 0 });
                }
                else {
                    $("#ddBrands").jqxDropDownList({ selectedIndex: -1 });
                    $("#ddGenerateQrBrands").jqxDropDownList({ selectedIndex: -1 });
                    $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
                    $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
                }
            }
            else {
                $("#ddBrands").jqxDropDownList({ selectedIndex: -1 });
                $("#ddGenerateQrBrands").jqxDropDownList({ selectedIndex: -1 });
                $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
                $("#ddBrands2").jqxDropDownList({ selectedIndex: -1 });
            }
        }
    });

}
function FillBrands(Brands) {

    var Brands =
    {
        dataType: "json",
        dataFields: [
            { name: 'BrandID', type: 'number' },
            { name: 'BrandName', type: 'string' },
        ],

        id: 'BrandID',
        localdata: Brands
    };

    debugger;
    dataAdapterBrandList = new $.jqx.dataAdapter(Brands);

    $("#ddBrands,#ddGenerateQrBrands,#ddBrandsAddBranchPopup,#ddBrands2,#ddBrandsLayout,#ddBrandsThemes,#ddWebSlideShowBrand,#ddSlideShowBrand,#ddPromtionBrand").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'Select Brands',
        source: dataAdapterBrandList,
        displayMember: "BrandName",
        valueMember: "BrandID",
        width: 270,
        height: 25
    });
    $("#ddBrands").on('change', function (event) {
        debugger;
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;

            // get item's label and value.
            //var label = item.label;
            //var value = item.value;
            if (item != null) {
                BindBranchs(item.value, "#ddBranchs");
            }
            //var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });
    $("#ddGenerateQrBrands").on('change', function (event) {
        debugger;
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;

            // get item's label and value.
            //var label = item.label;
            //var value = item.value;
            if (item != null) {
                BindBranchs(item.value, "#ddGenerateQrBranchList");
            }
            //var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });
    $("#ddBrandsAddBranchPopup").on('change', function (event) {
        debugger;
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;

            // get item's label and value.
            //var label = item.label;
            //var value = item.value;
            if (item != null) {
                BindBranchs(item.value, "#ddBranchsCopy");
            }
            //var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });
    $("#ddBrands2").on('change', function (event) {
        debugger;
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;

            // get item's label and value.
            //var label = item.label;
            //var value = item.value;
            if (item != null) {
                BindBranchs(item.value, "#ddBranchsCategoryView");
            }
            //var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });
    $('#ddWebSlideShowBrand').on('change', function (event) {
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;
            $('#jqxWebSlideShows').jqxFileUpload({ uploadUrl: '/Items/UploadSlideShowImages?isMobile=false&BrandID=' + item.value });
            //$('#jqxWebSlideShows').jqxFileUpload({ uploadUrl: 'upload.php' });

            // get item's label and value.
            var label = item.label;
            var value = item.value;
            CreateWebSlideShowTable(item.value);
            var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });


    $('#ddSlideShowBrand').on('change', function (event) {
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;
            // get item's label and value.
            $('#jqxSlideShows').jqxFileUpload({ uploadUrl: '/Items/UploadSlideShowImages?isMobile=true&BrandID=' + item.value });
            var label = item.label;
            CreateImageSequenceTable(item.value)

            var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });

    $('#ddPromtionBrand').on('change', function (event) {
        var args = event.args;
        if (args) {
            // index represents the item's index.                      
            var index = args.index;
            var item = args.item;
            // get item's label and value.
            $('#jqxPromotion').jqxFileUpload({ uploadUrl: '/Items/UploadPromotionImages?isMobile=true&BrandID=' + item.value });
            var label = item.label;
            CreateImagePromotionTable(item.value)

            var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });

    /*$("#ddBrands2").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'All',
        source: dataAdapterBrandList,
        displayMember: "BrandName",
        checkboxes: true,
        valueMember: "BrandID",
        width: 270,
        height: 25
    });*/


    $("#ddBrands3").jqxListBox({
        source: dataAdapterBrandList,
        displayMember: "BrandName",
        valueMember: "BrandID",
        multiple: true,
        checkboxes: true,
        width: 200,
        height: 150
    });




}

//-------------------------------------Brand-------------------------------------
function OpenBrand() {
    ClearBrand();
    $("#WinBrand").jqxWindow('open');
    $("#btnUpdateBrand").hide();
    $("#btnDeleteBrand").hide();
    EditBrandDetails();

}
function EditBrandDetails() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetBrands",
        success: function (result) {
            var grdBrand = result.dtgrdBrand;
            var Brand =
            {
                dataType: "json",
                dataFields: [
                    { name: 'BrandID', type: 'number' },
                    { name: 'ThemeID', type: 'number' },
                    { name: 'BrandName', type: 'string' },
                    { name: 'BrandLogo', type: 'string' },
                    { name: 'ThemeName', type: 'string' },
                    { name: 'BrandNameAr', type: 'string' },
                    { name: 'BrandSeq', type: 'number' },
                    { name: 'Russian', type: 'number' },
                    { name: 'Mandarin', type: 'number' },
                    { name: 'BrandUrl', type: 'string' },
                ],
                id: 'BrandID',
                localdata: grdBrand
            };


            var dataAdapterBrand = new $.jqx.dataAdapter(Brand);
            $("#grdBrand").jqxGrid({
                width: '100%',
                height: '315',
                source: dataAdapterBrand,
                theme: 'ui-redmond',
                pageSize: 10,
                pageable: true,
                sortable: true,
                showfilterrow: true,
                filterable: true,
                columnsresize: true,
                autoshowloadelement: false,
                selectionmode: 'singlerow',
                columns: [
                    { dataField: 'BrandID', text: 'ID', hidden: true },
                    { dataField: 'ThemeID', text: 'ThemeID', hidden: true },
                    { dataField: 'BrandName', text: 'Brand Name', width: '25%', hidden: true },
                    { dataField: 'BrandSeq', text: 'Brand Sequence', width: '25%', },
                    { dataField: 'BrandNameAr', text: 'Brand Name(Arabic)', width: '25%' },
                    { dataField: 'ThemeName', text: 'Brand Name', width: '25%', },
                    { dataField: 'BrandUrl', text: 'Brand Url', width: '25%', },
                    { dataField: 'Russian', text: 'Russian', hidden: true },
                    { dataField: 'BrandLogo', text: 'Brand Logo', hidden: true },
                    { dataField: 'Mandarin', text: 'Mandarin', hidden: true },
                ]

            });
            $("#grdBrand").on('rowselect', function (event) {
                //$("#copyBrandtr").hide("slow");

                $('input:checkbox').removeAttr('checked');
                $("#btnUpdateBrand").show("slow");
                $("#btnDeleteBrand").show("slow");
                $("#btnAddBrand").hide("slow");
                var getselectedrowindexes = event.args.rowindex;
                var row = $("#grdBrand").jqxGrid('getrowdata', getselectedrowindexes);
                $("#ddTheme").val(row.ThemeID),
                    $('#BrandID').val(row.BrandID);
                $('#txtBrandName').val(row.BrandName);
                $('#txtBrandNameAr').val(row.BrandNameAr);
                $('#txtBrandSeq').val(row.BrandSeq);
                $('#txtBrandurl').val(row.BrandUrl);
                $('#lblFileNameBrand').html(row.BrandLogo);
                var p = "../../images/" + row.BrandLogo;
                var t;

                t = "<div> <img src=" + p + "  width='87' height='58'  />  </div>";

                $("#imgBrand").html(t);

                if (row.Russian == 1) {
                    document.getElementById("chkRussian").checked = "true";
                }
                if (row.Mandarin == 1) {
                    document.getElementById("chkMandarin").checked = "true";
                }
            });
        }
    });
}
function AddBrand() {
    debugger;
    var Russian = 0;
    var Mandarin = 0;

    if ($("#txtBrandName").val() == '') {

        $("#txtBrandName").notify('Please insert Brand Name', { position: "right" });
        return;
    }

    if ($("#ddTheme").val() == '') {

        $("#ddTheme").notify('Please Select Theme', { position: "right" });
        return;
    }
    if ($("#txtBrandurl").val() == '') {

        $("#txtBrandurl").notify('Please Select url', { position: "right" });
        return;
    }
    if (document.getElementById('chkRussian').checked)
        Russian = 1;
    if (document.getElementById('chkMandarin').checked)
        Mandarin = 1;

    var value = {
        "BrandID": $('#BrandID').val(),
        "BrandName": $("#txtBrandName").val(),
        "BrandNameAr": $("#txtBrandNameAr").val(),
        "BrandLogo": $('#lblFileNameBrand').text(),
        "BrandSeq": $("#txtBrandSeq").val(),
        "Russian": Russian,
        "ThemeID": $("#ddTheme").val(),
        "Mandarin": Mandarin,
        "Brandurl": $("#txtBrandurl").val(),
        //"CopyBrandID":$("#ddBrandsCopy").val(),
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddBrand",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            EditBrandDetails();
            GetBrands();
            ClearBrand();
        }
    });
}
function UpdateBrand() {
    if ($("#txtBrandName").val() == '') {

        $("#txtBrandName").notify('Please insert Brand Name', { position: "right" });
        return;
    }
    if ($("#ddTheme").val() == '') {

        $("#ddTheme").notify('Please Select Theme', { position: "right" });
        return;
    }
    var Russian = 0;
    var Mandarin = 0;
    if (document.getElementById('chkRussian').checked)
        Russian = 1;
    if (document.getElementById('chkMandarin').checked)
        Mandarin = 1;
    var value = {
        "BrandID": $('#BrandID').val(),
        "BrandName": $("#txtBrandName").val(),
        "BrandNameAr": $("#txtBrandNameAr").val(),
        "BrandLogo": $('#lblFileNameBrand').text(),
        "ThemeID": $("#ddTheme").val(),
        "Russian": Russian,
        "Mandarin": Mandarin,
        "Brandurl": $("#txtBrandurl").val(),
    };
    var obji = { value: value }
    $.ajax({
        type: "POST",
        url: "/Items/UpdateBrand",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            GetBrands();
            EditBrandDetails();
            ClearBrand();
        }
    });
}
function DeleteBrand() {
    var value = {
        "BrandID": $('#BrandID').val(),
    };
    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteBrand",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            alert(result.Message);
            EditBrandDetails();
            ClearBrand();
            GetBrands();
        }
    });
}
function ClearBrand() {
    $("#ddTheme").jqxDropDownList({ selectedIndex: -1 });
    $('input:checkbox').removeAttr('checked');
    $("input[type=text]").val('');
    $("#btnUpdateBrand").hide("slow");
    $("#btnDeleteBrand").hide("slow");
    $("#btnAddBrand").show("slow");
    var p = "../../images/no_image.png";
    var t;
    t = "<div> <img src=" + p + " width='87' height='58'/>  </div>";

    $("#imgBrand").html(t);
    //$("#copyBrandtr").show("slow");
    //$("#ddBrandsCopy").jqxDropDownList({ selectedIndex: -1 });
    $("#grdBrand").jqxGrid('clearselection');
}


//-------------------------------------Branch-------------------------------------
function OpenBranch() {
    ClearBranch();
    $("#WinBranch").jqxWindow('open');
    $("#btnUpdateBranch").hide();
    $("#btnDeleteBranch").hide();
    AddEditBranchDetails();

}
function AddEditBranchDetails() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetBranchsList",
        success: function (result) {
            var grdBranch = result.dtgrdBranch;
            var Branch =
            {
                dataType: "json",
                dataFields: [
                    { name: 'BranchId', type: 'number' },
                    { name: 'branchName', type: 'string' },
                    { name: 'BranchNameAra', type: 'string' },
                    { name: 'BrandID', type: 'string' },
                    { name: 'BrandName', type: 'string' },
                ],
                id: 'BranchId',
                localdata: grdBranch
            };


            var dataAdapterBranch = new $.jqx.dataAdapter(Branch);
            $("#grdBranch").jqxGrid({
                width: '100%',
                height: '315',
                source: dataAdapterBranch,
                theme: 'ui-redmond',
                pageSize: 10,
                pageable: true,
                sortable: true,
                showfilterrow: true,
                filterable: true,
                columnsresize: true,
                autoshowloadelement: false,
                selectionmode: 'singlerow',
                columns: [
                    { dataField: 'BranchId', text: 'BranchID', hidden: true },
                    { dataField: 'branchName', text: 'Branch Name', width: '25%' },
                    { dataField: 'BranchNameAra', text: 'Branch Name Ara', width: '25%', },
                    { dataField: 'BrandID', text: 'BrandID', hidden: true },
                    { dataField: 'BrandName', text: 'Brand Name', width: '25%' },
                ]

            });
            $("#grdBranch").on('rowselect', function (event) {
                $("#copyBranchtr").hide("slow");
                $("#btnUpdateBranch").show("slow");
                $("#btnDeleteBranch").show("slow");
                $("#btnAddBranch").hide("slow");
                var getselectedrowindexes = event.args.rowindex;
                var row = $("#grdBranch").jqxGrid('getrowdata', getselectedrowindexes);
                $('#ddBrandsAddBranchPopup').val(row.BrandID);
                $('#BranchID').val(row.BranchId);
                $('#txtBranchName').val(row.branchName);
                $('#txtBranchNameAr').val(row.BranchNameAra);
            });
        }
    });
}
function AddBranch() {

    if ($("#ddBrandsAddBranchPopup").val() == '') {

        $("#ddBrandsAddBranchPopup").notify('Please Select Brand', { position: "right" });
        return;
    }
    if ($("#txtBranchName").val() == '') {

        $("#txtBranchName").notify('Please insert Branch Name', { position: "right" });
        return;
    }
    var value = {
        "BranchID": $('#BranchID').val(),
        "BranchName": $("#txtBranchName").val(),
        "BranchNameAra": $("#txtBranchNameAr").val(),
        "CopyBranchID": $("#ddBranchsCopy").val(),
        "BrandID": $('#ddBrandsAddBranchPopup').val(),
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddBranch",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            AddEditBranchDetails();
            //GetBranchs();
            //BindBranchs($("#ddBrands"),"#ddBranchs");
            //BindBranchs($("#ddBrandsAddBranchPopup"),"#ddBranchsCopy");
            ClearBranch();
        }
    });
}
function UpdateBranch() {
    if ($("#txtBranchName").val() == '') {

        $("#txtBranchName").notify('Please insert Branch Name', { position: "right" });
        return;
    }
    var value = {
        "BranchID": $('#BranchID').val(),
        "BranchName": $("#txtBranchName").val(),
        "BranchNameAra": $("#txtBranchNameAr").val(),
        "CopyBranchID": $("#ddBranchsCopy").val(),
        "BrandID": $('#ddBrandsAddBranchPopup').val(),
    };
    var obji = { value: value }
    $.ajax({
        type: "POST",
        url: "/Items/UpdateBranch",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            //GetBranchs();
            //BindBranchs($("#ddBrands"),"#ddBranchs");
            //BindBranchs($("#ddBrandsAddBranchPopup"),"#ddBranchsCopy");
            AddEditBranchDetails();
            ClearBranch();
        }
    });
}
function DeleteBranch() {
    var value = {
        "BranchId": $('#BranchID').val(),
    };
    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteBranch",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            alert(result.Message);
            AddEditBranchDetails();
            ClearBranch();
            //GetBranchs();
            //BindBranchs($("#ddBrands"),"#ddBranchs");
            //BindBranchs($("#ddBrandsAddBranchPopup"),"#ddBranchsCopy");
        }
    });
}
function ClearBranch() {
    $("input[type=text]").val('');
    $("#btnUpdateBranch").hide("slow");
    $("#btnDeleteBranch").hide("slow");
    $("#btnAddBranch").show("slow");
    $("#copyBranchtr").show("slow");

    $("#ddBranchsCopy").jqxDropDownList({ selectedIndex: -1 });
    $("#grdBranch").jqxGrid('clearselection');

    if (dataAdapterBrandList != undefined) {
        if (dataAdapterBrandList.totalrecords == 1) {
            //$("#ddBrands").jqxDropDownList({ selectedIndex: 1 });
            //$("#ddBrandsAddBranchPopup").jqxDropDownList({ selectedIndex: 1 });
            //$("#ddBrands").val(1);
            $("#ddBrandsAddBranchPopup").val(1);
        }
        else {
            $("#ddBrandsAddBranchPopup").jqxDropDownList({ selectedIndex: -1 });
        }
    }
    else {
        $("#ddBrandsAddBranchPopup").jqxDropDownList({ selectedIndex: -1 });
    }

}


//-------------------------------------Question Details-------------------------------------
function fillType(Type) {
    var FeedBackTypesad =
    {
        dataType: "json",
        dataFields: [
            { name: 'TypeId', type: 'number' },
            { name: 'Type', type: 'string' },
        ],
        id: 'TypeId',
        localdata: Type
    };
    var dataAdapterType = new $.jqx.dataAdapter(FeedBackTypesad);
    $("#ddType").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'Select Type:',
        source: dataAdapterType,
        displayMember: "Type",
        valueMember: "TypeId",
        width: 270,
        height: 25
    });
}
function GetFeedBackLayouts() {
    ClearFeedBackLayout();
    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/FeedBackLayout",
        success: function (result) {
            var FeedBackLayouts = result.dtFeedBackLayout;
            var FeedBackType = result.dtFeedBackType;
            fillType(FeedBackType);
            var FeedBackLayoutsad =
            {
                dataType: "json",
                dataFields: [
                    { name: 'id', type: 'number' },
                    { name: 'TypeId', type: 'number' },
                    { name: 'BrandID', type: 'number' },
                    { name: 'Question', type: 'string' },
                    { name: 'Type', type: 'string' },
                    { name: 'Sequence', type: 'number' },
                ],
                id: 'id',
                localdata: FeedBackLayouts
            };
            var dataAdapterBrand = new $.jqx.dataAdapter(FeedBackLayoutsad);
            $("#grdFeedBackLayout").jqxGrid({
                width: '100%',
                height: '315',
                source: dataAdapterBrand,
                theme: 'ui-redmond',
                pageSize: 10,
                pageable: true,
                sortable: true,
                showfilterrow: true,
                filterable: true,
                columnsresize: true,
                selectionmode: 'singlerow',
                columns: [
                    { dataField: 'id', text: 'id', hidden: true },
                    { dataField: 'TypeId', text: 'ThemeID', hidden: true },
                    { dataField: 'BrandID', text: 'BrandID', hidden: true },
                    { dataField: 'Question', text: 'Question', width: '70%', },
                    { dataField: 'Type', text: 'Type', width: '15%', },
                    { dataField: 'Sequence', text: 'Sequence', width: '15%', },
                ]

            });
            $("#grdFeedBackLayout").on('rowselect', function (event) {
                var row = $("#grdFeedBackLayout").jqxGrid('getrowdata', event.args.rowindex);
                $("#btnUpdateFeedBackLayout").show("slow");
                $("#btnDeleteFeedBackLayout").show("slow");
                $("#btnAddFeedBackLayout").hide("slow");
                $("#ddType").val(row.TypeId);
                $("#ddBrandsLayout").val(row.BrandID);
                $("#txtQuestion").val(row.Question);
                $("#txtQuestionSeq").val(row.Sequence);
                $("#FeedBackLayoutID").val(row.id);

            });
        }
    });

}
function AddFeedBackLayout() {

    if ($("#ddType").val() == '') {

        $("#ddType").notify('Please Select Type of Question', { position: "right" });
        return;
    }
    if ($("#ddBrandsLayout").val() == '') {

        $("#ddBrandsLayout").notify('Please Select Type of Question', { position: "right" });
        return;
    }


    var value = {
        "Question": $("#txtQuestion").val(),
        "Sequence": $("#txtQuestionSeq").val(),
        "TypeId": $("#ddType").val(),
        "BrandID": $("#ddBrandsLayout").val(),

    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddFeedBackLayout",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            GetFeedBackLayouts();
        }
    });
}
function UpdateFeedBackLayout() {
    if ($("#ddType").val() == '') {

        $("#ddType").notify('Please Select Type of Question', { position: "right" });
        return;
    }
    var value = {
        "id": $("#FeedBackLayoutID").val(),
        "Question": $("#txtQuestion").val(),
        "Sequence": $("#txtQuestionSeq").val(),
        "TypeId": $("#ddType").val(),
        "BrandID": $("#ddBrandsLayout").val(),
    };
    var obji = { value: value }
    $.ajax({
        type: "POST",
        url: "/Items/UpdateFeedBackLayout",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            GetFeedBackLayouts();
        }
    });
}
function DeleteFeedBackLayout() {
    var value = {
        "id": $("#FeedBackLayoutID").val(),
    };
    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteFeedBackLayout",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            GetFeedBackLayouts();
        }
    });
}
function ClearFeedBackLayout() {
    $("#grdFeedBackLayout").jqxGrid('clearselection');
    $("#ddType").jqxDropDownList({ selectedIndex: -1 });
    $("#ddBrandsLayout").jqxDropDownList({ selectedIndex: -1 });
    $("input[type=text]").val('');
    $("#btnUpdateFeedBackLayout").hide("slow");
    $("#btnDeleteFeedBackLayout").hide("slow");
    $("#btnAddFeedBackLayout").show("slow");

}

//-----------------------------------User Details----------------------------------- 

function GetWaiter() {

    ClearWaiter();
    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetWaiter",
        success: function (result) {
            var Waiter = result.dtWaiter;
            FillWaiter(Waiter);
        }
    });
}
function FillWaiter(Waiter) {
    var Waiter =
    {
        dataType: "json",
        dataFields: [
            { name: 'ID', type: 'number' },
            { name: 'NAME', type: 'string' },
            { name: 'USERNAME', type: 'string' },
            { name: 'BrandName', type: 'string' },
            { name: 'BrandID', type: 'string' },
            { name: 'RoleName', type: 'string' },
            { name: 'Role_ID', type: 'number' },
        ],
        id: 'ID',
        localdata: Waiter
    };
    var dataAdapterWaiter = new $.jqx.dataAdapter(Waiter);
    $("#grdWaiter").jqxGrid({
        width: '100%',
        height: '700',
        source: dataAdapterWaiter,
        theme: 'ui-redmond',
        pageSize: 20,
        pageable: true,
        sortable: true,
        columnsresize: true,
        autoshowloadelement: false,
        selectionmode: 'singlerow',
        filterable: true,
        showfilterrow: true,
        columns: [
            { dataField: 'ID', text: 'ID', hidden: true },
            { dataField: 'NAME', text: 'Name', width: '33%', },
            { dataField: 'USERNAME', text: 'UserName', width: '33%', },
            { dataField: 'BrandID', text: 'BrandID', hidden: true },
            { dataField: 'BrandName', text: 'Brand', width: '10%', hidden: true },
            { dataField: 'Role_ID', text: 'RoleID', width: '10%', hidden: true },
            { dataField: 'RoleName', text: 'RoleName', width: '33%', },
        ]
    });

    $("#grdWaiter").on('rowselect', function (event) {

        $("#btnAddWaiter").hide("slow");
        $("#btnUpdateWaiter").show("slow");
        $("#btnDeleteWaiter").show("slow");
        var getselectedrowindexes = event.args.rowindex;
        var row = $("#grdWaiter").jqxGrid('getrowdata', getselectedrowindexes);
        var ID = row.ID;
        var NAME = row.NAME;
        var USERNAME = row.USERNAME;
        $('#txtWaiterID').val(ID);
        $('#txtWaiterName').val(NAME);
        $('#ddRole').val(row.Role_ID);
        $("#txtUserName").val(USERNAME);
        $("#ddBrands3").jqxListBox('uncheckAll');
        var Brand = row.BrandID.split(',');
        for (i = 0; i < Brand.length; i++)
            $("#ddBrands3").jqxListBox('checkItem', Brand[i]);

    });
}
function AddWaiter() {

    if ($("#ddBrands3").val() == '') {

        $("#ddBrands3").notify('Please Select Country', { position: "right" });
        return;
    }

    var Brands = []
    var items = $("#ddBrands3").jqxListBox('getCheckedItems');
    for (var i = 0; i < items.length; i++) {
        Brands.push(items[i].value)
    }
    var abc = JSON.stringify(Brands)
    BrandID = abc.substring(1, ((abc.length) - 1));



    var value = {
        "NAME": $('#txtWaiterName').val(),
        "USERNAME": $("#txtUserName").val(),
        "Role_ID": $('#ddRole').val(),
        "Password": $("#txtPassword").val(),
        "BrandID": BrandID
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/AddWaiter",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            ClearWaiter();
            GetWaiter();
        }
    });
}
function UpdateWaiter() {


    if ($("#ddBrands3").val() == '') {

        $("#ddBrands3").notify('Please Select Country', { position: "right" });
        return;
    }

    var Brands = []
    var items = $("#ddBrands3").jqxListBox('getCheckedItems');
    for (var i = 0; i < items.length; i++) {
        Brands.push(items[i].value)
    }
    var abc = JSON.stringify(Brands)
    BrandID = abc.substring(1, ((abc.length) - 1));




    var value = {
        "ID": $('#txtWaiterID').val(),
        "NAME": $('#txtWaiterName').val(),
        "USERNAME": $("#txtUserName").val(),
        "Role_ID": $('#ddRole').val(),
        "Password": $("#txtPassword").val(),
        "BrandID": BrandID
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Items/UpdateWaiter",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message);
            ClearWaiter();
            GetWaiter();


        }
    });

}
function DeleteWaiter() {

    var value = {
        "ID": $('#txtWaiterID').val(),
    };

    //            var obj = JSON.stringify(value);
    $.ajax({
        type: "GET",
        url: "/Items/DeleteWaiter",
        contentType: 'application/json',
        data: value,
        success: function (result) {
            alert(result.Message);
            ClearWaiter();
            GetWaiter();
        }
    });

}
function ClearWaiter() {
    $("#btnUpdateWaiter").hide("slow");
    $("#btnDeleteWaiter").hide("slow");
    $("#btnAddWaiter").show("slow");
    $('#txtWaiterID').val('');
    $('#txtWaiterName').val('');
    $("#txtUserName").val('');
    $("#txtPassword").val('');
    //$("#txtDeletePassword").val('');
    $("#grdWaiter").jqxGrid('clearselection');
    $("#ddRole").jqxDropDownList({ selectedIndex: -1 });
    $("#ddBrands3").jqxListBox('uncheckAll');
}
function GetRole() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetRole",
        success: function (result) {
            var Role = result.dtRole;
            FillRole(Role);
        }
    });

}
function FillRole(Role) {

    var Role =
    {
        dataType: "json",
        dataFields: [
            { name: 'Role_ID', type: 'number' },
            { name: 'RoleName', type: 'string' }
        ],

        id: 'Role_ID',
        localdata: Role
    };


    var dataAdapterRole = new $.jqx.dataAdapter(Role);

    $("#ddRole").jqxDropDownList({
        selectedIndex: -1,
        placeHolder: 'Select Role:',
        source: dataAdapterRole,
        displayMember: "RoleName",
        valueMember: "Role_ID",
        width: 250,
        height: 25
    });



}


//-------------------------------------Themes Details-------------------------------------
function GetThemes() {
    Cleartheme();
    $.ajax({
        type: "GET",
        cache: false,
        url: "/Items/GetTheme",
        success: function (result) {
            var ThemeJson = result.dtgrdBrand;
            var Themes = {
                dataType: "json",
                dataFields: [
                    { name: 'themeID', type: 'number' },
                    { name: 'themeName', type: 'string' },
                    { name: 'categoryActive', type: 'string' },
                    { name: 'categoryInActive', type: 'string' },
                    { name: 'setting', type: 'string' },
                    { name: 'englishButton', type: 'string' },
                    { name: 'arabicButton', type: 'string' },
                    { name: 'closeButton', type: 'string' },
                    { name: 'homeScreen', type: 'string' },
                    { name: 'popUpBackground', type: 'string' },
                    { name: 'FontColor', type: 'string' },
                    { name: 'FontColorIngName', type: 'string' },
                    { name: 'FontColorItemName', type: 'string' },
                    { name: 'FontColorPrice', type: 'string' },
                    { name: 'itemBackgroundColor', type: 'string' },
                    { name: 'brandID', type: 'number' },
                    { name: 'BrandName', type: 'string' },
                ],
                id: 'themeID',
                localdata: ThemeJson
            };
            var dataAdapterThemes = new $.jqx.dataAdapter(Themes);
            $("#ddTheme").jqxDropDownList({
                selectedIndex: -1,
                placeHolder: 'Select Theme',
                source: dataAdapterThemes,
                displayMember: "themeName",
                valueMember: "themeID",
                width: 250,
                height: 25
            });

            $("#grdthemes").jqxGrid({
                width: '100%',
                height: '315',
                source: dataAdapterThemes,
                theme: 'ui-redmond',
                pageSize: 10,
                pageable: true,
                sortable: true,
                showfilterrow: true,
                filterable: true,
                columnsresize: true,
                autoshowloadelement: false,
                selectionmode: 'singlerow',
                columns: [
                    { dataField: 'themeID', text: 'ID', hidden: true },
                    { dataField: 'themeName', text: 'theme Name', },
                    { dataField: 'brandID', text: 'ID', hidden: true },
                    { dataField: 'BrandName', text: 'Brand Name', },
                    { dataField: 'categoryActive', text: 'categoryActive', },
                    { dataField: 'categoryInActive', text: 'categoryInActive' },
                    { dataField: 'englishButton', text: 'englishButton' },
                    { dataField: 'arabicButton', text: 'arabicButton', },
                    { dataField: 'closeButton', text: 'closeButton' },
                    { dataField: 'homeScreen', text: 'home Screen', },
                    { dataField: 'popUpBackground', text: 'popUpBackground' },
                    { dataField: 'FontColor', text: 'Category Font Color ', },
                    { dataField: 'FontColorItemName', text: 'FontColorItemName' },
                    { dataField: 'FontColorIngName', text: 'Font Color Ing Name', },
                    { dataField: 'FontColorPrice', text: 'Font Color Price' },
                    { dataField: 'itemBackgroundColor', text: 'item Background Color', },

                ]

            });
            $("#grdthemes").on('rowselect', function (event) {
                $("#btnUpdatetheme").show("slow");
                $("#btnDeletetheme").show("slow");
                $("#btnAddtheme").hide("slow");
                var getselectedrowindexes = event.args.rowindex;
                var row = $("#grdthemes").jqxGrid('getrowdata', getselectedrowindexes);
                $('#lblCategoryActive').text(row.categoryActive);
                $('#lblCategoryInActive').text(row.categoryInActive);
                $('#lblEnglishButton').text(row.englishButton);
                $('#lblArabicButton').text(row.arabicButton);
                $('#lbCloseButton').text(row.closeButton);
                $('#lblHomeScreen').text(row.homeScreen);
                $('#lblPopUpBackground').text(row.popUpBackground);

                $("#ddBrandsThemes").val(row.brandID);


                $("#txtthemeID").val(row.themeID),
                    $('#txtThemeName').val(row.themeName);
                $('#clrFontColor').val(row.FontColor);
                $('#clrFontColorItemName').val(row.FontColorItemName);
                $('#clrFontColorIngName').val(row.FontColorIngName);
                $('#clrFontColorPrice').val(row.FontColorPrice);
                $('#clrItemBackgroundColor').val(row.itemBackgroundColor);


                CreateImage("#imgCategoryActive", row.categoryActive);
                CreateImage("#imgCategoryInActive", row.categoryInActive)
                CreateImage("#imgEnglishButton", row.englishButton)
                CreateImage("#imgArabicButton", row.arabicButton)
                CreateImage("#imgCloseButton", row.closeButton)
                CreateImage("#imgHomeScreen", row.homeScreen)
                CreateImage("#imgPopUpBackground", row.popUpBackground)
            });
        }
    });

}
function Addtheme() {

    if ($("#txtThemeName").val() == '') {

        $("#txtThemeName").notify('Please Enter Theme name', { position: "right" });
        return;
    }
    if ($("#ddBrandsThemes").val() == '') {

        $("#ddBrandsThemes").notify('Please Select Brand', { position: "right" });
        return;
    }
    var value = {
        "themeName": $("#txtThemeName").val(),
        "brandID": $("#ddBrandsThemes").val(),
        "categoryActive": $('#lblCategoryActive').html(),
        "categoryInActive": $('#lblCategoryInActive').html(),
        "englishButton": $('#lblEnglishButton').html(),
        "arabicButton": $('#lblArabicButton').html(),
        "closeButton": $('#lbCloseButton').html(),
        "homeScreen": $('#lblHomeScreen').html(),
        "popUpBackground": $('#lblPopUpBackground').html(),
        "FontColor": $("#clrFontColor").val(),
        "FontColorItemName": $("#clrFontColorItemName").val(),
        "FontColorIngName": $("#clrFontColorIngName").val(),
        "FontColorPrice": $("#clrFontColorPrice").val(),
        "itemBackgroundColor": $("#clrItemBackgroundColor").val(),

    };

    var obji = { value: value, Command: "Add" }

    $.ajax({
        type: "POST",
        url: "/Items/EditTheme",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message)
            GetThemes();
        }
    });
}
function Updatetheme() {
    if ($("#txtThemeName").val() == '') {

        $("#txtThemeName").notify('Please Enter Theme name', { position: "right" });
        return;
    }
    var value = {
        "themeID": $("#txtthemeID").val(),
        "brandID": $("#ddBrandsThemes").val(),
        "themeName": $("#txtThemeName").val(),

        "categoryActive": $('#lblCategoryActive').text(),
        "categoryInActive": $('#lblCategoryInActive').text(),
        "englishButton": $('#lblEnglishButton').text(),
        "arabicButton": $('#lblArabicButton').text(),
        "closeButton": $('#lbCloseButton').text(),
        "homeScreen": $('#lblHomeScreen').text(),
        "popUpBackground": $('#lblPopUpBackground').text(),
        "FontColor": $("#clrFontColor").val(),
        "FontColorItemName": $("#clrFontColorItemName").val(),
        "FontColorIngName": $("#clrFontColorIngName").val(),
        "FontColorPrice": $("#clrFontColorPrice").val(),
        "itemBackgroundColor": $("#clrItemBackgroundColor").val(),

    }
    var obji = { value: value, Command: "Update" }
    $.ajax({
        type: "POST",
        url: "/Items/EditTheme",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            alert(result.Message)
            GetThemes();
        }
    });
}
function Cleartheme() {
    $("#grdthemes").jqxGrid('clearselection');
    $("#grdthemes").jqxDropDownList({ selectedIndex: -1 });
    $("input[type=color]").val('');

    $("#btnUpdatetheme").hide("slow");
    $("#btnDeletetheme").hide("slow");
    $("#btnAddtheme").show("slow");
    var p = "../../images/no_image.png";
    var t;
    $("#Image").val('');
    t = "<div> <img src=" + p + "  width='50' height='50'/>  </div>";
    $("#ddBrandsThemes").jqxDropDownList({ selectedIndex: -1 });
    $("#imgArabicButton").html(t);
    $("#imgEnglishButton").html(t);
    $("#imgPopUpBackground").html(t);
    $("#imgHomeScreen").html(t);
    $("#imgCloseButton").html(t);
    $("#imgCategoryInActive").html(t);
    $("#imgCategoryActive").html(t);
    $('#lblCategoryActive').text("");
    $('#lblCategoryInActive').text("");
    $('#lblEnglishButton').text("");
    $('#lblArabicButton').text("");
    $('#lbCloseButton').text("");
    $('#lblHomeScreen').text("");
    $('#lblPopUpBackground').text("");
}


function OpenGenerateQrCode() {
    debugger;
    ClearQrcode();
    $("#WinGenerateQRcode").jqxWindow('open');
}

function ClearQrcode() {
    $("#ddBranchList").val();
    $("#divQRCodeImage").html("");
    $("#divBranchURL").html("");
}

function GenerateQrcode() {
    var selectedBranch = $("#ddBranchList").val();
    if (selectedBranch != 0) {

    }
    else {
        $("#ddBranchList").notify('Please Select Branch', { position: "right" });
    }
}


////////////start Bind Extra Items and Extra Comments //////////////

function BindExtraItesmDdr(Cat_Num) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: { Cat_Num: Cat_Num },
        url: "/Items/GetExtraItems",
        success: function (result) {
            var Items = result.dtgrdItems;
            FillExtraItems(Items);
        }
    });
}
function FillExtraItems(Items) {
    var Items =
    {
        dataType: "json",
        dataFields: [
            { name: 'ID', type: 'number' },
            { name: 'ITEM_NAME', type: 'string' },
            { name: 'ITEM_NAME_ARABIC', type: 'string' },
        ],

        id: 'ID',
        localdata: Items
    };

    var dataAdapterItems = new $.jqx.dataAdapter(Items);
    debugger;
    $('#ddExtraItems').jqxDropDownList({
        selectedIndex: -1,
        //searchmode: 'contains',
        //placeHolder: 'All',
        source: dataAdapterItems,
        displayMember: "ITEM_NAME",
        checkboxes: true,
        valueMember: "ID",
        width: 270,
        height: 25,
    });
}

function BindExtraCommentsDdr() {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        //data: { brandid: BrandId },
        url: "/Items/GetExtraComments",
        success: function (result) {
            var Comments = result.dtgrdComments;
            FillExtraComments(Comments);
        }
    });
}
function FillExtraComments(Comments) {
    var Comments =
    {
        dataType: "json",
        dataFields: [
            { name: 'ID', type: 'number' },
            { name: 'comments_eng', type: 'string' },
            { name: 'comments_arb', type: 'string' },
        ],

        id: 'ID',
        localdata: Comments
    };

    var dataAdapterComments = new $.jqx.dataAdapter(Comments);
    debugger;
    $('#ddExtraComments').jqxDropDownList({
        selectedIndex: -1,
        //searchmode: 'contains',
        //placeHolder: 'All',
        source: dataAdapterComments,
        displayMember: "comments_eng",
        checkboxes: true,
        valueMember: "ID",
        width: 270,
        height: 25,
    });
}
////////////End Bind Extra Items and Extra Comments //////////////