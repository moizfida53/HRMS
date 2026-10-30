var itemnumdisplay;
var catnumdisplay;
var Cvalue;
var Ivalue;
var Themepreview = [];
var ThemeJson;
var fontITEMcolorvalue;
var fontCATcolorvalue;
var fontPRICEcolor;
var fontINGREDIENTcolor;
var Itemingredientdetails;
$(document).ready(function () {


    GetThemes();
    $("#category").hide();
    $("#itempage").hide();
    $("#clearbutton").hide();

    $("#itemdetailpage").hide();
    $("#mainhomepage").show();
    themesforview();
    uploadfile();
    collapse();

});

function collapse() {
    // Add minus icon for collapse element which is open by default
    $(".collapse.show").each(function () {
        $(this).prev(".card-header").find(".fa").addClass("fa-minus").removeClass("fa-plus");
    });

    // Toggle plus minus icon on show hide of collapse element
    $(".collapse").on('show.bs.collapse', function () {
        $(this).prev(".card-header").find(".fa").removeClass("fa-plus").addClass("fa-minus");
    }).on('hide.bs.collapse', function () {
        $(this).prev(".card-header").find(".fa").removeClass("fa-minus").addClass("fa-plus");
    });
}
function bindcategorylist() {

    $("#divbackbtn").show();
    $("#category").show();
    $("#mainhomepage").hide();
    $("#itemdetailpage").hide();
    $("#backbtn").attr('data-back', "main");

    $("#backbtn").show();
    getcategory();
}

function binditemlist(catid) {
    $("#category").hide();
    $("#itempage").show();
    $("#backbtn").show();
    $("#backbtn").attr('data-back', "categorypage");
    itemlist(catid);

}
function btnbackclick() {
    var redirectto = $("#backbtn").attr('data-back');
    if (redirectto == "main") {
        $("#category").hide();
        $("#mainhomepage").show();
        $("#backbtn").hide();
    }
    else if (redirectto == "categorypage") {
        $("#itempage").hide();
        $("#mainhomepage").hide();
        //$("#backbtn").show();
        $("#category").show();
        $("#compnylogo").show();
        $("#backbtn").attr('data-back', "main");
    }

    else if (redirectto == "items") {
        debugger
        $("#mainhomepage").hide();
        $("#category").hide();
        $("#compnylogo").show();
        //$("#backbtn").show();
        $("#itempage").show();
        $("#itemdetailpage").hide();
        $("#backbtn").attr('data-back', "categorypage");
    }
}

function itemlist(catid) {
    var obji = { CID: catid }
    $.ajax({
        type: "POST",
        data: obji,
        cache: false,
        url: "/image/getitem",
        success: function (result) {
            ThemeJson = result.dtItems;
            var head = '<div>' + result.dtItems["0"].CAT_NAME + '</div>';
            var items = "";

            if (itemnumdisplay == 3) {
                for (var key in result.dtItems) {


                    var out = ' <div class="col-sm-4 Itemimagediv">';
                    //   out += '<div class="container " >';
                    out += '<div class="overlaytopname" style="color: ' + fontITEMcolorvalue + ' ;font-size: 15px;"> <label> ' + result.dtItems[key].ITEM_NAME + ' </label> </div>';
                    out += '<img onclick=itemdetails(' + result.dtItems[key].CAT_NUM + ',id)  id=' + result.dtItems[key].ID + ' class="itemimage"src="../../images/' + result.dtItems[key].IMAGENAME + '">';
                    out += '<div class="overlay" style="color: ' + fontPRICEcolor + ' ;font-size: 13px;"><label>KD</label> <label> ' + result.dtItems[key].PRICE + '</label> </div>';
                    out += '</div>';
                    //   out += '</div>';
                    out += '</div>';


                    items = items + out
                }
            }
            else if (itemnumdisplay == 2) {
                for (var key in result.dtItems) {


                    var out = '  <div class="col-sm-6 Itemimagediv "  >';
                    //   out += '<div class="container " >';
                    out += '<div class="overlaytopname" style="color: ' + fontITEMcolorvalue + ' ;font-size: 15px;"> <label> ' + result.dtItems[key].ITEM_NAME + ' </label> </div>';
                    out += '<img onclick=itemdetails(' + result.dtItems[key].CAT_NUM + ',id)  id=' + result.dtItems[key].ID + ' class="image"src="../../images/' + result.dtItems[key].IMAGENAME + '">';
                    out += '<div class="overlay" style="color: ' + fontPRICEcolor + ' ;font-size: 13px;"><label>KD</label> <label> ' + result.dtItems[key].PRICE + '</label> </div>';
                    out += '</div>';
                    //   out += '</div>';
                    out += '</div>';


                    items = items + out
                }
            }
            else if (itemnumdisplay == 4) {
                for (var key in result.dtItems) {


                    var out = '  <div class=" col-sm-3 Itemimagediv"  >';
                    //   out += '<div class="container " >';
                    out += '<div class="overlaytopname" style="color: ' + fontITEMcolorvalue + ' ;font-size: 15px;"> <label> ' + result.dtItems[key].ITEM_NAME + ' </label> </div>';
                    out += '<img onclick=itemdetails(' + result.dtItems[key].CAT_NUM + ',id)  id=' + result.dtItems[key].ID + ' class="image"src="../../images/' + result.dtItems[key].IMAGENAME + '">';
                    out += '<div class="overlay" style="color: ' + fontPRICEcolor + ' ;font-size: 13px;"><label>KD</label> <label> ' + result.dtItems[key].PRICE + '</label> </div>';
                    out += '</div>';
                    //   out += '</div>';
                    out += '</div>';


                    items = items + out
                }
            }

            $("#divitemlist").html(items);
            $('#head').html(head);

        }
    });
}

