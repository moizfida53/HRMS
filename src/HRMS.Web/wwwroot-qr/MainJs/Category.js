var tempbrandid = 0;
var isbackcounter = 0;
var selectedMainCategoryId = 0;
var SelectedCategoryIsSub = 0;
var ExtraItemsList = null;
var CommentsList = null;
var choicesList = null;
var GroupModifierTypesList = null;
var table_ReservationData;
var GroupModifierList = null;
$(document).ready(function () {
    $(document).ajaxStart(function () {
        $('.loading').show();
    });
    $(document).ajaxStop(function () {
        $('.loading').hide();
    });
    $(document).ajaxError(function () {
        $('.loading').hide();
    });

    debugger;
    if ($('#hdnIsChoiceBind').val() == "false") {
        $('#divCreateItemChoiceList').hide();
        $('#divChoicesList').hide();
    }

    if ($('#hdnIsExtraItemsBind').val() == "false") {
        $('#divCreateItemExtraItemsList').hide();
        $('#divExtraItemsList').hide();
    }
    tempbrandid = $('#hdnBrandId').val();
    GetBrands();
    BindCategory();
    BindExtraComments();
    BindGroupModifier();
    BindAllergens();
    //BindItemBranchs(1);
    //$('.js-example-basic-single').select2();
    //$("#ddBrand").select2({
    //    placeholder: "Select Brand",
    //});
    //$('#ddItemBrand').select2({
    //    placeholder: "Select Brand",
    //});
    //$('#ddExtraItems').select2();
    //$('#ddExtraComments').select2();
    //$('#ddBranch').select2({
    //    //dropdownParent: $('#WindowCategoryAdd')
    //});
    //$('#ddItemBranch').select2();

    $('.custom-file-input').on('change', function () {
        //get the file name
        debugger;
        var fileName = $(this).val();

        var fileNameIndex = fileName.lastIndexOf("\\") + 1;
        fileName = fileName.substr(fileNameIndex);
        //replace the "Choose a file" label
        $(this).next('.custom-file-label').html(fileName);
    });

    //$('#ddGroupModifierType').change(function () {
    //    debugger;
    //    // $(this).val() will work here
    //    if ($(this).find(":selected").text() == "Choice") {
    //        $('#divGModifierCreateItemChoiceList').show();
    //        $('#divGModifierCreateItemExtraItemsList').hide();
    //    }
    //    else {
    //        $('#divGModifierCreateItemChoiceList').hide();
    //        $('#divGModifierCreateItemExtraItemsList').show();
    //    }
    //});



});

function GetBrands() {
    $.ajax({
        type: "GET",
        cache: false,
        async: false,
        url: "/Category/GetBrands",
        success: function (result) {
            var Brands = result.dtgrdBrand;
            FillBrands(Brands);
        }
    });

}
function FillBrands(Brands) {

    for (var i = 0; i < Brands.length; i++) {
        var opt = new Option(Brands[i].BrandName, Brands[i].BrandID);
        $('#ddBrand').append(opt);
        $('#ddItemBrand').append(opt);
    };

    //$('#ddBrand').trigger('change');
    //$('#ddItemBrand').trigger('change');

    //BrandID set in layoutNew page
    BindBranchs(tempbrandid);




    $("#ddBrand").on('change', function (event) {
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
                BindBranchs(item.value);
            }
            //var type = args.type; // keyboard, mouse or null depending on how the item was selected.
        }
    });
}
var BranchList;
function BindBranchs(BrandId) {
    $("#ddBranch").html("");
    $("#ddItemBranch").html("");
    $("#ulBranchList").html("");
    $.ajax({
        type: "GET",
        cache: false,
        data: { brandid: BrandId },
        url: "/Category/GetBranchsBrandWise",
        success: function (result) {
            //var Branchs = result.dtgrdBranch;
            debugger;
            BranchList = result.dtgrdBranch;
            var cntOfBranch = result.dtgrdBranch.length;
            $.each(result.dtgrdBranch, function (data, value) {
                $("#ddItemBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
                if (cntOfBranch == 1) {
                    $("#ddBranch").append($("<option selected></option>").val(value.BranchId).html(value.branchName));
                }
                else {
                    $("#ddBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
                }

                var strBranchLi = ""
                //strBranchLi = '<li>\
                //                <div class="custom-control custom-radio">\
                //                    <input type="radio" id="rdBranch_'+ value.BranchId + '" data-val="' + value.BranchId + '" value="' + value.BranchId + '" name="customRadio" onchange="rdBranchCheck(this);" class="custom-control-input clRadioBranch">\
                //                    <label class="custom-control-label" for="rdBranch_'+ value.BranchId + '">' + value.branchName + '</label>\
                //                </div>\
                //            </li>';
                strBranchLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="branch_tdShort"><button href="#" class="fa fa-angle-up btn btn-warning btnSortingModifier" title="Up" onclick="UpdateBranchSequence('+ value.BranchId + ',\'up\');" style=""></button>\
                                    <button href="#" class="fa fa-angle-down btn btn-warning btnSortingModifier" title="Down" onclick="UpdateBranchSequence(' + value.BranchId + ',\'down\');" style=""></button></td>\
                                <td class="branch_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdBranch_'+ value.BranchId + '" data-val="' + value.BranchId + '"  value="' + value.BranchId + '" name="customRadio" onchange="rdBranchCheck(this);" class="custom-control-input clRadioBranch">\
                                            <label class="custom-control-label" for="rdBranch_'+ value.BranchId + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="branch_td2">' + value.branchName + '</td>\
                                    <td class="branch_td3" >\
                                        <a href="#" class="edit-btn" data-val-Eng="' + value.branchName + '" data-val-Arb="' + value.BranchNameAra + '" data-val-Active="' + value.IsActive + '" \
                                            onclick="OnEditBranch(this,' + value.BranchId + ')";><img src="../images/text-edit.svg" alt=""></a>\
												</td>\
											</tr>	\
										</table>\
									</li>';
                $("#ulBranchList").append(strBranchLi);
                debugger;
                if (value.IsActive == true) {
                    $("#chkBranchStatus_" + value.BranchId + "").prop("checked", true);
                }
            });
            debugger;
            if (parseInt($('#hdnMultipleBranch').val()) == 1) {
                var strBranchAddButton = '<li>\
                                <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowBranchAdd" onclick="AddBranch()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Branch</span></a>\
                            </li>';
                $("#ulBranchList").append(strBranchAddButton);
            }


            $('#ddItemBranch').bsMultiSelect('update');
            $('#ddBranch').bsMultiSelect('update');
            //$("#ddBranch").bsMultiSelect();
            //var strClearSelection = '<li>\
            //                    <a onclick="clearBranchSelect();" class="btn btn-icon btn-secondary  w-100 text-left" > <img class="icon" src="../Images/clear.svg" alt=""> <span>Clear Selection</span></a>\
            //                </li >';
            //$("#ulBranchList").append(strClearSelection);


            //$('#ddBranch').multiselect();
            //$('#ddBranch').trigger('change');
            //$('#ddItemBranch').trigger('change');
        }
    });
}

function ClearCategoryFields() {
    debugger;
    if ($('#hdnIsSubCategoryProject').val() == "true") {
        BindMainCategory();
        $("#chkIsSubCategory").prop("checked", false);
        $('#divddrMainCategoryList').hide();
    }
    if (BranchList.length != 1) {
        $('#ddBranch').val('').bsMultiSelect('update');
    }

    $("#AddCategoryTitle").text(getAdmLbl("adm_titleAddCategory", "Add Category"));
    $("#CatAddButton").text(getAdmLbl("adm_btnAdd", "Add"));

    $("#txtCategoryName").val('');
    $("#txtCategoryNameArabic").val('');

    $("#txtCategoryNumber").val(0);
    $("#txtSeqNo").val(0);
    debugger;
    //$("input[name=chkShowCategory]:checked").val('true');
    //$("input[name=isSubCategory]:checked").val('false');

    $("#chkShowCategory").prop("checked", true);
    $("#isSubCategory").prop("checked", false);

    $("#CatDeleteButton").hide();
}

function SaveCategory() {

    debugger
    //if ($("#ddBrand").val() == '') {
    //    $("#warningMessage").html("Please Select Brand.");
    //    $('#warning').modal("toggle");
    //    return;
    //}
    if ($("#txtCategoryName").val() == '') {
        $("#warningMessage").html(getAdmLbl("adm_msgInsertCatName", "Please insert Category Name."));
        $('#warning').modal("toggle");
        return;
    }

    if ($("#txtCategoryNameArabic").val() == '') {
        $("#warningMessage").html(getAdmLbl("adm_msgInsertCatNameAra", "Please insert Category Name (Arabic)."));
        $('#warning').modal("toggle");
        return;
    }



    var Package = $("#ddBranch").val();
    var PackageData = new Array();
    if (Package != undefined) {
        if (Package.length > 0) {
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i];
                PackageData[i] = { "BranchId": RowData };
            }
        }
    } else {
        $("#ddBranch").notify('Please Select branch', { position: "right" });
        return;
    }

    if ($('#txtCategoryName').val() == "") {
        $("#txtCategoryName").notify('Please insert Category Name', { position: "right" });
        return;
    }
    // initially it is aasume that for main category the value for MainCateogry in DB is = so  MainCategory=0 
    // if it is sub category then the value of main category for this sub category is taken from ddMainCategory 
    var MainCategory = 0;
    //var isSubCategory = $("input[name=isSubCategory]:checked").val()
    //if (isSubCategory) {
    //    MainCategory = $('#ddMainCategory').val()
    //}
    var isSubCategory = $('#chkIsSubCategory').is(":checked");
    if (isSubCategory) {
        MainCategory = $('#ddMainCategoryList').val();
        if (!(parseInt(MainCategory) > 0)) {
            return;
        }

    }
    debugger;

    var IsShowInTablet = false;
    if ($('#chkShowCategory').is(':checked')) {
        IsShowInTablet = true;
    }
    var value = {
        "CAT_NUM": $('#txtCategoryNumber').val(),
        "CAT_NAME": $('#txtCategoryName').val(),
        //"BrandID": $('#ddBrand').val(),
        "BrandID": tempbrandid,
        "BranchData": PackageData,
        "CAT_NAME_ARABIC": $("#txtCategoryNameArabic").val(),
        "CatNameMan": $("#txtCategoryNameMan").val(),
        "CatNameRus": $("#txtCategoryNameRus").val(),
        "ShowInTablet": IsShowInTablet,
        "SEQ_NUM": $("#txtSeqNo").val(),
        "MainCategory": MainCategory
    };

    var CatOpr = "AddCategory";
    if ($('#txtCategoryNumber').val() != 0) {
        CatOpr = "UpdateCategory";
    }

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Category/" + CatOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {

            //check if subcategory edit then bind only subcategory list
            if (selectedMainCategoryId > 0) {
                BindSubCategory(selectedMainCategoryId);
            }
            BindCategory();

            //alert(result.Message);

            $("#message").html(result.Message);
            $('#alert').modal("toggle");

            $("#WindowCategoryAdd").modal('hide');
        }
    });
}

function DeleteCategory() {
    debugger
    var obji = {
        "CAT_NUM": $('#txtCategoryNumber').val()
    }
    $.ajax({
        type: "POST",
        url: "/Category/DeleteCategory",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            if (result.Message == "Deleted Sucessfully") {
                //check if subcategory edit then bind only subcategory list
                if (selectedMainCategoryId > 0) {
                    BindSubCategory(selectedMainCategoryId);
                }
                BindCategory();
                $("#message").html(result.Message);
                $('#alert').modal("toggle");
                $("#WindowCategoryAdd").modal('hide');
            }
            else if (result.Message == "SubCategory Exist") {
                result.Message = "You can not delete this Category, Please remove Sub Category first."
                $("#warningMessage").html(result.Message);
                $('#warning').modal("toggle");
            }
            else if (result.Message == "Items Exist") {
                result.Message = "You can not delete this Category, Please remove Items first."
                $("#warningMessage").html(result.Message);
                $('#warning').modal("toggle");
            }

        }
    });
}

//Bind  Category
/* Called by AdminLang.js after an EN<->AR switch: re-render the visible list so
   DB category/item names load in the selected language. */
window.onAdminLangChanged = function (lang) {
    try {
        if ($('#divCategoryItemsList').is(':visible') && window.admCurrentCatId) {
            BindCategoryItems(window.admCurrentCatId);
        } else if ($('#divSubCategoryList').is(':visible') && window.admCurrentCatId) {
            BindSubCategory(window.admCurrentCatId);
        } else {
            BindCategory();
        }
    } catch (e) { try { BindCategory(); } catch (e2) { } }
};
function BindCategory() {
    debugger;
    $('#CategoryList').html("");

    $.ajax({
        type: "Post",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/Category/GetCategoryList?BrandId=" + tempbrandid + "&Branchid=" + $('#hdnBranchId').val() + "&MainCategoryId=" + 0,
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Category = result.dtCategory;
                FillCategories(Category);
                //var selectedCatItems = result.dtItems;
                CreateCategoryHtml(Category);
            }
        }
    });
}
function CreateCategoryHtml(Category) {
    debugger;
    var Mainstr = '';
    if ($('#hdnIsEcommerce').val() == "false") {
        Mainstr = '<div class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2">' +
            '<a class="card add-btn" data-toggle="modal" data-target="#WindowCategoryAdd"  onclick="ClearCategoryFields()">' +
            '<img src="../Images/add.svg" alt="">' +
            '</a>' +
            '</div >';
    }

    var cntcat = 0;
    $.each(Category, function (i, item) {
        //var isDisplaySubcategory = true;
        //if ($('#hdnIsSubCategoryProject').val()=="true") {
        //    if (item.MainCategory != 0) {
        //        isDisplaySubcategory = false;
        //    }
        //}

        //if (isDisplaySubcategory == true) {
        var catname = (typeof getAdmLang === 'function' && getAdmLang() === 'AR' && item.CAT_NAME_ARABIC) ? item.CAT_NAME_ARABIC : item.CAT_NAME;

        //var catname = "";
        //if ($('#selectedLang').val() == "EN") {
        //    catname = item.CAT_NAME;
        //}
        //else {
        //    catname = item.CAT_NAME_ARABIC;
        //}
        var opacity = 1;
        if (item.ShowInTablet != true) {
            opacity = 0.5;
        }
        var str = "";
        //onclick = "OnCategoryClick(' + item.CAT_NUM + ');"
        //
        str = '<div id="Cat_' + item.CAT_NUM + '" onmousedown = "divmousedown();" onmousemove = "divmousemove();" onmouseup = "divmouseup(' + item.CAT_NUM + ',this);" data-val-id="' + item.CAT_NUM + '" data-val="' + catname + '" data-text="' + cntcat + '" class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2 catDraggable" style="opacity:' + opacity + ' !important;">' +
            '<div class="card">' +
            '<div class="custom-control custom-checkbox">' +
            '       <input type="checkbox" class="custom-control-input clChkCategory" id="ChkCategory_' + item.CAT_NUM + '" onchange="chkCategoryCheck(this,' + item.CAT_NUM + ');">' +
            '          <label class="custom-control-label" for="customCheck1"></label>' +
            '     </div>' +
            '    <img data-val="' + catname + '" onclick="OnCategoryClick(' + item.CAT_NUM + ',this,' + item.IsHaveSubCategory + ')" src="../Images/' + item.ImageName + '" class="card-img-top img-responsive" alt="...">' +
            '       <div class="card-body">' +
            '          <div class="d-flex justify-content-between">' +
            '             <p class="card-text">' + catname + '</p>' +
            '            <a href="#" class="edit-btn" data-val="' + catname + '" onclick="OnCategoryEditClick(' + item.CAT_NUM + ')";><img src="../Images/text-edit.svg" alt=""></a>' +
            '   </div>' +
            '      </div>' +
            ' </div>' +
            '</div>'


        //str = '<div id="Cat_' + item.CAT_NUM + '" onclick="OnCategoryClick(' + item.CAT_NUM + ');" data-val="' + catname + '" data-text="' + cntcat + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4">' +
        //    '<a class="card-primary ml-1 mr-1" >' +
        //    '<img class="card-img-top img-responsive img-Category" src="../../ThumbnailImages/' + item.ImageName + '" alt="">' +
        //    '<div class="card-body">' +
        //    '<h3>' + catname + '</h3>' +
        //    '</div>' +
        //    '</a>' +
        //    '</div>';

        Mainstr = Mainstr + str;
        cntcat = cntcat + 1;

        //if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
        //    $('#divCatename').html(catname);
        //    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
        //}
        //}

    });
    $('#CategoryList').html(Mainstr);

    //$('#CategoryList').gridstrap();
}

//Bind SubCategory
function BindSubCategory(Main_cat_num) {
    debugger;
    selectedMainCategoryId = Main_cat_num;
    $('#divCategoryList').hide()
    $('#divSubCategoryList').show();
    $('#selectedSubCategoryId').val(Main_cat_num)
    $('#ItemCategoryNumber').val(Main_cat_num);
    $('#SubCategoryList').html("");

    $.ajax({
        type: "Post",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/Category/GetCategoryList?BrandId=" + tempbrandid + "&Branchid=" + $('#hdnBranchId').val() + "&MainCategoryId=" + Main_cat_num,
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Category = result.dtCategory;
                FillCategories(Category);
                //var selectedCatItems = result.dtItems;
                CreateSubCategoryHtml(Category);
            }
        }
    });
}
function CreateSubCategoryHtml(Category) {
    debugger;
    var Mainstr = '<div class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2">' +
        '<a class="card add-btn" data-toggle="modal" data-target="#WindowCategoryAdd"  onclick="ClearCategoryFields()">' +
        '<img src="../Images/add.svg" alt="">' +
        '</a>' +
        '</div >';
    var cntcat = 0;
    $.each(Category, function (i, item) {
        var catname = (typeof getAdmLang === 'function' && getAdmLang() === 'AR' && item.CAT_NAME_ARABIC) ? item.CAT_NAME_ARABIC : item.CAT_NAME;

        //var catname = "";
        //if ($('#selectedLang').val() == "EN") {
        //    catname = item.CAT_NAME;
        //}
        //else {
        //    catname = item.CAT_NAME_ARABIC;
        //}
        var opacity = 1;
        if (item.ShowInTablet != true) {
            opacity = 0.5;
        }
        var str = "";
        //onclick = "OnCategoryClick(' + item.CAT_NUM + ');"
        //
        str = '<div id="Cat_' + item.CAT_NUM + '" onmousedown = "divmousedown();" onmousemove = "divmousemove();" onmouseup = "divmouseup(' + item.CAT_NUM + ',this);" data-val-id="' + item.CAT_NUM + '" data-val="' + catname + '" data-text="' + cntcat + '" class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2 catDraggable" style="opacity:' + opacity + ' !important;">' +
            '<div class="card">' +
            '<div class="custom-control custom-checkbox">' +
            '       <input type="checkbox" class="custom-control-input clChkCategory" id="ChkCategory_' + item.CAT_NUM + '" onchange="chkCategoryCheck(this,' + item.CAT_NUM + ');">' +
            '          <label class="custom-control-label" for="customCheck1"></label>' +
            '     </div>' +
            '    <img data-val="' + catname + '" onclick="OnCategoryClick(' + item.CAT_NUM + ',this,' + item.IsHaveSubCategory + ')" src="../Images/' + item.ImageName + '" class="card-img-top img-responsive" alt="...">' +
            '       <div class="card-body">' +
            '          <div class="d-flex justify-content-between">' +
            '             <p class="card-text">' + catname + '</p>' +
            '            <a href="#" class="edit-btn" data-val="' + catname + '" onclick="OnCategoryEditClick(' + item.CAT_NUM + ')";><img src="../Images/text-edit.svg" alt=""></a>' +
            '   </div>' +
            '      </div>' +
            ' </div>' +
            '</div>'


        Mainstr = Mainstr + str;
        cntcat = cntcat + 1;


    });
    $('#SubCategoryList').html(Mainstr);

    //$('#CategoryList').gridstrap();
}

//Edit Category
function OnCategoryEditClick(cat_num) {
    debugger;
    $("#WindowCategoryAdd").modal('show');
    $("#CatDeleteButton").show();
    BindMainCategory();
    GetCategoryDetails(cat_num);
}
function GetCategoryDetails(CAT_NUM) {
    $.ajax({
        type: "GET",
        cache: false,
        data: { CAT_NUM },
        url: "/Category/GetCategoryDetails",
        success: function (result) {

            var CatItem = result.dtCategoryDetails;
            var selectedBranchs = result.dtselectedBranch;

            $("#AddCategoryTitle").text(getAdmLbl("adm_titleEditCategory", "Edit Category"));
            $("#CatAddButton").text(getAdmLbl("adm_btnSave", "Save"));

            $("#txtCategoryNumber").val(CatItem[0].CAT_NUM);
            $("#txtCategoryName").val(CatItem[0].CAT_NAME);
            $("#txtCategoryNameArabic").val(CatItem[0].CAT_NAME_ARABIC);
            $("#txtSeqNo").val(CatItem[0].SEQ_NUM);

            $("#chkShowCategory").prop('checked', CatItem[0].ShowInTablet);
            debugger;
            if ($('#hdnIsSubCategoryProject').val() == "true") {
                if (CatItem[0].MainCategory > 0) {
                    $("#chkIsSubCategory").prop('checked', true);
                    $("#divddrMainCategoryList").show();
                    $('#ddMainCategoryList').val(CatItem[0].MainCategory);
                    //$('#ddMainCategoryList option[value=' + CatItem[0].MainCategory+']').attr('selected', 'selected');
                }
                else {
                    $("#chkIsSubCategory").prop('checked', false);
                    $("#divddrMainCategoryList").hide();
                }
            }

            $("#chkShowCategory").prop('checked', CatItem[0].ShowInTablet);

            $("#isSubCategory").prop('checked', CatItem[0].MainCategory);
            $("#ddBranch").html("");
            $.each(BranchList, function (data, value) {
                if (jQuery.inArray(value.BranchId, selectedBranchs) !== -1) {
                    $("#ddBranch").append($("<option selected></option>").val(value.BranchId).html(value.branchName));
                }
                else {
                    $("#ddBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
                }
            });
            $('#ddBranch').bsMultiSelect('update');
        }
    });
}

//Bind category Items
function OnCategoryClick(cat_num, obj, IsHaveSubCategory) {
    window.admCurrentCatId = cat_num;
    var CategoryName = $(obj).attr("data-val");

    if ($('#hdnIsSubCategoryProject').val() == "true" && IsHaveSubCategory == 1) {

        //$('#hdnIsCategoryOrItemsSelected').val("SubCategory");
        $('#hdnIsCategoryOrItemsSelected').val("Category");

        //$('#divExtraItemsList').show();
        //$('#divCommentsList').show();
        $("#SubCategoryListHeaderLabel").html(getAdmLbl("adm_secSubCategory", "Sub Category") + ' (' + CategoryName + ')');
        $("#ItemPopupCategoryName").html(CategoryName);
        $("#ExtraItemPopupCategoryName").html(CategoryName);

        BindSubCategory(cat_num);

    }
    else {
        $('#hdnIsCategoryOrItemsSelected').val("Items");


        if ($('#hdnIsExtraItemsBind').val() == "true") {
            $('#divExtraItemsList').show();
        }

        if ($('#hdnIsChoiceBind').val() == "true") {
            $('#divChoicesList').show();
        }

        $('#divCommentsList').show();
        $('#divGroupModifierList').show();
        $('#divAllergensList').show();
        $("#itemlistHeaderLabel").html(getAdmLbl("adm_hdrItems", "Items") + ' (' + CategoryName + ')');
        $("#ItemPopupCategoryName").html(CategoryName);
        $("#ExtraItemPopupCategoryName").html(CategoryName);

        BindCategoryItems(cat_num);

        if ($('#hdnIsExtraItemsBind').val() == "true") {
            BindExtraItesmDdr();
        }
        if ($('#hdnIsChoiceBind').val() == "true") {
            BindChoicesDdr();
        }

    }
    isbackcounter = isbackcounter + 1;
    clearAllSelection();
    //BindItemBranchs(1);
}

//function BindSubCategory(selectedCategoryId) {
//    debugger;
//    $('#divCategoryList').hide()
//    $('#divCategoryItemsList').show();
//    $('#ItemCategoryNumber').val(selectedCategoryId);
//    $('#CategoryItemsList').html("");

//    $.ajax({
//        type: "Post",
//        contentType: "application/json; charset=utf-8",
//        dataType: "json",
//        cache: false,
//        //BrandID set in layoutNew page
//        url: "/Category/GetItemList?Cat_Num=" + selectedCategoryId + "&BrandId=" + tempbrandid + "&Branchid=" + $('#hdnBranchId').val(),
//        success: function (result) {
//            debugger;
//            if (result.Message == "Success") {
//                var CategoryItems = result.dtItems;
//                CreateCategoryItemHtml(CategoryItems);
//            }
//        }
//    });
//}

function BindCategoryItems(CategoryId) {
    debugger;
    $('#divCategoryList').hide()
    $('#divSubCategoryList').hide()
    $('#divCategoryItemsList').show();
    $('#ItemCategoryNumber').val(CategoryId);
    $('#CategoryItemsList').html("");

    $.ajax({
        type: "Post",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        //BrandID set in layoutNew page
        url: "/Category/GetItemList?Cat_Num=" + CategoryId + "&BrandId=" + tempbrandid + "&Branchid=" + $('#hdnBranchId').val(),
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var CategoryItems = result.dtItems;
                var IsShowAllergen = result.IsShowAllergen;
                window.isShowAllergenFlag = (IsShowAllergen == "1");
                if (IsShowAllergen == "1") {
                    $('#divAllergensList').show();
                }
                else {
                    $('#divAllergensList').hide();
                }
                CreateCategoryItemHtml(CategoryItems);
            }
        }
    });
}
function CreateCategoryItemHtml(CategoryItems) {
    debugger;
    var Mainstr = '';
    if ($('#hdnIsEcommerce').val() == "false") {
        Mainstr = '<div class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2">' +
            '<a class="card add-btn" data-toggle="modal" data-target="#WindowCategoryItemAdd"  onclick="ClearCategoryItemFields(1)">' +
            '<img src="../Images/add.svg" alt="">' +
            '</a>' +
            '</div >';
    }



    var cntitem = 0;
    $.each(CategoryItems, function (i, item) {

        var itemname = (typeof getAdmLang === 'function' && getAdmLang() === 'AR' && item.ITEM_NAME_ARABIC) ? item.ITEM_NAME_ARABIC : item.ITEM_NAME;

        //var catname = "";
        //if ($('#selectedLang').val() == "EN") {
        //    catname = item.CAT_NAME;
        //}
        //else {
        //    catname = item.CAT_NAME_ARABIC;
        //}
        var opacity = 1;
        if (item.ShowInTablet != true) {
            opacity = 0.5;
        }
        var str = "";
        debugger;
        //onclick = "OnCategoryItemClick(' + item.id + ');"
        str = '<div id="divItem_' + item.id + '"  data-val-id="' + item.id + '" data-val="' + itemname + '" data-text="' + cntitem + '" class="col-6 col-sm-4 col-xl-2 mb-3 pl-2 pr-2 catItemsDraggable" style="opacity:' + opacity + ' !important;">' +
            '<div class="card">' +
            '<div class="custom-control custom-checkbox">' +
            '       <input type="checkbox" class="custom-control-input clChkItem" id="ChkItem_' + item.id + '" onchange="chkItemCheck(this,' + item.id + ');">' +
            '          <label class="custom-control-label" for="customCheck1"></label>' +
            '     </div>' +
            '    <img src="../Images/' + item.IMAGENAME + '" class="card-img-top img-responsive" alt="...">' +
            '       <div class="card-body">' +
            '          <div class="d-flex justify-content-between">' +
            '             <p class="card-text">' + itemname + '</p>' +
            '            <a href="#" class="edit-btn" onclick="OnCategoryItemEditClick(' + item.id + ')";><img src="../Images/text-edit.svg" alt="" ></a>' +
            '           </div>' +
            '          <div class="d-flex justify-content-between">' +
            '             <p class="card-text">' + item.Currency + '. ' + item.PRICE + '</p>' +
            '             <a href="#" class="edit-btn" data-val="' + itemname + '" onclick="OnAssignGroupModifierClick(' + item.id + ',this)";> <img class="groupAssignmentEdit" src="../Images/group_modifier.png" alt="" ></a>' +
            '           </div>' +
            '      </div>' +
            ' </div>' +
            '</div>'


        //str = '<div id="Cat_' + item.CAT_NUM + '" onclick="OnCategoryClick(' + item.CAT_NUM + ');" data-val="' + catname + '" data-text="' + cntcat + '" class="col-6 col-sm-4 col-md-4 col-lg-6 pb-4">' +
        //    '<a class="card-primary ml-1 mr-1" >' +
        //    '<img class="card-img-top img-responsive img-Category" src="../ThumbnailImages/' + item.ImageName + '" alt="">' +
        //    '<div class="card-body">' +
        //    '<h3>' + catname + '</h3>' +
        //    '</div>' +
        //    '</a>' +
        //    '</div>';

        Mainstr = Mainstr + str;
        cntitem = cntitem + 1;

        //if (selectedCategoryId > 0 && item.CAT_NUM == selectedCategoryId) {
        //    $('#divCatename').html(catname);
        //    $('#divItemDetailsViewTopItemName').html($('#divCatename').html().trim());
        //}
    });
    $('#CategoryItemsList').html(Mainstr);
}
function ClearCategoryItemFields(isNewCreate) {
    //$('#ddBranch').val(null).trigger('change');
    //$('#ddBranch').val(null).trigger('change');
    debugger;

    $("#AddItemTitle").text(getAdmLbl("adm_titleAddItem", "Add Item"));
    $("#ItemAddButton").text(getAdmLbl("adm_btnSave", "Save"));

    $("#txtItemNameEng").val('');
    $("#txtItemNameAra").val('');

    $("#txtIngEng").val('');
    $("#txtIngAra").val('');

    $("#txtPrice").val('');
    $("#txtItemID").val(0);
    $("#txtSeqNo").val(0);

    //$("input[name=chkIsExtraItems]:checked").val(false);
    //$("input[name=chkShowItems]:checked").val(true);

    $("#ItemPopupCategoryName").show();
    $("#ddItemCategory").hide();

    $("#chkIsExtraItems").prop("checked", false);
    $("#chkShowItems").prop("checked", true);

    $("#hdnImageFileName").val('');
    $("#hdnVideoFileName").val('');
    $("#lblImageuploadName").html('Choose file');
    $("#vdfilename").html('Choose file');
    $("#lblVideoMessage").html('');

    debugger;
    $("#ddItemBranch").val('');
    $("#ddExtraComments").val('');
    $("#ddExtraItems").val('');

    $("#ddItemBranch").val('').bsMultiSelect('update');
    $("#ddExtraComments").val('').bsMultiSelect('update');
    $("#ddExtraItems").val('').bsMultiSelect('update');

    $("#Imagepreview").attr('src', "https://placehold.it/75x75");
    if (typeof resetSecondaryImages === 'function') { resetSecondaryImages(); }

    $("#ItemDeleteButton").hide();

    if (window.isShowAllergenFlag) {
        $('#divItemAllergensSection').show();
    } else {
        $('#divItemAllergensSection').hide();
    }
    if (AllergensList != null) {
        $("#ddItemAllergens").html("");
        $.each(AllergensList, function (data, value) {
            $("#ddItemAllergens").append($("<option></option>").val(value.id).html(value.name));
        });
        $('#ddItemAllergens').bsMultiSelect('update');
    }

    if (isNewCreate == 1) {
        $("#ddItemBranch").html("");
        $.each(BranchList, function (data, value) {
            //if (jQuery.inArray(value.BranchId, selectedBranchs) !== -1) {
            $("#ddItemBranch").append($("<option selected></option>").val(value.BranchId).html(value.branchName));
            //}
            //else {
            //    $("#ddItemBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
            //}
        });
        $('#ddItemBranch').bsMultiSelect('update');
    }

}