function callscrolljs() {
    const slider = document.querySelector('.items');
    let isDown = false;
    let startX;
    let scrollLeft;

    slider.addEventListener('mousedown', (e) => {
        isDown = true;
        slider.classList.add('active');
        startX = e.pageX - slider.offsetLeft;
        scrollLeft = slider.scrollLeft;
    });
    slider.addEventListener('mouseleave', () => {
        isDown = false;
        slider.classList.remove('active');
    });
    slider.addEventListener('mouseup', () => {
        isDown = false;
        slider.classList.remove('active');
    });
    slider.addEventListener('mousemove', (e) => {
        if (!isDown) return;
        e.preventDefault();
        const x = e.pageX - slider.offsetLeft;
        const walk = (x - startX) * 3; //scroll-fast
        slider.scrollLeft = scrollLeft - walk;
        console.log(walk);
    });
}

function itemdetails(catID, itemid) {
    // $("#itemdetailpage").show();
    $("#itempage").hide();
    $("#compnylogo").hide();
    $("#backbtn").attr('data-back', "items");
    {
        var obji =
            {
                CID: catID,
                ItemID: itemid

            }
        $.ajax({
            type: "POST",
            data: obji,
            cache: false,
            url: "/image/getitemwithselectedimage",
            success: function (result) {
                Itemingredientdetails = result.dtItems["0"].INGREDIENT;
                ThemeJson = result.dtItems;
                var head = '<center><img class="itemdetailimage"  src="/images/' + result.dtItems["0"].IMAGENAME + '"  id=' + result.dtItems["0"].ID + '></center>';
                $('#firstimage').html(head);

                var ItemN = '<div style=" color:' + fontITEMcolorvalue + '; font-size: 18px;margin-left: 25px;margin-top: 15px;"> <label>' + result.dtItems["0"].ITEM_NAME + '</label></div>';
                $('#itemname').html(ItemN);

                var itemP = '<div  style="color:' + fontPRICEcolor + '; font-size: 13px;margin-left: 25px;"><label>KD' + result.dtItems["0"].PRICE + '</label></div>';
                $('#itemprice').html(itemP);


                var ItemING = '<div   style="height:69px;color:' + fontINGREDIENTcolor + ';width: auto;margin-left: 25px;margin-top:0px; width: 550px;">' + result.dtItems["0"].INGREDIENT + '</div>';
                $('#ingrident').html(ItemING);

                repeadteditems(catID);
                $("#itemdetailpage").show();
            }

        });
    }


}