//function ClearGroupModifierFields(isNewCreate) {
//    //$('#ddBranch').val(null).trigger('change');
//    //$('#ddBranch').val(null).trigger('change');
//    debugger;

//    $("#AddGroupModifierTitle").text("Add Group Modifier");
//    $("#GroupModifierAddButton").text("Save");

//    $("#txtGroupModifierNameEng").val('');
//    $("#txtGroupModifierNameAra").val('');

//    $("#txtGroupModifierMinSelect").val(0);
//    $("#txtGroupModifierMaxSelect").val(0);

//    $("#txtGroupModifierId").val(0);
//    //$("#txtSeqNo").val(0);


//    debugger;
//    $("#ddItemBranch").val('');
//    $("#ddExtraComments").val('');
//    $("#ddExtraItems").val('');

//    $("#ddItemBranch").val('').bsMultiSelect('update');
//    $("#ddExtraComments").val('').bsMultiSelect('update');
//    $("#ddExtraItems").val('').bsMultiSelect('update');

//    $("#ItemDeleteButton").hide();
//    if (isNewCreate == 1) {
//        $("#ddItemBranch").html("");
//        $.each(BranchList, function (data, value) {
//            //if (jQuery.inArray(value.BranchId, selectedBranchs) !== -1) {
//            $("#ddItemBranch").append($("<option selected></option>").val(value.BranchId).html(value.branchName));
//            //}
//            //else {
//            //    $("#ddItemBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
//            //}
//        });
//        $('#ddItemBranch').bsMultiSelect('update');
//    }

//}
function FillCategories(Categories) {
    debugger;
    for (var i = 0; i < Categories.length; i++) {
        var opt = new Option(Categories[i].CAT_NAME, Categories[i].CAT_NUM);
        $('#ddItemCategory').append(opt);
    };
    //$('#ddItemCategory').bsMultiSelect('update');
    //$('#ddItemCategory').select2(
    //    {
    //        placeholder: "Select Category",
    //    }
    //);
}

var CommentsList;
function BindExtraComments() {
    $('#ddExtraComments').html("");
    $('#ulItemCommentsList').html("");

    $.ajax({
        type: "GET",
        cache: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetExtraComments",
        success: function (result) {
            //var Comments = result.dtgrdComments;
            CommentsList = result.dtgrdComments;
            debugger;
            var strCommentsAddButton = '<li>\
                                <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowAddComment" onclick="AddComment()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Comment</span></a>\
                            </li>'
            $("#ulItemCommentsList").append(strCommentsAddButton);

            $.each(result.dtgrdComments, function (data, value) {
                $("#ddExtraComments").append($("<option></option>").val(value.ID).html(value.comments_eng));

                var strItemCommentsLi = ""
                strItemCommentsLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="comment_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdItemComment_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio2" onchange="rdCommentCheck(this);" class="custom-control-input clrdItemComment">\
                                            <label class="custom-control-label" for="rdItemComment_'+ value.ID + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="comment_td2">' + value.comments_eng + '</td>\
                                    <td class="comment_td3" >\
                                        <a href="#" class="edit-btn" data-val-Eng="' + value.comments_eng + '" data-val-Arb="' + value.comments_arb + '"  onclick="OnEditComment(this,' + value.ID + ')";><img src="../images/text-edit.svg" alt=""></a>\
												</td>\
											</tr>	\
										</table>\
									</li>';
                //strItemCommentsLi = '<li>\
                //                <div class="custom-control custom-radio">\
                //                    <input type="radio" id="rdItemComment_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio2" onchange="rdCommentCheck(this);" class="custom-control-input clrdItemComment">\
                //                    <label class="custom-control-label" for="rdItemComment_'+ value.ID + '">' + value.comments_eng + '</label>\
                //                    <a href="#" class="edit-btn" onclick="OnEditComment(' + value.ID + ')";><img src="../Images/text-edit.svg" alt="" style="width:24px;"></a>\
                //                </div>\
                //            </li>';
                $("#ulItemCommentsList").append(strItemCommentsLi);
            })
            $('#ddExtraComments').bsMultiSelect('update');



            //$('#ddExtraComments').trigger('change');
        }
    });
}

function BindGroupModifier() {
    debugger;
    //$('#ddGroupModifier').html("");
    $('#ulGroupModifierList').html("");
    $.ajax({
        type: "GET",
        cache: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetGroupModifier",
        success: function (result) {
            debugger;
            //var Comments = result.dtgrdComments;
            GroupModifierList = result.dtGroupModifier;
            debugger;
            $("#ddGroupModifierassignment").html("");
            $("#ddGroupModifierassignment").append($("<option data-typeid=" + 0 + "></option>").val(0).html(getAdmLbl("adm_optSelect", "Select")));

            var strGroupModifierAddButton = '<li>\
                                <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowAddComment" onclick="AddGroupModifier()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Group Modifier</span></a>\
                            </li>'

            $("#ulGroupModifierList").append(strGroupModifierAddButton);

            $.each(result.dtGroupModifier, function (data, value) {
                //$("#ddGroupModifier").append($("<option></option>").val(value.ID).html(value.GroupNameEng));
                $("#ddGroupModifierassignment").append($("<option data-typeid=" + value.TypeID + "></option>").val(value.ID).html(value.GroupNameEng));

                var strGroupModifierLi = ""
                strGroupModifierLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="comment_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdItemComment_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio2" onchange="rdCommentCheck(this);" class="custom-control-input clrdItemComment">\
                                            <label class="custom-control-label" for="rdItemComment_'+ value.ID + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="comment_td2">' + value.GroupNameEng + '</td>\
                                    <td class="comment_td3" >\
                                        <a href="#" class="edit-btn" data-val-Eng="' + value.GroupNameEng + '" data-val-Arb="' + value.GroupNameArb + '"  onclick="OnEditGroupModifier(this,' + value.ID + ')";><img src="../images/text-edit.svg" alt=""></a>\
												</td>\
											</tr>	\
										</table>\
									</li>';
                //strItemCommentsLi = '<li>\
                //                <div class="custom-control custom-radio">\
                //                    <input type="radio" id="rdItemComment_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio2" onchange="rdCommentCheck(this);" class="custom-control-input clrdItemComment">\
                //                    <label class="custom-control-label" for="rdItemComment_'+ value.ID + '">' + value.comments_eng + '</label>\
                //                    <a href="#" class="edit-btn" onclick="OnEditComment(' + value.ID + ')";><img src="../Images/text-edit.svg" alt="" style="width:24px;"></a>\
                //                </div>\
                //            </li>';
                $("#ulGroupModifierList").append(strGroupModifierLi);
            })
            //$('#ddGroupModifier').bsMultiSelect('update');



            bindGroupModifierGridview(GroupModifierList);
            //$('#ddExtraComments').trigger('change');
        }
    });
}
function BindAllergens() {
    debugger;
    //$('#ddGroupModifier').html("");
    $('#ulAllergensList').html("");
    $.ajax({
        type: "GET",
        cache: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetAllergens",
        success: function (result) {
            debugger;
            //var Comments = result.dtgrdComments;
            AllergensList = result.dtAllergens;
            debugger;
            //$("#ddGroupModifierassignment").html("");
            //$("#ddGroupModifierassignment").append($("<option data-typeid=" + 0 + "></option>").val(0).html(getAdmLbl("adm_optSelect", "Select")));

            //var strAllergensAddButton = '<li>\
            //                    <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowAddComment" onclick="AddGroupModifier()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Group Modifier</span></a>\
            //                </li>'

            //$("#ulAllergensList").append(strAllergensAddButton);

            $.each(AllergensList, function (data, value) {
                //$("#ddGroupModifierassignment").append($("<option data-typeid=" + value.TypeID + "></option>").val(value.ID).html(value.GroupNameEng));

                var strAllergensLi = ""
                strAllergensLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="comment_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdAllergens_'+ value.id + '" data-val="' + value.id + '" name="customRadio2" onchange="rdAllergenCheck(this);" class="custom-control-input clrdAllergen">\
                                            <label class="custom-control-label" for="rdAllergens_'+ value.ID + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="comment_td2">' + value.name + '</td>\
                                    <td class="comment_td3" >\
									</td>\
								</tr>	\
							</table>\
						</li>';
                $("#ulAllergensList").append(strAllergensLi);
            })

            //bindGroupModifierGridview(GroupModifierList);
            //$('#ddExtraComments').trigger('change');
        }
    });
}
function clearAdditem() {

}
//Add/Edit Items
function SaveItem(IsExtraItem) {
    debugger;
    if (IsExtraItem == true) {
        if ($("#txtExtraItemNameEng").val() == '') {
            $("#warningMessage").html(getAdmLbl("adm_msgInsertItemName", "Please insert item Name."));
            $('#warning').modal("toggle");
            return;
        }

        //if ($("#txtExtraItemPrice").val() == '') {
        //    $("#warningMessage").html(getAdmLbl("adm_msgInsertPrice", "Please insert price."));
        //    $('#warning').modal("toggle");
        //    return;
        //}
    }
    else {
        if ($("#txtItemNameEng").val() == '') {
            $("#warningMessage").html(getAdmLbl("adm_msgInsertItemName", "Please insert item Name."));
            $('#warning').modal("toggle");
            return;
        }

        if ($("#txtItemNameAra").val() == '') {
            $("#warningMessage").html(getAdmLbl("adm_msgInsertItemNameAra", "Please insert item Name (Arabic)."));
            $('#warning').modal("toggle");
            return;
        }

        if ($("#txtPrice").val() == '') {
            $("#warningMessage").html(getAdmLbl("adm_msgInsertPrice", "Please insert price."));
            $('#warning').modal("toggle");
            return;
        }
    }


    var PackageData = new Array();
    var SelectedExtraItems = new Array();
    var selectedChoice = new Array();
    var SelectedComments = new Array();
    var PackageData = new Array();
    var Package = $("#ddItemBranch").val();

    if (Package != undefined) {
        if (Package.length > 0) {
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i];
                PackageData[i] = { "BranchId": RowData };
            }
        }
    }
    //else {
    //    $("#ddItemBranch").notify('Please Select branch', { position: "right" });
    //    return;
    //}

    //Start get selected Extra items
    var ExtraItems = $("#ddExtraItems").val();
    if (ExtraItems != undefined) {
        if (ExtraItems.length > 0) {
            for (var i = 0; i < ExtraItems.length; i++) {
                var RowData = ExtraItems[i];
                SelectedExtraItems[i] = { "ID": RowData };
            }
        }
    }
    //else {
    //    //$("#ddExtraItems").notify('Please Select Extra Items', { position: "right" });
    //    //return;
    //}
    //End get selected Extra items

    //Start get selected Comments
    var Comments = $("#ddExtraComments").val();
    if (Comments != undefined) {
        if (Comments.length > 0) {
            for (var i = 0; i < Comments.length; i++) {
                var RowData = Comments[i];
                SelectedComments[i] = { "id": RowData };
            }
        }
    } else {
        //$("#ddItemComments").notify('Please Select Comments', { position: "right" });
        //return;
    }

    //End get selected Comments


    //Start get selected Choice
    var Choices = $("#ddChoices").val();
    if (Choices != undefined) {
        if (Choices.length > 0) {
            for (var i = 0; i < Choices.length; i++) {
                var RowData = Choices[i];
                selectedChoice[i] = { "ID": RowData };
            }
        }
    }
    //End get selected Choice

    //Start get selected Allergens (only relevant for regular items, and only when
    //the Select Allergen section is actually shown for this brand - ShowAllergen=1)
    var SelectedAllergens = null;
    if (!IsExtraItem && window.isShowAllergenFlag) {
        SelectedAllergens = new Array();
        var Allergens = $("#ddItemAllergens").val();
        if (Allergens != undefined) {
            if (Allergens.length > 0) {
                for (var i = 0; i < Allergens.length; i++) {
                    var RowData = Allergens[i];
                    SelectedAllergens[i] = { "id": RowData };
                }
            }
        }
    }
    //End get selected Allergens

    //var ImageName = $('#lblFileName').text();
    //ImageName = ImageName.replace(" ", "_");

    var ImageName = $('#hdnImageFileName').val();
    var VideoName = $('#hdnVideoFileName').val();

    //if ($("#ddCategory").val() == '') {

    //    $("#ddCategory").notify('Please Select Category', { position: "top" });
    //    return;
    //}
    //if ($("#txtItemNameEng").val() == "" & IsExtraItem) {
    //    $("#txtItemNameEng").notify('Please insert Item Name', { position: "right" });
    //    return;
    //}

    var IsShowInTablet = false;

    if (IsExtraItem) {
        if ($('#chkShowItemsExtra').is(':checked')) {
            IsShowInTablet = true;
        }
    }
    else {
        if ($('#chkShowItems').is(':checked')) {
            IsShowInTablet = true;
        }
    }

    var ItemOpr = "AddItem";
    if ($('#txtItemID').val() != 0) {
        ItemOpr = "UpdateItem";
    }
    if ($('#hdnselectedExtraItemId').val() != 0) {
        ItemOpr = "UpdateItem";
    }

    var value = {
        "ID": IsExtraItem ? $('#hdnselectedExtraItemId').val() : $('#txtItemID').val(),
        "CAT_NUM": ItemOpr == "UpdateItem" ? $("#ddItemCategory").val() : $('#ItemCategoryNumber').val(),
        "ITEM_NAME": IsExtraItem ? $("#txtExtraItemNameEng").val() : $("#txtItemNameEng").val(),
        "ITEM_NAME_ARABIC": IsExtraItem ? $("#txtExtraItemNameAra").val() : $("#txtItemNameAra").val(),

        "ItemNameRus": IsExtraItem ? "" : $("#txtItemNameRus").val(),
        "ItemNameMan": IsExtraItem ? "" : $("#txtItemNameMan").val(),
        //"PRICE": IsExtraItem ? $("#txtExtraItemPrice").val() : $("#txtPrice").val(),
        "PRICE": IsExtraItem ? $("#txtExtraItemPrice").val() : $("#txtPrice").val(),
        "IMAGENAME": IsExtraItem ? $('#hdnExtreaItemImageFileName').val() : ImageName,

        "INGREDIENT": IsExtraItem ? "" : $("#txtIngEng").val(),
        "INGREDIENT_ARABIC": IsExtraItem ? "" : $("#txtIngAra").val(),
        "INGREDIENT_Rus": IsExtraItem ? "" : $("#txtIngRus").val(),
        "INGREDIENT_Man": IsExtraItem ? "" : $("#txtIngMan").val(),
        "ITEM_DESC_ENG": IsExtraItem ? "" : $("#txtDescription").val(),

        // "Seq_Num": $("#txtSequenceNo").val(),
        "Video": IsExtraItem ? "" : VideoName,
        "ShowInTablet": IsShowInTablet,
        "BranchData": PackageData,
        "BrandID": $("#hdnBrandId").val(),
        "IsExtraItems": IsExtraItem, //$('#chkIsExtraItems').prop("checked"),
        "ExtraItems": SelectedExtraItems,
        "Comments": SelectedComments,
        "Choices": selectedChoice,
        "Allergens": SelectedAllergens,
        // Explicit flag, separate from Allergens itself: an empty JS array can bind to
        // null on the server (ASP.NET MVC JSON-binding quirk), so the server can't
        // reliably tell "cleared to zero" apart from "section hidden, don't touch it"
        // just from Allergens being null. This flag removes that ambiguity.
        "IsAllergenSectionVisible": (!IsExtraItem && !!window.isShowAllergenFlag),
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Category/" + ItemOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            var finalizeItemSave = function () {
                IsItemUpdate = '1';

                $('#alert').modal("toggle");
                $("#message").html(result.Message);
                clearAllSelection();

                CategoryLock = true;//for Edit
                $("#WindowCategoryItemAdd").modal('hide');
                $("#WindowCategoryExtraItemAdd").modal('hide');
                BindCategoryItems($('#ItemCategoryNumber').val());
                if ($('#hdnIsExtraItemsBind').val() == "true") {
                    BindExtraItesmDdr();
                }
            };
            if (!IsExtraItem && typeof saveSecondaryImages === 'function') {
                var savedItemId = (ItemOpr == "AddItem" && result.ID) ? result.ID : $('#txtItemID').val();
                saveSecondaryImages(savedItemId, finalizeItemSave);
            } else {
                finalizeItemSave();
            }
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}

function DeleteItem(IsExtraItem) {
    debugger;
    var obji = {
        "ID": IsExtraItem ? $('#hdnselectedExtraItemId').val() : $('#txtItemID').val(),
    }
    $.ajax({
        type: "POST",
        url: "/Category/DeleteItem",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            if (result.Message == "Deleted Sucessfully") {
                IsItemUpdate = '1';

                $('#alert').modal("toggle");
                $("#message").html(result.Message);
                clearAllSelection();

                CategoryLock = true;//for Edit

                $("#WindowCategoryItemAdd").modal('hide');
                $("#WindowCategoryExtraItemAdd").modal('hide');

                BindCategoryItems($('#ItemCategoryNumber').val());
                //BindExtraItesmDdr();
            }

        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}
$("#btnImageUpload").click(function () {
    $('.loading').show();
    //var filename = $("#imageFileUpload").val();
    var fileUpload = $("#imageFileUpload").get(0);
    var files = fileUpload.files;

    // Create FormData object  
    var fileData = new FormData();

    // Looping over all files and add it to FormData object  
    for (var i = 0; i < files.length; i++) {
        fileData.append(files[i].name, files[i]);
    }

    debugger;
    $.ajax({
        type: "POST",
        url: "/Category/UploadFile",
        //enctype: 'multipart/form-data',
        //data: {
        //    file: filename
        //},
        contentType: false, // Not to set any content header  
        processData: false, // Not to process data  
        data: fileData,
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                $('#Imagepreview').attr('src', "../images/" + result.FileName);
                $('#hdnImageFileName').val(result.FileName);
                if (typeof enableSecondaryImages === 'function') { enableSecondaryImages(); }
            }
            //alert("Image Uploaded.");
            $('.loading').hide();
        },

    }).always(function (jqXHROrData, textStatus, jqXHROrErrorThrown) {
        debugger;
        $('.loading').hide();
    });
});
$("#btnVideoUpload").click(function () {
    debugger;
    //var formData = new FormData();
    //formData.append("fileName", $("#vdfilename").val());
    //formData.append("file", $("#videoFileUpload")[0].files[0]);

    var fileUpload = $("#videoFileUpload").get(0);
    var files = fileUpload.files;

    // Create FormData object  
    var fileData = new FormData();
    // Looping over all files and add it to FormData object  
    for (var i = 0; i < files.length; i++) {
        fileData.append(files[i].name, files[i]);
    }
    debugger;
    $.ajax({
        url: "/Category/VideoUploadFile",
        type: 'POST',
        //data: formData,
        data: fileData,
        cache: false,
        contentType: false,
        processData: false,
        success: function (result) {
            if (result.Message == "Success") {
                $("#fileProgress").hide();
                $("#lblVideoMessage").html("<b>" + result.FileName + "</b> has been uploaded.");
                $('#Imagepreview').attr('src', "../images/" + result.FileName);
                $('#hdnVideoFileName').val(result.FileName);
            }
        },
        xhr: function () {
            var fileXhr = $.ajaxSettings.xhr();
            if (fileXhr.upload) {
                $("progress").show();
                fileXhr.upload.addEventListener("progress", function (e) {
                    if (e.lengthComputable) {
                        $("#fileProgress").attr({
                            value: e.loaded,
                            max: e.total
                        });
                    }
                }, false);
            }
            return fileXhr;
        }
    });
    //var fileUpload = $("#videoFileUpload").get(0);
    //var files = fileUpload.files;

    //// Create FormData object  
    //var fileData = new FormData();

    //// Looping over all files and add it to FormData object  
    //for (var i = 0; i < files.length; i++) {
    //    fileData.append(files[i].name, files[i]);
    //}

    //debugger;
    //$.ajax({
    //    type: "POST",
    //    url: "/Category/UploadFile",
    //    //enctype: 'multipart/form-data',
    //    //data: {
    //    //    file: filename
    //    //},
    //    contentType: false, // Not to set any content header  
    //    processData: false, // Not to process data  
    //    data: fileData,
    //    success: function (result) {
    //        debugger;
    //        if (result.Message == "Success") {
    //            $('#hdnVideoFileName').val(result.FileName);
    //        }
    //        //alert("Image Uploaded.");
    //    }
    //});
});

$("#btnExtraItemImageUpload").click(function () {
    var fileUpload = $("#imageFileUploadExtra").get(0);
    var files = fileUpload.files;

    // Create FormData object  
    var fileData = new FormData();

    // Looping over all files and add it to FormData object  
    for (var i = 0; i < files.length; i++) {
        fileData.append(files[i].name, files[i]);
    }

    debugger;
    $.ajax({
        type: "POST",
        url: "/Category/UploadFile",
        //enctype: 'multipart/form-data',
        //data: {
        //    file: filename
        //},
        contentType: false, // Not to set any content header  
        processData: false, // Not to process data  
        data: fileData,
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                $('#ExtraItemImagepreview').attr('src', "../images/" + result.FileName);
                $('#hdnExtreaItemImageFileName').val(result.FileName);
            }
            //alert("Image Uploaded.");
        }
    });
});
function OnCategoryItemEditClick(ID) {
    debugger;
    //if (IsExtraItem) {
    //    $("#WindowCategoryExtraItemAdd").modal('show');
    //}
    //else {
    $("#WindowCategoryItemAdd").modal('show');

    //}
    ClearCategoryItemFields(0);
    GetItemDetails(ID);
    $("#ItemDeleteButton").show();
}
function AddExtraItem() {
    $("#WindowCategoryExtraItemAdd").modal('show');
    debugger;
    ClearCategoryExtraItemFields();
}
function OnEditExtraItems(ID) {
    debugger;
    $("#WindowCategoryExtraItemAdd").modal('show');
    ClearCategoryExtraItemFields();
    $("#AddExtraItemTitle").text(getAdmLbl("adm_titleEditExtraItem", "Edit Extra Item"));
    GetExtraItemDetails(ID);
}
function GetExtraItemDetails(ID) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: { ID },
        url: "/Category/GetItemDetails",
        success: function (result) {

            var Item = result.dtItemDetails;
            //var selectedBranchs = result.dtselectedBranch;
            //var selectedExtraItems = result.dtselectedExtraItems;
            //var selectedComments = result.dtselectedComments;
            debugger;
            $("#hdnselectedExtraItemId").val(ID);
            //$("#ItemPopupCategoryName").hide();
            //$("#ddItemCategory").show();

            //$("#ddItemCategory").val(Item[0].CAT_NUM);
            $("#txtExtraItemNameEng").val(Item[0].ITEM_NAME);
            $("#txtExtraItemNameAra").val(Item[0].ITEM_NAME_ARABIC);
            $("#txtExtraItemPrice").val(Item[0].PRICE);

            $("#chkShowItemsExtra").prop('checked', Item[0].ShowInTablet);
            //$("#chkShowItemsExtra").prop('checked', Item[0].IsActive);
            $("#ExtraItemImagepreview").attr("src", "../Images/" + Item[0].IMAGENAME + "");
            $("#hdnExtreaItemImageFileName").val(Item[0].IMAGENAME);

        }
    });
}
function ClearCategoryExtraItemFields() {
    //$('#ddBranch').val(null).trigger('change');
    //$('#ddBranch').val(null).trigger('change');
    debugger;

    $("#hdnselectedExtraItemId").val("0");
    $("#AddExtraItemTitle").text(getAdmLbl("adm_titleAddExtraItem", "Add Extra Item"));
    $("#ExtraItemAddButton").text(getAdmLbl("adm_btnSave", "Save"));

    $("#txtExtraItemNameEng").val('');
    $("#txtExtraItemNameAra").val('');

    $("#txtIngEng").val('');
    $("#txtIngAra").val('');

    $("#txtExtraItemPrice").val('');
    $("#txtItemID").val(0);

    $("#chkShowItemsExtra").prop("checked", true);
    $("#ExtraItemImagepreview").attr("src", "../Images/https://placehold.it/75x75");
}


function OnEditItemsChoice(ID) {
    debugger;
    $("#WindowItemChoicesAdd").modal('show');
    ClearItemChoicesFields();
    $("#AddItemChoicesTitle").text(getAdmLbl("adm_titleEditItemChoice", "Edit Item Choice"));
    GetItemChoiceDetails(ID);
}
function GetItemChoiceDetails(ID) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: { ID },
        url: "/Category/GetItemDetails",
        success: function (result) {

            var Item = result.dtItemDetails;
            //var selectedBranchs = result.dtselectedBranch;
            //var selectedExtraItems = result.dtselectedExtraItems;
            //var selectedComments = result.dtselectedComments;
            debugger;
            $("#hdnselectedItemChoicesId").val(ID);
            //$("#ItemPopupCategoryName").hide();
            //$("#ddItemCategory").show();

            //$("#ddItemCategory").val(Item[0].CAT_NUM);
            $("#txtItemChoiceNameEng").val(Item[0].ITEM_NAME);
            $("#txtItemChoiceNameAra").val(Item[0].ITEM_NAME_ARABIC);
            $("#txtItemChoicePrice").val(Item[0].PRICE);

            $("#chkShowItemsChoices").prop('checked', Item[0].ShowInTablet);
            //$("#chkShowItemsExtra").prop('checked', Item[0].IsActive);
            //$("#ExtraItemImagepreview").attr("src", "../Images/" + Item[0].IMAGENAME + "");
            //$("#hdnExtreaItemImageFileName").val(Item[0].IMAGENAME);

        }
    });
}