function repeadteditems(catid) {
    var obji = { CID: catid }
    $.ajax({
        type: "POST",
        data: obji,
        cache: false,
        url: "/image/getitem",
        success: function (result) {
            ThemeJson = result.dtItems;

            var itemslist = "";
            
           
                for (var key in result.dtItems) {


                    // var out = '  <div style="margin-left:14px;float:left;width: 170px;height:230px;">';
                    var out = '  <div class="item item1">';
                    out += ' <div class="img-container" ><img class="imagescrool"   src="../../images/' + result.dtItems[key].IMAGENAME + '"onclick=itemdetails(' + result.dtItems[key].CAT_NUM + ',id)  id=' + result.dtItems[key].ID + '> </div>';
                    out += '<div style="font-size: 14px;text-align:center;"><label>' + result.dtItems[key].ITEM_NAME + '</label></div>';
                    out += '</div>';





                    itemslist = itemslist + out;
                }

            


            $("#allitems").html(itemslist);
            callscrolljs();
        }
    });
}



function GetThemes() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/image/GetTheme",
        success: function (result) {
            ThemeJson = result.dtgrdBrand;

            //document.getElementById("btneng").style.backgroundColor = result.dtgrdBrand["0"].englishButton;
            document.getElementById("btnarb").style.backgroundColor = result.dtgrdBrand["0"].englishButton;

            document.getElementById("btncntr").style.backgroundColor = result.dtgrdBrand["0"].englishButton;
            document.getElementById("backbtn").style.backgroundColor = result.dtgrdBrand["0"].englishButton;

            fontCATcolorvalue = result.dtgrdBrand["0"].FontColor;

            fontITEMcolorvalue = result.dtgrdBrand["0"].FontColorItemName;

            fontPRICEcolor = result.dtgrdBrand["0"].FontColorPrice;


            fontINGREDIENTcolor = result.dtgrdBrand["0"].FontColorIngName;


            document.getElementById("detailitempageimage").style.backgroundColor = result.dtgrdBrand["0"].itemBackgroundColor;

            var homeimage = result.dtgrdBrand["0"].popUpBackground;
            var bkgimage = result.dtgrdBrand["0"].homeScreen;
            //var itembkimage = result.dtgrdBrand["0"].setting;
            catnumdisplay = result.dtgrdBrand["0"].leftArrow;
            itemnumdisplay = result.dtgrdBrand["0"].leftBottom;

            if (homeimage == "") {
                $(".homepage").css("background-image", "url()");
            }
            else {
                var p = "../../images/" + homeimage;
                // var imageUrl = "images/sky.jpg";

                $(".homepage").css("background-image", "url(" + p + ")");
            }
            //-------------------------------------------------------------------------------------------------------------------------

            if (bkgimage == "") {
                $(".bkimag").css("background-image", "url()");
            }
            else {
                var l = "../../images/" + bkgimage;
                // var imageUrl = "images/sky.jpg";

                $(".bkimag").css("background-image", "url(" + l + ")");
            }

            //-------------------------------------------------------------------------------------------------------------------------
            //if (itembkimage == "") {
            //    $(".itembkimg").css("background-image", "url()");
            //}
            //else {
            //    var m = "../../images/" + itembkimage;
            //    // var imageUrl = "images/sky.jpg";

            //    $(".itembkimg").css("background-image", "url(" + m + ")");
            //}
        }
    });
}