//Add/Edit Items
function SaveItemChoices() {
    debugger;
    var IsItemChoice = true

    if ($("#txtItemChoiceNameEng").val() == '') {
        $("#warningMessage").html(getAdmLbl("adm_msgInsertItemName", "Please insert item Name."));
        $('#warning').modal("toggle");
        return;
    }

    //if ($("#txtItemChoicePrice").val() == '') {
    //    $("#warningMessage").html(getAdmLbl("adm_msgInsertPrice", "Please insert price."));
    //    $('#warning').modal("toggle");
    //    return;
    //}

    var PackageData = new Array();
    var SelectedExtraItems = new Array();
    var selectedChoice = new Array();
    var SelectedComments = new Array();
    var Package = $("#ddItemBranch").val();

    if (Package != undefined) {
        if (Package.length > 0) {
            for (var i = 0; i < Package.length; i++) {
                var RowData = Package[i];
                PackageData[i] = { "BranchId": RowData };
            }
        }
    }

    var ImageName = $('#hdnImageFileName').val();
    var VideoName = $('#hdnVideoFileName').val();

    var IsShowInTablet = true;

    var ItemOpr = "AddItem";
    if ($('#txtItemID').val() != 0) {
        ItemOpr = "UpdateItem";
    }
    if ($('#hdnselectedItemChoicesId').val() != 0) {
        ItemOpr = "UpdateItem";
    }

    var value = {
        "ID": $('#hdnselectedItemChoicesId').val(),
        "CAT_NUM": ItemOpr == "UpdateItem" ? $("#ddItemCategory").val() : $('#ItemCategoryNumber').val(),
        "ITEM_NAME": $("#txtItemChoiceNameEng").val(),
        "ITEM_NAME_ARABIC": $("#txtItemChoiceNameAra").val(),

        "ItemNameRus": "",
        "ItemNameMan": "",
        //"PRICE": $("#txtItemChoicePrice").val(),
        "PRICE": 0,
        "IMAGENAME": "",

        "INGREDIENT": "",
        "INGREDIENT_ARABIC": "",
        "INGREDIENT_Rus": "",
        "INGREDIENT_Man": "",
        "ITEM_DESC_ENG": "",

        // "Seq_Num": $("#txtSequenceNo").val(),
        "Video": "",
        "ShowInTablet": IsShowInTablet,
        "BranchData": PackageData,
        "BrandID": $("#hdnBrandId").val(),
        "IsExtraItems": false,
        "Ischoice": true,
        "ExtraItems": SelectedExtraItems,
        "Comments": SelectedComments,
        "Choices": selectedChoice,
    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Category/" + ItemOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            IsItemUpdate = '1';

            $('#alert').modal("toggle");
            $("#message").html(result.Message);
            clearAllSelection();

            CategoryLock = true;//for Edit
            $("#WindowItemChoicesAdd").modal('hide');
            //BindCategoryItems($('#ItemCategoryNumber').val());
            //BindExtraItesmDdr();
            if ($('#hdnIsChoiceBind').val() == "true") {
                BindChoicesDdr();
            }
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}
function AddItemChoices() {
    $("#WindowItemChoicesAdd").modal('show');
    debugger;
    ClearItemChoicesFields();
}
function ClearItemChoicesFields() {
    //$('#ddBranch').val(null).trigger('change');
    //$('#ddBranch').val(null).trigger('change');
    debugger;

    $("#hdnselectedItemChoicesId").val("0");
    $("#AddItemChoicesTitle").text(getAdmLbl("adm_titleAddItemChoices", "Add Item Choice"));
    $("#ItemChoiceAddButton").text(getAdmLbl("adm_btnSave", "Save"));

    $("#txtItemChoiceNameEng").val('');
    $("#txtItemChoiceNameAra").val('');

    $("#txtIngEng").val('');
    $("#txtIngAra").val('');

    $("#txtItemChoicePrice").val('');
    $("#txtItemID").val(0);

    $("#chkShowItemsChoices").prop("checked", true);
    $("#ItemChoiceImagepreview").attr("src", "../Images/https://placehold.it/75x75");
}

function OnEditComment(obj, ID) {
    debugger;
    $("#WindowAddComment").modal('show');

    $("#txtCommentid").val(ID);
    $("#txtCommentNameEng").val($(obj).attr("data-val-Eng"));
    $("#txtCommentNameAra").val($(obj).attr("data-val-Arb"));

    $("#AddCommentTitle").text(getAdmLbl("adm_titleEditComment", "Edit Comment"));
    //GetCommentDetails(ID);
}
function GetItemDetails(ID) {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        data: { ID },
        url: "/Category/GetItemDetails",
        success: function (result) {
            debugger;
            var Item = result.dtItemDetails;
            var selectedBranchs = result.dtselectedBranch;
            var selectedExtraItems = result.dtselectedExtraItems;
            var selectedComments = result.dtselectedComments;
            var selectedChoice = result.dtselectedChoices;
            //var GroupModifierType = result.dtGroupModifierType;
            debugger;
            //$.each(result.dtItemDetails, function (data, value) {

            $("#AddItemTitle").text(getAdmLbl("adm_titleEditItem", "Edit Item"));
            $("#ItemAddButton").text(getAdmLbl("adm_btnSave", "Save"));

            $("#txtItemID").val(ID);

            $("#ItemPopupCategoryName").hide();
            $("#ddItemCategory").show();
            debugger;

            $("#ddItemCategory").val(Item[0].CAT_NUM);
            //$('#ddItemCategory').bsMultiSelect('update');
            $("#Imagepreview").attr("src", "../Images/" + Item[0].IMAGENAME + "");
            //$("#ddItemCategory").trigger("change");
            if (typeof enableSecondaryImages === 'function') { enableSecondaryImages(); }
            if (typeof loadSecondaryImages === 'function') { loadSecondaryImages(ID); }

            $("#txtItemNameEng").val(Item[0].ITEM_NAME);
            $("#txtItemNameAra").val(Item[0].ITEM_NAME_ARABIC);

            $("#txtIngEng").val(Item[0].INGREDIENT);
            $("#txtIngAra").val(Item[0].INGREDIENT_ARABIC);

            $("#txtPrice").val(Item[0].PRICE);

            $("#chkShowItems").prop('checked', Item[0].ShowInTablet);

            $("#ddItemBranch").html("");
            $.each(BranchList, function (data, value) {
                if (jQuery.inArray(value.BranchId, selectedBranchs) !== -1) {
                    $("#ddItemBranch").append($("<option selected></option>").val(value.BranchId).html(value.branchName));
                }
                else {
                    $("#ddItemBranch").append($("<option></option>").val(value.BranchId).html(value.branchName));
                }
            });
            $('#ddItemBranch').bsMultiSelect('update');

            if (ExtraItemsList != null) {
                $("#ddExtraItems").html("");
                $.each(ExtraItemsList, function (data, value) {
                    if (jQuery.inArray(value.ID, selectedExtraItems) !== -1) {
                        $("#ddExtraItems").append($("<option selected></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                    }
                    else {
                        $("#ddExtraItems").append($("<option></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                    }
                });
                $('#ddExtraItems').bsMultiSelect('update');
            }

            if (CommentsList != null) {
                $("#ddExtraComments").html("");
                $.each(CommentsList, function (data, value) {
                    if (jQuery.inArray(value.ID, selectedComments) !== -1) {
                        $("#ddExtraComments").append($("<option selected></option>").val(value.ID).html(value.comments_eng));
                    }
                    else {
                        $("#ddExtraComments").append($("<option></option>").val(value.ID).html(value.comments_eng));
                    }
                });
                $('#ddExtraComments').bsMultiSelect('update');
            }


            debugger;
            if (choicesList != null) {
                $("#ddChoices").html("");
                $.each(choicesList, function (data, value) {
                    if (jQuery.inArray(value.ID, selectedChoice) !== -1) {
                        $("#ddChoices").append($("<option selected></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                    }
                    else {
                        $("#ddChoices").append($("<option></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                    }
                });
                $('#ddChoices').bsMultiSelect('update');
            }

            debugger;
            $("#hdnImageFileName").val(Item[0].IMAGENAME);
            $("#hdnVideoFileName").val(Item[0].Video);
            $("#lblVideoMessage").html(Item[0].Video);

            if (AllergensList != null) {
                $.ajax({
                    type: "GET",
                    cache: false,
                    data: { ItemId: ID, BrandId: tempbrandid },
                    url: "/Category/GetItemAllergens",
                    success: function (allergenResult) {
                        var selectedAllergens = allergenResult.dtselectedAllergens || [];
                        $("#ddItemAllergens").html("");
                        $.each(AllergensList, function (data, value) {
                            if (jQuery.inArray(value.id, selectedAllergens) !== -1) {
                                $("#ddItemAllergens").append($("<option selected></option>").val(value.id).html(value.name));
                            }
                            else {
                                $("#ddItemAllergens").append($("<option></option>").val(value.id).html(value.name));
                            }
                        });
                        $('#ddItemAllergens').bsMultiSelect('update');
                    }
                });
            }
        }
    });
}
function BacktoCategoryList() {
    debugger;
    $('#hdnIsCategoryOrItemsSelected').val("Category");

    //left collapsible panel div
    $('#divExtraItemsList').hide();
    $('#divChoicesList').hide();
    $('#divCommentsList').hide();
    $('#divGroupModifierList').hide();
    $('#divAllergensList').hide();

    //if (parseInt($('#selectedSubCategoryId').val()) >= 0) {
    //    $("#divSubCategoryList").show();
    //}
    //else if (!($('#divSubCategoryList').is(':visible')) ) {
    //    $("#divSubCategoryList").show();
    //}
    if (isbackcounter == 2) {
        $("#divSubCategoryList").show();
    }
    else {
        selectedMainCategoryId = 0;
        $('#selectedSubCategoryId').val("0");
        $("#divCategoryList").show();
        $("#divSubCategoryList").hide();
    }
    isbackcounter = isbackcounter - 1;
    $("#divCategoryItemsList").hide();

    BindCategory(selectedMainCategoryId);

    clearAllSelection();
}

var isDragging = false;
function divmousedown() {
    isDragging = false;
}
function divmousemove() {
    isDragging = true;
}

function divmouseup(CAT_NUM, obj) {
    var wasDragging = isDragging;

    isDragging = false;
    if (!wasDragging) {
        //debugger;
        ////left collapsible panel div
        //$('#divExtraItemsList').show();
        //$('#divCommentsList').show();

        //var CategoryName = $(obj).attr("data-val");
        //$("#itemlistHeaderLabel").html('Items (' + CategoryName + ')');
        //OnCategoryClick(CAT_NUM);
    }
    //else {
    //    alert('drag');
    //}
}



////start code for Category drag drop update sequance number in db/////
$(".catDroppable").sortable({
    update: function (event, ui) {
        CatDropped();
    }
});
function CatDropped(event, ui) {
    Catlist = [];
    debugger;
    var seq = 0;
    $(".catDraggable").each(function () {
        seq = seq + 1;
        var id = $(this).attr("data-val-id");
        //var Name = $(this).attr("data-val");
        var details = {}
        details["CAT_NUM"] = id;
        details["SEQ_NUM"] = seq;
        Catlist.push(details);
    });
    debugger;
    updateCateSequance(Catlist);

}
function updateCateSequance(Catlist) {
    debugger;
    $.ajax({
        type: "Post",
        data: JSON.stringify(Catlist),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/Category/updateCategorySequance",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                //refresh();
            }
        }
    });
}

////End code for Category drag drop update sequance number in db//////


////start code for Items drag drop update sequance number in db/////
$(".catItemsDroppable").sortable({
    update: function (event, ui) {
        ItemsDropped();
    }
});
function ItemsDropped(event, ui) {
    Itemslist = [];
    debugger;
    var seq = 0;
    $(".catItemsDraggable").each(function () {
        seq = seq + 1;
        var id = $(this).attr("data-val-id");
        //var Name = $(this).attr("data-val");
        var details = {}
        details["ItemId"] = id;
        details["SEQ_NUM"] = seq;
        Itemslist.push(details);
    });
    debugger;
    updateItemsSequance(Itemslist);
}
function updateItemsSequance(Itemslist) {
    debugger;
    $.ajax({
        type: "Post",
        data: JSON.stringify(Itemslist),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        url: "/Category/updateItemsSequance",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                BindCategory();
                //refresh();
            }
        }
    });
}

////End code for Items drag drop update sequance number in db//////


function BindExtraItesmDdr() {
    debugger;
    $("#ddExtraItems").html("");
    $("#ulExtraItemsList").html("");
    $.ajax({
        type: "GET",
        cache: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetExtraItems",
        success: function (result) {
            debugger;
            ExtraItemsList = result.dtgrdItems;
            var strExtraItemsButton = '<li>\
                                <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowCategoryExtraItemAdd" onclick="AddExtraItem()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Extra Items</span></a>\
                            </li>'
            $("#ulExtraItemsList").append(strExtraItemsButton);
            $.each(result.dtgrdItems, function (data, value) {
                debugger;
                var ItemName = value.ITEM_NAME;
                $("#ddExtraItems").append($("<option></option>").val(value.ID).html(ItemName + " (" + value.PRICE + ")"));

                var strItemCommentsLi = ""
                //strItemCommentsLi = '<li>\
                //                <div class="custom-control custom-radio">\
                //                    <input type="radio" id="rdExtraItem_'+ value.ID + '"  data-val="' + value.ID + '" name="customRadio3" onchange="rdExtraItemCheck(this);" class="custom-control-input clrdExtraItem">\
                //                    <label class="custom-control-label" for="rdExtraItem_'+ value.ID + '">' + ItemName + ' (+ ' + value.Currency + '. ' + value.PRICE + ')</label>\
                //                    <a href="#" class="edit-btn" onclick="OnEditExtraItems(' + value.ID + ')";><img src="../Images/text-edit.svg" alt="" style="width:24px;"></a>\
                //                </div>\
                //            </li>';

                strItemCommentsLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="extraItem_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdExtraItem_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio3" onchange="rdExtraItemCheck(this);" class="custom-control-input clrdExtraItem">\
                                            <label class="custom-control-label" for="rdExtraItem_'+ value.ID + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="extraItem_td2">' + ItemName + '</td>\
                                    <td class="extraItem_td3" ><span class="price">' + value.PRICE + ' <em>' + value.Currency + '</em></span></td>\
                                    <td class="extraItem_td4" >\
                                        <a href="#" class="edit-btn" onclick="OnEditExtraItems(' + value.ID + ')";><img src="../images/text-edit.svg" alt=""></a>\
												</td>\
											</tr>	\
										</table>\
									</li>';
                $("#ulExtraItemsList").append(strItemCommentsLi);
            })
            $('#ddExtraItems').bsMultiSelect('update');

            //$('#ddExtraItems').trigger('change');
        }
    });
}
function BindChoicesDdr() {
    debugger;
    $("#ddChoices").html("");
    $("#ulChoicesList").html("");
    $.ajax({
        type: "GET",
        cache: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetChoices",
        success: function (result) {
            debugger;
            choicesList = result.dtgrdItems;

            var strChoicesButton = '<li>\
                                <a href="#" class="btn btn-icon btn-secondary  w-100 text-left" data-target="WindowItemChoicesAdd" onclick="AddItemChoices()"><img class="icon" src="../Images/add-b.svg" alt=""> <span>Add Item Choices</span></a>\
                            </li>'

            $("#ulChoicesList").append(strChoicesButton);
            $.each(result.dtgrdItems, function (data, value) {
                debugger;
                var ItemName = value.ITEM_NAME;
                $("#ddChoices").append($("<option></option>").val(value.ID).html(ItemName + " (" + value.PRICE + ")"));

                var strItemchoicesLi = ""
                strItemchoicesLi = '<li class="p-0 mb-2" >\
                        <table class="table">\
                            <tr>\
                                <td class="extraItem_td1">\
                                    <div class="custom-control custom-radio">\
                                        <input type="radio" id="rdChoiceItem_'+ value.ID + '" data-val="' + value.ID + '" name="customRadio4" onchange="rdChoiceItemCheck(this);" class="custom-control-input clrdChoiceItem">\
                                            <label class="custom-control-label" for="rdChoiceItem_'+ value.ID + '">\
                                            </label>\
									</div>\
								</td>\
                                    <td class="extraItem_td2">' + ItemName + '</td>\
                                    <td class="extraItem_td3" ><span class="price">' + value.PRICE + ' <em>' + value.Currency + '</em></span></td>\
                                    <td class="extraItem_td4" >\
                                        <a href="#" class="edit-btn" onclick="OnEditItemsChoice(' + value.ID + ')";><img src="../images/text-edit.svg" alt=""></a>\
												</td>\
											</tr>	\
										</table>\
									</li>';
                $("#ulChoicesList").append(strItemchoicesLi);
            })
            $('#ddChoices').bsMultiSelect('update');


            //$('#ddExtraItems').trigger('change');
        }
    });
}
function rdBranchCheck(obj) {
    debugger;
    clearAllSelection();
    $(obj).prop("checked", true);

    if (obj.checked) {
        var branchid = $(obj).attr("data-val");
        if ($('#hdnIsCategoryOrItemsSelected').val() == "Category") {
            $.ajax({
                type: "GET",
                cache: false,
                data: { BrandID: tempbrandid, BranchId: branchid },
                url: "/Category/GetCategoryBranchwise",
                success: function (result) {
                    if (result.Message == "Success") {
                        //var Branchs = result.dtgrdBranch;
                        debugger;
                        $(".clChkCategory").each(function () {
                            debugger;
                            $(this).prop("checked", false);
                        })
                        debugger
                        $.each(result.dtcate, function (data, value) {
                            $('#ChkCategory_' + value.CAT_NUM).prop("checked", true);
                        })
                    } else {
                        $("#warningMessage").html(result.Message);
                        $('#warning').modal("toggle");
                    }

                }
            });
        }
        else {  //items div visible
            $.ajax({
                type: "GET",
                cache: false,
                data: { BrandID: tempbrandid, BranchId: branchid },
                url: "/Category/GetItemsBranchwise",
                success: function (result) {
                    if (result.Message == "Success") {
                        debugger;
                        $(".clChkItem").each(function () {
                            debugger;
                            $(this).prop("checked", false);
                        })
                        debugger
                        $.each(result.dtItems, function (data, value) {
                            $('#ChkItem_' + value.ID).prop("checked", true);
                        })
                    } else {
                        $("#warningMessage").html(result.Message);
                        $('#warning').modal("toggle");
                    }
                }
            });
        }
    }
}
function chkBranchCheckStatus(obj) {
    debugger;
    //clearAllSelection();
    //$(obj).prop("checked", true);
    var status = 0;

    if (obj.checked) {
        status = 1
    }
    var branchid = $(obj).attr("data-val");
    $.ajax({
        type: "POST",
        cache: false,
        data: { BranchId: branchid, IsActive: status },
        url: "/Category/UpdateBranchStatus",
        success: function (result) {
            if (result.Message == "Success") {
                //if (status == 1) {
                //    $(obj).prop("checked", true);
                //}
                //else {
                //    $(obj).prop("checked", false);
                //}
            } else {
                $("#warningMessage").html(result.Message);
                $('#warning').modal("toggle");
            }

        }
    });
}
function UpdateBranchSequence(Id, SortingType) {
    debugger;
    //var value = {
    //    "BranchId": Id,
    //    //"Seq_Num": NewSeqNumber
    //    "SortingType": SortingType
    //};
    //var obji = { value: value }
    $.ajax({
        type: "POST",
        cache: false,
        //url: "/Category/UpdateGroupModifierSequence",
        url: "/Category/UpdateBranchSequence",
        //data: JSON.stringify(obji),
        data: { BranchId: Id, SortingType: SortingType },
        //contentType: "application/json; charset=utf-8",
        //dataType: "json",
        success: function (result) {
            debugger;
            BindBranchs(tempbrandid);
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}
function rdChoiceItemCheck(obj) {
    debugger;
    clearAllSelection();
    $(obj).prop("checked", true);

    if (obj.checked) {
        var ChoiceId = $(obj).attr("data-val");
        $.ajax({
            type: "GET",
            cache: false,
            data: { choiceId: ChoiceId },
            url: "/Category/GetChoicesItemsWise",
            success: function (result) {
                if (result.Message == "Success") {
                    $(".clChkItem").each(function () {
                        debugger;
                        $(this).prop("checked", false);
                    })
                    $.each(result.dtItemIds, function (data, value) {
                        $('#ChkItem_' + value.ID).prop("checked", true);
                    })
                } else {
                    $("#warningMessage").html(result.Message);
                    $('#warning').modal("toggle");
                }

            }
        });

    }
}
function rdExtraItemCheck(obj) {
    debugger;
    clearAllSelection();
    $(obj).prop("checked", true);

    if (obj.checked) {
        var extraItemId = $(obj).attr("data-val");
        $.ajax({
            type: "GET",
            cache: false,
            data: { ExtraItemId: extraItemId },
            url: "/Category/GetItemsExtraItemsWise",
            success: function (result) {
                if (result.Message == "Success") {
                    $(".clChkItem").each(function () {
                        debugger;
                        $(this).prop("checked", false);
                    })
                    $.each(result.dtItemIds, function (data, value) {
                        $('#ChkItem_' + value.ID).prop("checked", true);
                    })
                } else {
                    $("#warningMessage").html(result.Message);
                    $('#warning').modal("toggle");
                }

            }
        });

    }
}
function rdCommentCheck(obj) {
    debugger;
    clearAllSelection();
    $(obj).prop("checked", true);
    if (obj.checked) {
        var commentid = $(obj).attr("data-val");
        $.ajax({
            type: "GET",
            cache: false,
            data: { CommentId: commentid },
            url: "/Category/GetItemsCommentWise",
            success: function (result) {
                if (result.Message == "Success") {
                    debugger;
                    $(".clChkItem").each(function () {
                        debugger;
                        $(this).prop("checked", false);
                    })
                    debugger
                    $.each(result.dtItemIds, function (data, value) {
                        $('#ChkItem_' + value.ID).prop("checked", true);
                    })
                } else {
                    $("#warningMessage").html(result.Message);
                    $('#warning').modal("toggle");
                }
            }
        });
    }
}

function rdAllergenCheck(obj) {
    debugger;
    clearAllSelection();
    $(obj).prop("checked", true);
    if (obj.checked) {
        var allergenid = $(obj).attr("data-val");
        $.ajax({
            type: "GET",
            cache: false,
            data: { AllergenId: allergenid },
            url: "/Category/GetItemsAllergenWise",
            success: function (result) {
                if (result.Message == "Success") {
                    debugger;
                    $(".clChkItem").each(function () {
                        debugger;
                        $(this).prop("checked", false);
                    })
                    debugger
                    $.each(result.dtItemIds, function (data, value) {
                        $('#ChkItem_' + value.ID).prop("checked", true);
                    })
                } else {
                    $("#warningMessage").html(result.Message);
                    $('#warning').modal("toggle");
                }
            }
        });
    }
}

function BindGroupModifierTypesDdr() {
    debugger;
    $("#ddGroupModifierType").html("");
    $.ajax({
        type: "GET",
        cache: false,
        //data: { Brandid: tempbrandid },
        url: "/Category/GetGroupModifierTypes",
        success: function (result) {
            debugger;
            GroupModifierTypesList = result.dtGroupModifierTypes;
            $.each(result.dtGroupModifierTypes, function (data, value) {
                debugger;
                var TypeName_TMM = value.TypeName_TMM;
                $("#ddGroupModifierType").append($("<option></option>").val(value.ID).html(TypeName_TMM));
            })
            //$('#ddGroupModifierType').bsMultiSelect('update');
            $('#divCreateItemChoiceList').show();
            $('#divCreateItemExtraItemsList').hide();
        }
    });
}

function clearAllSelection() {
    debugger;
    $(".clRadioBranch").each(function () {
        $(this).prop("checked", false);
    })
    $(".clChkCategory").each(function () {
        $(this).prop("checked", false);
    })
    $(".clChkItem").each(function () {
        $(this).prop("checked", false);
    })
    $(".clrdChoiceItem").each(function () {
        $(this).prop("checked", false);
    })
    $(".clrdExtraItem").each(function () {
        $(this).prop("checked", false);
    })
    $(".clrdItemComment").each(function () {
        $(this).prop("checked", false);
    })
    $(".clrdAllergen").each(function () {
        $(this).prop("checked", false);
    })
}

function chkCategoryCheck(obj, Cat_num) {
    debugger;
    var selectedbranchId = $("input:radio.clRadioBranch:checked").val();
    var isSelected = false;
    if ($(obj).prop("checked") == true) {
        isSelected = true;
    }
    if (parseInt(selectedbranchId) > 0) {
        //var brandid = parseInt($('#hdnBrandId').val());
        $.ajax({
            type: "POST",
            cache: false,
            //BrandID set in layoutNew page
            data: { brandId: tempbrandid, branchId: selectedbranchId, cat_num: Cat_num, Isselected: isSelected },
            url: "/Category/UpdateCategoryBranchAssign",
            success: function (result) {
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    else {
        $("#warningMessage").html(getAdmLbl("adm_msgSelectBranch", "Please select Branch"));
        $('#warning').modal("toggle");
    }
}

function chkItemCheck(obj, ItemId) {
    debugger;
    var isSelected = false;
    if ($(obj).prop("checked") == true) {
        isSelected = true;
    }
    debugger;
    var selectedbranchId = $("input:radio.clRadioBranch:checked").attr("data-val");
    var selectedExtraItemId = $("input:radio.clrdExtraItem:checked").attr("data-val");
    var selectedCommentId = $("input:radio.clrdItemComment:checked").attr("data-val");
    var selectedChoiceId = $("input:radio.clrdChoiceItem:checked").attr("data-val");
    var selectedAllergenId = $("input:radio.clrdAllergen:checked").attr("data-val");


    if (parseInt(selectedbranchId) > 0) {
        $.ajax({
            type: "POST",
            cache: false,
            //BrandID set in layoutNew page
            data: { brandId: tempbrandid, branchId: selectedbranchId, ItemId: ItemId, Isselected: isSelected },
            url: "/Category/AssignItemToBranch",
            success: function (result) {
                debugger
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    if (parseInt(selectedChoiceId) > 0) {
        $.ajax({
            type: "POST",
            cache: false,
            data: { ChoiceId: selectedChoiceId, ItemId: ItemId, Isselected: isSelected },
            url: "/Category/AssignChoiceToItem",
            success: function (result) {
                debugger
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    if (parseInt(selectedExtraItemId) > 0) {
        $.ajax({
            type: "POST",
            cache: false,
            data: { ExtraItemId: selectedExtraItemId, ItemId: ItemId, Isselected: isSelected },
            url: "/Category/AssignExtraItemToItem",
            success: function (result) {
                debugger
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    if (parseInt(selectedCommentId) > 0) {
        $.ajax({
            type: "POST",
            cache: false,
            data: { Commentid: selectedCommentId, ItemId: ItemId, Isselected: isSelected },
            url: "/Category/AssignCommentToItem",
            success: function (result) {
                debugger
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    if (parseInt(selectedAllergenId) > 0) {
        $.ajax({
            type: "POST",
            cache: false,
            data: { AllergenId: selectedAllergenId, ItemId: ItemId, Isselected: isSelected },
            url: "/Category/AssignAllergen",
            success: function (result) {
                debugger
                if (result.Message != "Success") {
                    $(obj).attr("checked", false);
                }
            }
        });
    }
    //else {
    //    alert("Please select Branch");
    //}
}

function AddComment() {

    $("#WindowAddComment").modal('show');

    $("#AddExtraItemTitle").text(getAdmLbl("adm_titleAddItem", "Add Item"));
    $("#ExtraItemAddButton").text(getAdmLbl("adm_btnSave", "Save"));

    $("#txtCommentid").val(0);
    $("#txtCommentNameEng").val('');
    $("#txtCommentNameAra").val('');

}

function SaveComment() {
    var value = {
        "id": $('#txtCommentid').val(),
        "comments_eng": $('#txtCommentNameEng').val(),
        "comments_arb": $('#txtCommentNameAra').val(),
    };

    var obji = { value: value, Brandid: tempbrandid }

    $.ajax({
        type: "POST",
        url: "/Category/SaveComment",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            BindExtraComments();

            $("#message").html(result.Message);
            $('#alert').modal("toggle");

            $("#WindowAddComment").modal('hide');
        }
    });
}

function AddGroupModifier() {
    ClearGroupModifierForm();
    $("#WindowGroupModifierAdd").modal('show');
    BindGroupModifierTypesDdr();

    if (GroupModifierList != null) {
        bindGroupModifierGridview(GroupModifierList);
    }
    //ClearGroupModifierFields(0);
    //GetItemDetails(0);
    //$("#GroupModifierDeleteButton").show();
}


function SaveGroupModifier() {
    debugger;

    if ($("#txtGroupModifierNameEng").val() == '') {
        $("#warningMessage").html(getAdmLbl("adm_msgInsertItemName", "Please insert item Name."));
        $('#warning').modal("toggle");
        return;
    }

    if ($("#txtGroupModifierNameAra").val() == '') {
        $("#warningMessage").html(getAdmLbl("adm_msgInsertPrice", "Please insert price."));
        $('#warning').modal("toggle");
        return;
    }

    var ItemOpr = "AddGroupModifier";
    if ($('#hdnselectedGroupModifierId').val() != 0) {
        ItemOpr = "UpdateGroupModifier";
    }

    var value = {
        "ID": parseInt($('#hdnselectedGroupModifierId').val()) > 0 ? $('#hdnselectedGroupModifierId').val() : 0,
        "Type": $("#ddGroupModifierType").find(":selected").val(),
        "GroupNameEng": $("#txtGroupModifierNameEng").val(),
        "GroupNameArb": $("#txtGroupModifierNameAra").val(),
        "MinSelect": $("#txtGroupModifierMinSelect").val(),
        "MaxSelect": $("#txtGroupModifierMaxSelect").val()
    };

    var obji = { value: value, Brandid: tempbrandid }

    $.ajax({
        type: "POST",
        url: "/Category/" + ItemOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            $('#alert').modal("toggle");
            $("#message").html(result.Message);
            $("#WindowGroupModifierAdd").modal('hide');
            BindGroupModifier();
            ClearGroupModifierForm();
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}
function DeleteGroupModifier() {
    debugger;

    if (parseInt($('#hdnselectedGroupModifierId').val()) == 0) {
        $("#warningMessage").html(getAdmLbl("adm_msgSelectGroupModifier", "Please select Group Modifier."));
        $('#warning').modal("toggle");
        return;
    }
    var value = {
        "ID": parseInt($('#hdnselectedGroupModifierId').val()) > 0 ? $('#hdnselectedGroupModifierId').val() : 0,
    };
    var obji = { value: value }
    $.ajax({
        type: "POST",
        url: "/Category/DeleteGroupModifier",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            $('#alert').modal("toggle");
            $("#message").html(result.Message);
            //$("#WindowGroupModifierAdd").modal('hide');
            BindGroupModifier();
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}


function ChangePassword() {
    $("#WindowChangePassword").modal('hide');
    var UserId = $('#hdnUserId').val();
    var OldPassword = $('#txtOldPassword').val();
    var NewPassword = $('#txtNewPassword').val();


    if ($('#txtNewPassword').val() != $('#txtReTypePassword').val()) {
        $("#warningMessage").html(getAdmLbl("adm_msgPwdNotMatch", "New password and retype password not matched."));
        $('#warning').modal("toggle");
        return false;
    }
    //var value = {
    //    UserId: $('#hdnUserId').val(),
    //    OldPassword: $('#txtOldPassword').val(),
    //    NewPassword: $('#txtNewPassword').val(),
    //};

    //var obji = { value: value }

    debugger;
    $.ajax({
        type: "Post",
        url: "/Category/ChangePassword?UserId=" + $('#hdnUserId').val() + "&OldPassword=" + OldPassword + "&NewPassword=" + NewPassword,
        //url: "/Category/ChangePassword",
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        cache: false,
        //data: obji,
        //data: JSON.stringify(obji),
        //BrandID set in layoutNew page
        success: function (result) {
            debugger;
            if (result.message == "fail" && result.alert == "Wrong Password") {
                $("#warningMessage").html(getAdmLbl("adm_msgOldPwdIncorrect", "Old Password is incorrect."));
                $('#warning').modal("toggle");
            }
            else if (result.message == "fail") {
                $("#warningMessage").html(result.alert);
                $('#warning').modal("toggle");
            }
            else {

                $("#message").html(getAdmLbl("adm_msgPwdUpdated", "Password updated successfully."));
                $('#alert').modal("toggle");
            }
        }
    });
}

function AddBranch() {
    $("#WindowBranchAdd").modal('show');
    debugger;
    ClearBranchFields();
}
function ClearBranchFields() {

    $("#hdnAddEditBranchid").val("0");
    $("#AddBranchTitle").text(getAdmLbl("adm_titleAddBranch", "Add Branch"));
    $("#txtBranchName").val('');
    $("#txtBranchNameArabic").val('');
    $("#chkShowBranch").prop("checked", true);
}
function OnEditBranch(obj, ID) {
    debugger;
    $("#WindowBranchAdd").modal('show');
    ClearBranchFields();
    $("#hdnAddEditBranchid").val(ID);
    $("#txtBranchName").val($(obj).attr("data-val-Eng"));
    $("#txtBranchNameArabic").val($(obj).attr("data-val-Arb"));
    if ($(obj).attr("data-val-Active") == 'true') {
        $("#chkShowBranch").prop("checked", true);
    }
    else {
        $("#chkShowBranch").prop("checked", false);
    }

    $("#AddBranchTitle").text(getAdmLbl("adm_titleEditBranch", "Edit Branch"));


}
function SaveBranch() {

    debugger
    if ($('#txtBranchName').val() == "") {
        $("#txtBranchName").notify('Please insert Branch Name', { position: "right" });
        return;
    }
    // initially it is aasume that for main category the value for MainCateogry in DB is = so  MainCategory=0 
    // if it is sub category then the value of main category for this sub category is taken from ddMainCategory 

    var IsShow = false;
    if ($('#chkShowBranch').is(':checked')) {
        IsShow = true;
    }
    var value = {
        "BranchId": $('#hdnAddEditBranchid').val(),
        "branchName": $('#txtBranchName').val(),
        "BranchNameAra": $('#txtBranchNameArabic').val(),
        "IsActive": IsShow
    };

    var CatOpr = "SaveBranch";
    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/Category/" + CatOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            GetBrands();
            $("#message").html(result.Message);
            $('#alert').modal("toggle");

            $("#WindowBranchAdd").modal('hide');
        }
    });
}

jQuery(document).on('keydown', 'input.numericOnly', function (event) {
    if (event.shiftKey == true) {
        event.preventDefault();
    }

    if ((event.keyCode >= 48 && event.keyCode <= 57) ||
        (event.keyCode >= 96 && event.keyCode <= 105) ||
        event.keyCode == 8 || event.keyCode == 9 || event.keyCode == 37 ||
        event.keyCode == 39 || event.keyCode == 46 || event.keyCode == 190 || event.keyCode == 110) { } else {
        event.preventDefault();
    }
    if ($(this).val().indexOf('.') != -1 && (event.keyCode == 190 || event.keyCode == 110)) {
        event.preventDefault();
    }
    //if a decimal has been added, disable the "."-button
});


jQuery(document).on('keydown', 'input.numericOnlyNotDecimal', function (event) {
    if (event.shiftKey == true) {
        event.preventDefault();
    }

    if ((event.keyCode >= 48 && event.keyCode <= 57) ||
        (event.keyCode >= 96 && event.keyCode <= 105) ||
        event.keyCode == 8 || event.keyCode == 9 || event.keyCode == 37 ||
        event.keyCode == 39 || event.keyCode == 46 || event.keyCode == 190 || event.keyCode == 110) { } else {
        event.preventDefault();
    }
    //if ($(this).val().indexOf('.') != -1 && (event.keyCode == 190 || event.keyCode == 110)) {
    //    event.preventDefault();
    //}
    //if a decimal has been added, disable the "."-button
});

function BindMainCategory() {
    debugger;
    $.ajax({
        type: "GET",
        cache: false,
        async: false,
        data: { Brandid: tempbrandid },
        url: "/Category/GetMainCategoryList",
        success: function (result) {
            debugger;
            var MainCategoryList = result.dtMainCategory;
            debugger;
            $("#ddMainCategoryList").html("");
            $.each(MainCategoryList, function (data, value) {
                //if (CatItem[0].MainCategory == value.CAT_NUM) {
                //    $("#ddMainCategoryList").append($("<option selected></option>").val(value.CAT_NUM).html(value.CAT_NAME));
                //}
                //else {
                $("#ddMainCategoryList").append($("<option></option>").val(value.CAT_NUM).html(value.CAT_NAME));
                //}
            });
            //$('#divddrMainCategoryList').bsMultiSelect('update');
        }
    });
}


function chkIsSubCategoryChange(obj) {
    debugger;
    if ($(obj).is(":checked")) {
        $('#divddrMainCategoryList').show();
        //var returnVal = confirm("Are you sure?");
        //$(this).prop("checked", returnVal);
    }
    else {
        $('#divddrMainCategoryList').hide();
    }
}

function OnAssignGroupModifierClick(ID, obj) {
    debugger;
    $('#hdnGroupSelectMainItemId').val(ID);
    $('#destDivOfGroups').html("");
    BindAssignGroupModifier();
    $('#AssignGroupModifierTitle').html(getAdmLbl("adm_msgAssignGroupModifierPrefix", "Assign Group Modifier - ") + $(obj).attr("data-val"));

    //create default one group html
    //CopyGroupModifierRow();
    $("#WindowAssignGroupModifier").modal('show');
}

function bindGroupModifierGridview(dtGroupModifier) {
    debugger
    if ($.fn.DataTable.isDataTable('#grd_GroupModifierList')) {
        $('#grd_GroupModifierList').DataTable().destroy();
    }
    $('#grd_GroupModifierList tbody').empty();

    table_ReservationData = $('#grd_GroupModifierList');
    var tablekk = table_ReservationData.DataTable({
        "lengthChange": false,
        //responsive: true,
        //"pageLength": 5,
        //"lengthMenu": [[5, 10, 25, 50, -1], [5, 10, 25, 50, "All"]],
        data: dtGroupModifier,
        //ajax: {
        //    url: "/BranchReservation/GetReservationData?slotIds=" + selectedslotIds + "&FromDate=" + FromDate + "&ToDate=" + ToDate + "",
        //    type: 'POST',
        //    data: {
        //        //pagination: {
        //        //    perpage: 50,
        //        //},
        //    },
        //},
        columns: [
            {
                data: 'ID',
                className: 'displayNone'
            },
            {
                data: 'Seq_Num',
                className: 'displayNone'
            },
            {
                data: 'ID',
            },
            {
                data: 'GroupNameEng'
            },
            {
                data: 'GroupNameArb'
            },
            {
                data: 'TypeID',
                className: "displayNone"
            },
            {
                data: 'TypeName'
            },
            {
                data: 'MinSelect',
            },
            {
                data: 'MaxSelect',
            },
            //{
            //    data: 'id',
            //    responsivePriority: -1
            //},
        ],
        rowReorder: {
            dataSrc: 'ID'
        },
        deferRender: true,
        select: true,
        //rowReorder: true,
        //columnDefs: [
        //    { orderable: true, className: 'reorder', targets: 1 },
        //    { orderable: false, targets: '_all' }
        //],
        //"scrollY": "350px",
        //"scrollCollapse": true,
        "paging": false,
        "order": [[1, "asc"]],
        bFilter: false,
        bInfo: false,
        "ordering": false,
        columnDefs: [
            //{
            //    "targets": [0, 3],
            //    "visible": false
            //},
            //{
            //    width: '20px',
            //    targets: 6,
            //},
            //{ "width": "50px", "targets": 2 },
            {
                targets: 2,
                title: 'Sorting',
                orderable: false,
                render: function (data, type, full, meta) {
                    return '<button href="#" class="fa fa-angle-up btn btn-warning btnSortingModifier" title="Up" onclick="UpdateGroupModifierSequence(' + full.ID + ',\'up\');" style=""></button>' +
                        '<button href="#" class="fa fa-angle-down btn btn-warning btnSortingModifier" title="Down" onclick="UpdateGroupModifierSequence(' + full.ID + ',\'down\');" style="margin-left:7px;"></button>';
                },
                //'createdCell': function (td, cellData, rowData, row, col) {
                //    $(td).attr('nowrap', 'nowrap');
                //}
            },

        ],
        //select: {
        //    style: 'os',
        //    selector: 'td:first-child'
        //},

        //dom: 'Bfrtip',
        //buttons: [
        //    'copyHtml5',
        //    'excelHtml5',
        //    'csvHtml5',
        //    'pdfHtml5'
        //]
    });
    //$('#divGModifierCreateItemChoiceList').attr("style","width:100%;");


    //tablekk.on('row-reorder', function (e, diff, edit) {
    //    debugger
    //    //var result = 'Reorder started on row: ' + edit.triggerRow.data()["GroupNameEng"] + '<br>';
    //    var selectedid = edit.triggerRow.data()["ID"];
    //    var updatedSeq = 0;
    //    var executedId = 0;
    //    for (var i = 0, ien = diff.length; i < ien; i++) {
    //        //var rowData = tablekk.row(diff[i].node.rowIndex).data();
    //        if (diff[i].node.children[0].innerText == selectedid) {
    //            updatedSeq = diff[i].newPosition;

    //            //alert("Id" + selectedid + "\n" +
    //            //" newData " + diff[i].newData + "\n"+
    //            //" newPosition " + diff[i].newPosition + "\n"+
    //            //" oldData " + diff[i].oldData + "\n"+
    //            //    " oldPosition " + diff[i].oldPosition);

    //            //result += rowData["GroupNameEng"] + ' updated to be in position ' +
    //            //    diff[i].newData + ' (was ' + diff[i].oldData + ')<br>';
    //        }
    //    }

    //    //$('#result').html('Event result:<br> Id' + selectedid + " NewSeq" + updatedSeq);

    //    if (executedId == 0) {
    //        UpdateGroupModifierSequence(selectedid, updatedSeq);
    //        executedId = selectedid;
    //    }
    //    //alert('Id' + selectedid + " NewSeq" + updatedSeq);
    //});

    $('#grd_GroupModifierList tbody').on('click', 'tr', function () {
        $('#hdnselectedGroupModifierId').val($(this).find("td:eq(0)").text());
        $('#txtGroupModifierNameEng').val($(this).find("td:eq(3)").text());
        $('#txtGroupModifierNameAra').val($(this).find("td:eq(4)").text());
        $('#ddGroupModifierType').val($(this).find("td:eq(5)").text());
        $('#txtGroupModifierMinSelect').val($(this).find("td:eq(7)").text());
        $('#txtGroupModifierMaxSelect').val($(this).find("td:eq(8)").text());
        $('#GroupModifierAddButton').text(getAdmLbl("adm_btnUpdate", "Update"));
        $('#GroupModifierUpdateCancelButton').show();
        $('#GroupModifierDeleteButton').show();
    });
    //var table1 = $('#grd_GroupModifierList').DataTable();
    //myintVar = setInterval(function () {
    //    console.log(FromDate + ',' + ToDate);
    //    table1.ajax.reload();
    //}, 2000);
}

function CancelUpdateGroupModifier() {
    ClearGroupModifierForm();
}
function ClearGroupModifierForm() {
    $('#hdnselectedGroupModifierId').val("0");
    /*$("#AddGroupModifierTitle").text("Add Group Modifier");*/
    $('#ddGroupModifierType').val($("#ddGroupModifierType option:first").val());
    $('#GroupModifierAddButton').text(getAdmLbl("adm_btnSave", "Save"));
    $('#GroupModifierDeleteButton').hide();
    $('#GroupModifierUpdateCancelButton').hide();
    $("#txtGroupModifierNameEng").val("");
    $("#txtGroupModifierNameAra").val("");
    $("#txtGroupModifierMinSelect").val("0")
    $("#txtGroupModifierMaxSelect").val("0")
}

function OnEditGroupModifier(objbutton, Id) {
    ClearGroupModifierForm();
    $("#WindowGroupModifierAdd").modal('show');
    BindGroupModifierTypesDdr();
    $('#hdnselectedGroupModifierId').val(Id);

    if (GroupModifierList != null) {
        $.each(GroupModifierList, function (data, value) {
            if (value.ID == Id) {
                $('#hdnselectedGroupModifierId').val(Id);
                $('#ddGroupModifierType').val(value.TypeID);
                $('#txtGroupModifierNameEng').val(value.GroupNameEng);
                $('#txtGroupModifierNameAra').val(value.GroupNameArb);
                $('#txtGroupModifierMinSelect').val(value.MinSelect);
                $('#txtGroupModifierMaxSelect').val(value.MaxSelect);
                $('#GroupModifierAddButton').text(getAdmLbl("adm_btnUpdate", "Update"));
                $('#GroupModifierUpdateCancelButton').show();
                $('#GroupModifierDeleteButton').show();
            }
        })
    }
}

function UpdateGroupModifierSequence(Id, SortingType) {
    debugger;
    var value = {
        "ID": Id,
        //"Seq_Num": NewSeqNumber
        "SortingType": SortingType
    };
    var obji = { value: value }
    $.ajax({
        type: "POST",
        url: "/Category/UpdateGroupModifierSequence",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            //debugger;
            //$('#alert').modal("toggle");
            //$("#message").html(result.Message);
            //$("#WindowGroupModifierAdd").modal('hide');
            BindGroupModifier();
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}

//$('.drpGroupModifier').on('change', function () {
$(document).on('change', '.drpGroupModifier', function () {
    debugger;
    // 1 = Choice
    // 2 = Extra
    var controlid = $(this).attr("id");
    var rowindex = controlid.split('_')[1];
    $('#colChoiceExtra_' + rowindex + '').html("");
    if ($(this).find('option:selected').attr("data-TypeID") != "0") {
        if ($(this).find('option:selected').attr("data-TypeID") == "1") {
            //$('#ddGroupModifierChoices_' + rowindex + '').show();
            //$('#ddGroupModifierExtraItems_' + rowindex + '').hide();
            var strhtml = "<label>Select Choices</label>" +
                "<select id='ddGroupModifierChoices_" + rowindex + "' name='GroupModifierChoices[]' class='form-control MultiSelect' multiple='multiple'></select>";
            $('#colChoiceExtra_' + rowindex + '').html(strhtml);

            if (choicesList != null) {
                $('#ddGroupModifierChoices_' + rowindex + '').html("");
                $.each(choicesList, function (data, value) {
                    $('#ddGroupModifierChoices_' + rowindex + '').append($("<option></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                });
                $('#ddGroupModifierChoices_' + rowindex + '').bsMultiSelect('update');
            }
        }
        else {
            //$('#ddGroupModifierChoices_' + rowindex + '').hide();
            //$('#ddGroupModifierExtraItems_' + rowindex + '').show();
            var strhtml = "<label>Select Extras</label>" +
                "<select id='ddGroupModifierExtraItems_" + rowindex + "' name='GroupModifierExtraItems[]' class='form-control MultiSelect' multiple='multiple'></select>";
            $('#colChoiceExtra_' + rowindex + '').html(strhtml);

            if (ExtraItemsList != null) {
                $('#ddGroupModifierExtraItems_' + rowindex + '').html("");
                $.each(ExtraItemsList, function (data, value) {
                    $('#ddGroupModifierExtraItems_' + rowindex + '').append($("<option></option>").val(value.ID).html(value.ITEM_NAME + " (" + value.PRICE + ")"));
                });
                $('#ddGroupModifierExtraItems_' + rowindex + '').bsMultiSelect('update');
            }
        }
    }

    //var fileName = $(this).val();

    //var fileNameIndex = fileName.lastIndexOf("\\") + 1;
    //fileName = fileName.substr(fileNameIndex);
    ////replace the "Choose a file" label
    //$(this).next('.custom-file-label').html(fileName);
});

function CopyGroupModifierRow(cntrows) {
    debugger;
    var strhtml = $('#copyFormDiv').html();
    if (cntrows == 0) {
        cntrows = $('.drpGroupModifier').length + 1;
    }

    strhtml = strhtml.replace("colGroup", "colGroup_" + cntrows + "");
    strhtml = strhtml.replace("colChoiceExtra", "colChoiceExtra_" + cntrows + "");
    strhtml = strhtml.replace("colRemove", "colRemove_" + cntrows + "");

    strhtml = strhtml.replace("ddGroupModifierassignment", "ddGroupModifierassignment_" + cntrows + "");
    strhtml = strhtml.replace("ddGroupModifierChoices", "ddGroupModifierChoices_" + cntrows + "");
    strhtml = strhtml.replace("ddGroupModifierExtraItems", "ddGroupModifierExtraItems_" + cntrows + "");
    strhtml = strhtml.replace("btnRemoveRow", "btnRemoveRow_" + cntrows + "");
    $('#destDivOfGroups').append(strhtml);
}

function RemoveGroupRow(objbutton) {
    debugger;
    var controlid = $(objbutton).attr("id");
    var rowindex = controlid.split('_')[1];

    $('#colGroup_' + rowindex + '').remove();
    $('#colChoiceExtra_' + rowindex + '').remove();
    $('#colRemove_' + rowindex + '').remove();
}

function SaveAssignGroupModifier() {
    debugger;
    var groupAssignment;
    var seq = 1;
    var items = [];
    $('#destDivOfGroups .drpGroupModifier').each(function (data, value) {
        var selectedGroupid = $(this).val();
        var counterindex = $(this).attr("id");
        var rowindex = counterindex.split('_')[1];

        if ($('#ddGroupModifierChoices_' + rowindex + '').length > 0) {
            var Choices = $("#ddGroupModifierChoices_" + rowindex + "").val();
            if (Choices != undefined) {
                if (Choices.length > 0) {
                    for (var i = 0; i < Choices.length; i++) {
                        var RowData = Choices[i];
                        /*selectedChoice[i] = { "ID": RowData };*/
                        items.push({
                            'MainItemId': $('#hdnGroupSelectMainItemId').val(),
                            'GroupId': selectedGroupid,
                            'ItemID': RowData,
                            'Seq_Num': seq,
                        });
                        seq++;
                        //groupAssignment.push(items);
                    }
                }
            }
        }
        else {
            var ExtraItems = $("#ddGroupModifierExtraItems_" + rowindex + "").val();
            if (ExtraItems != undefined) {
                if (ExtraItems.length > 0) {
                    for (var i = 0; i < ExtraItems.length; i++) {
                        var RowData = ExtraItems[i];
                        //SelectedExtraItems[i] = { "ID": RowData };
                        items.push({
                            'MainItemId': $('#hdnGroupSelectMainItemId').val(),
                            'GroupId': selectedGroupid,
                            'ItemID': RowData,
                            'Seq_Num': seq,
                        });
                        seq++;
                        //groupAssignment.add(items);
                    }
                }
            }
        }

    });


    var ItemOpr = "AssignGroupModifier";
    var obji = {
        value: items,
        MainItemId: $('#hdnGroupSelectMainItemId').val()
    }
    $.ajax({
        type: "POST",
        url: "/Category/" + ItemOpr,
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            $('#alert').modal("toggle");
            $("#message").html(result.Message);
            $("#WindowAssignGroupModifier").modal('hide');
            //BindGroupModifier();
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}

function BindAssignGroupModifier() {
    debugger;
    var obji = { MainItemId: $('#hdnGroupSelectMainItemId').val() }
    $.ajax({
        type: "POST",
        url: "/Category/BindAssignGroupModifier",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {
            debugger;
            if (result.Message == "Success") {
                var Groupsdata = JSON.parse(result.Groupsdata);
                var GroupWiseItemsdata = JSON.parse(result.GroupWiseItemsdata);
                var cnt = 1;
                //if groupmofider assigned then bind list else default one display
                if (Groupsdata.length > 0) {
                    $(Groupsdata).each(function (data, value) {
                        CopyGroupModifierRow(cnt)
                        $('#ddGroupModifierassignment_' + cnt + '').val(value.GroupId);
                        //$('#ddGroupModifierassignment_' + cnt + '').trigger('change');

                        // 1 = Choice
                        // 2 = Extra
                        if (value.GroupTypeid == "1") {

                            var strhtml = "<label>Select Choices</label>" +
                                "<select id='ddGroupModifierChoices_" + cnt + "' name='GroupModifierChoices[]' class='form-control MultiSelect' multiple='multiple'></select>";
                            $('#colChoiceExtra_' + cnt + '').html(strhtml);

                            if (choicesList != null) {
                                $('#ddGroupModifierChoices_' + cnt + '').html("");
                                $.each(choicesList, function (d1, v1) {

                                    var selected = false;
                                    //check ItemId selected in this group or not
                                    $(GroupWiseItemsdata).each(function (d2, v2) {
                                        if (v2.GroupId == value.GroupId && v2.ItemID == v1.ID) {
                                            selected = true;
                                        }
                                    });

                                    if (selected) {
                                        $('#ddGroupModifierChoices_' + cnt + '').append($("<option selected></option>").val(v1.ID).html(v1.ITEM_NAME + " (" + v1.PRICE + ")"));
                                    }
                                    else {
                                        $('#ddGroupModifierChoices_' + cnt + '').append($("<option></option>").val(v1.ID).html(v1.ITEM_NAME + " (" + v1.PRICE + ")"));
                                    }
                                });
                                $('#ddGroupModifierChoices_' + cnt + '').bsMultiSelect('update');
                            }

                            //$('#ddGroupModifierassignment_' + cnt + '').val(value.ItemID);
                            //$('#ddGroupModifierassignment_' + cnt + '').trigger('change');
                        }
                        else {

                            var strhtml = "<label>Select Extras</label>" +
                                "<select id='ddGroupModifierExtraItems_" + cnt + "' name='GroupModifierExtraItems[]' class='form-control MultiSelect' multiple='multiple'></select>";
                            $('#colChoiceExtra_' + cnt + '').html(strhtml);

                            if (ExtraItemsList != null) {
                                $('#ddGroupModifierExtraItems_' + cnt + '').html("");
                                $.each(ExtraItemsList, function (d1, v1) {

                                    var selected = false;
                                    //check ItemId selected in this group or not
                                    $(GroupWiseItemsdata).each(function (d2, v2) {
                                        if (v2.GroupId == value.GroupId && v2.ItemID == v1.ID) {
                                            selected = true;
                                        }
                                    });

                                    if (selected) {
                                        $('#ddGroupModifierExtraItems_' + cnt + '').append($("<option selected></option>").val(v1.ID).html(v1.ITEM_NAME + " (" + v1.PRICE + ")"));
                                    }
                                    else {
                                        $('#ddGroupModifierExtraItems_' + cnt + '').append($("<option></option>").val(v1.ID).html(v1.ITEM_NAME + " (" + v1.PRICE + ")"));
                                    }
                                });
                                $('#ddGroupModifierExtraItems_' + cnt + '').bsMultiSelect('update');
                            }
                            //$('#ddGroupModifierChoices_' + cnt + '').val(value.ItemID);
                        }
                        cnt++;
                    });
                }
                else {
                    CopyGroupModifierRow(1);
                }

            }
            else if (result.Message == "NoData") {
                CopyGroupModifierRow(1);
            }
            else {
                $("#message").html(result.Message);
                $('#warning').modal("toggle");
            }
            //$('#alert').modal("toggle");
            //$("#message").html(result.Message);
            //$("#WindowAssignGroupModifier").modal('hide');
            //BindGroupModifier();
        },
        error: function (data, data2, data3) {
            $('#warning').modal("toggle");
        }
    });
}
function GroupModifierSeqclick(GroupModifierId, seqNum, SortingType) {
    debugger;
    //var updatedSeq = seqNum
    //if (SortingType == "up") {
    //    updatedSeq = seqNum + 1;
    //}
    //else {
    //    updatedSeq = seqNum- 1;
    //}
    UpdateGroupModifierSequence(GroupModifierId, updatedSeq);
}