function getcategory() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/image/getcategorylist",
        success: function (result) {
            ThemeJson = result.categorydata;

            var category = "";
            if (catnumdisplay == 3) {
                for (var key in result.categorydata) {

                    var out = '<div class="col-sm-4 catimage">';

                    out += '<img onclick=binditemlist(id)  id=' + result.categorydata[key].CAT_NUM + ' class="image"src="../../images/' + result.categorydata[key].Imagename + '">';
                    out += '<div id="catnamefont" style="color:' + fontCATcolorvalue + ';font-size: 15px; " class="overlaytop"><label><b> ' + result.categorydata[key].CAT_NAME + '</b> </label> </div>';

                    out += '</div>';



                    category = category + out
                }
            }
            else if (catnumdisplay == 4) {
                for (var key in result.categorydata) {

                    var out = '  <div class="col-sm-3 catimage" >';
                    //  out += '<div class="container">';
                    out += '<img onclick=binditemlist(id)  id=' + result.categorydata[key].CAT_NUM + ' class="image"src="../../images/' + result.categorydata[key].Imagename + '">';
                    out += '<div id="catnamefont" style="color:' + fontCATcolorvalue + ';font-size: 15px; " class="overlaytop"><label><b> ' + result.categorydata[key].CAT_NAME + '</b> </label> </div>';
                    //    out += '</div>';
                    out += '</div>';



                    category = category + out
                }
            }
            else if (catnumdisplay == 2) {
                for (var key in result.categorydata) {

                    var out = '  <div class="col-sm-6 catimage" >';
                    //  out += '<div class="container">';
                    out += '<img onclick=binditemlist(id)  id=' + result.categorydata[key].CAT_NUM + ' class="image"src="../../images/' + result.categorydata[key].Imagename + '">';
                    out += '<div id="catnamefont" style="color:' + fontCATcolorvalue + ';font-size: 15px; " class="overlaytop"><label><b> ' + result.categorydata[key].CAT_NAME + '</b> </label> </div>';
                    //    out += '</div>';
                    out += '</div>';



                    category = category + out
                }
            }
            $("#divcatlist").html(category);

        }
    });
}



/////////////////////////////////////////////////////////////////theme page JS/////////////////////////////////////////////////////

function themesforview() {

    $.ajax({
        type: "GET",
        cache: false,
        url: "/image/GetTheme",
        success: function (result) {
            ThemeJson = result.dtgrdBrand;


            $('#lblimgitemcat').text(result.dtgrdBrand["0"].homeScreen);
            $('#lblHomescreen').text(result.dtgrdBrand["0"].popUpBackground);

            CreateImage("#imgitemcatimage", result.dtgrdBrand["0"].homeScreen)
            CreateImage("#imgHomescreen", result.dtgrdBrand["0"].popUpBackground)
            themeID = result.dtgrdBrand["0"].themeID;
            $('#colourbutton').val(result.dtgrdBrand["0"].englishButton);
            $('#Catfontcolor').val(result.dtgrdBrand["0"].FontColor);
            $('#Itemfontcolor').val(result.dtgrdBrand["0"].FontColorItemName);
            $('#ItemBackgroundcolor').val(result.dtgrdBrand["0"].itemBackgroundColor);

            $('#fontPRICEcolor').val(result.dtgrdBrand["0"].FontColorPrice);
            $('#fontIngredientcolor').val(result.dtgrdBrand["0"].FontColorIngName);


            $('#catvalue').val(result.dtgrdBrand["0"].leftArrow);
            $('#Itemvalue').val(result.dtgrdBrand["0"].leftBottom);

        },

    })
}

function CreateImage(imageid, image) {
    try {
        var p = "../../images/" + image;
        var t;
        t = "<div> <img src=" + p + "  width='180' height='130' />  </div>";
        $(imageid).html(t);
    } catch (err) {
    }

}




function uploadfile() {
    $('#jqxitemcatimage,#jqxHomescreen').jqxFileUpload({
        width: 300,
        height: 140,
        uploadUrl: '/Items/UploadFile',
        fileInputName: 'fileToUpload',
        browseTemplate: 'success',
        multipleFilesUpload: false,
        localization: { browseButton: 'Select Image', uploadButton: 'Upload Image', cancelButton: 'Cancel' }
    });

    $('#jqxitemcatimage').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblimgitemcat").html(args.file);
        CreateImage("#imgitemcatimage", fileName)
    });
    $('#jqxHomescreen').on('uploadEnd', function (event) {
        var args = event.args;
        var fileName = args.file;
        $("#lblHomescreen").html(args.file);
        CreateImage("#imgHomescreen", fileName)
    });
}



function Updatetheme() {

    if ($("#lblimgitemcat").html() == '') {

        alert("Background image not found for category and image");
        return;
    }
    if ($("#lblHomescreen").html() == '') {

        alert("Background home");
        return;
    }


    var e = document.getElementById("catvalue");
    Cvalue = e.options[e.selectedIndex].value;
    // var text = e.options[e.selectedIndex].text;
    var b = document.getElementById("Itemvalue");
    Ivalue = b.options[b.selectedIndex].value;
    // var text = b.options[e.selectedIndex].text;



    var value = {
        "leftArrow": Cvalue,
        "leftBottom": Ivalue,
        "englishButton": $("#colourbutton").val(),
        "popUpBackground": $('#lblHomescreen').html(),
        "homeScreen": $('#lblimgitemcat').html(),
        "themeID": themeID,
        "FontColor": $("#Catfontcolor").val(),
        "FontColorItemName": $("#Itemfontcolor").val(),
        "itemBackgroundColor": $("#ItemBackgroundcolor").val(),
        "FontColorPrice": $("#fontPRICEcolor").val(),
        "FontColorIngName": $("#fontIngredientcolor").val(),



    };

    var obji = { value: value }

    $.ajax({
        type: "POST",
        url: "/image/EditTheme",
        data: JSON.stringify(obji),
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function (result) {

            alert(result.Message)
            // alert("theme updated successfully done !!")
        }
    });
}



function preview() {

    GetThemespreview();
    $("#category").hide();
    $("#itempage").hide();

    $("#itemdetailpage").hide();
    $("#mainhomepage").show();

    $("#clearbutton").show('1000');
    // $("#previewbutton").hide('1000');

}


function clearpreview() {
    GetThemes();
    $("#category").hide();
    $("#itempage").hide();

    $("#itemdetailpage").hide();
    $("#mainhomepage").show();

    $("#clearbutton").hide('1000');
    //  $("#previewbutton").show('1000');
    themesforview();
   
    // Add minus icon for collapse element which is open by default
    $(".collapse.in.show").each(function () {
        debugger
        $(this).removeClass("in");
        $(this).removeClass("show");
    });

    $(".fa.fa-minus").each(function () {
        debugger
        $(this).removeClass("fa-minus");
        $(this).addClass("fa-plus");
    });


}



function GetThemespreview() {


    var e = document.getElementById("catvalue");
    Cvalue = e.options[e.selectedIndex].value;
    // var text = e.options[e.selectedIndex].text;
    var b = document.getElementById("Itemvalue");
    Ivalue = b.options[b.selectedIndex].value;
    // var text = b.options[e.selectedIndex].text;

    Themepreview = {
        "leftArrow": Cvalue,
        "leftBottom": Ivalue,
        "englishButton": $("#colourbutton").val(),
        "popUpBackground": $('#lblHomescreen').html(),
        "homeScreen": $('#lblimgitemcat').html(),
        "themeID": themeID,
        "FontColor": $("#Catfontcolor").val(),
        "FontColorItemName": $("#Itemfontcolor").val(),
        "itemBackgroundColor": $("#ItemBackgroundcolor").val(),
        "FontColorPrice": $("#fontPRICEcolor").val(),
        "FontColorIngName": $("#fontIngredientcolor").val(),

    };


    console.log(Themepreview);

    document.getElementById("btnarb").style.backgroundColor = Themepreview.englishButton;

    document.getElementById("btncntr").style.backgroundColor = Themepreview.englishButton;

    document.getElementById("backbtn").style.backgroundColor = Themepreview.englishButton;

    fontCATcolorvalue = Themepreview.FontColor;

    fontITEMcolorvalue = Themepreview.FontColorItemName;

    fontPRICEcolor = Themepreview.FontColorPrice;


    fontINGREDIENTcolor = Themepreview.FontColorIngName;


    document.getElementById("detailitempageimage").style.backgroundColor = Themepreview.itemBackgroundColor;

    var homeimage = Themepreview.popUpBackground;
    var bkgimage = Themepreview.homeScreen;
    //var itembkimage = result.dtgrdBrand["0"].setting;
    catnumdisplay = Themepreview.leftArrow;
    itemnumdisplay = Themepreview.leftBottom;

    if (homeimage == "") {
        $(".homepage").css("background-image", "url()");
    }
    else {
        var p = "../../images/" + homeimage;
        // var imageUrl = "images/sky.jpg";

        $(".homepage").css("background-image", "url(" + p + ")");
    }
    //    //-------------------------------------------------------------------------------------------------------------------------

    if (bkgimage == "") {
        $(".bkimag").css("background-image", "url()");
    }
    else {
        var l = "../../images/" + bkgimage;
        // var imageUrl = "images/sky.jpg";

        $(".bkimag").css("background-image", "url(" + l + ")");
    }

}