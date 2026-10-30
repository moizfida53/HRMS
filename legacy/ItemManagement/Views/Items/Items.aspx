<%@ Page Title="" Language="C#" MasterPageFile="../../Views/Shared/MasterPage.Master" Inherits="System.Web.Mvc.ViewPage<dynamic>" %>

<asp:Content ID="Content1" ContentPlaceHolderID="TitleContent" runat="server">
    Items
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="MainContent" runat="server">

    <link href="../../Content/jqx.base.css" rel="stylesheet" type="text/css" />
    <meta name="viewport" content="width=device-width" />
    <meta name="viewport" content="initial-scale=0, maximum-scale=0, user-scalable=no" />



    <script src="../../Scripts/jquery-1.11.1.min.js" type="text/javascript"></script>


    <script src="../../Scripts/jqxcore.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxbuttons.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxdropdownbutton.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxcheckbox.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxmenu.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxlistbox.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxdropdownlist.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxtabs.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxscrollbar.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.selection.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.filter.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.columnsresize.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.pager.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxdata.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.sort.js" type="text/javascript"></script>
    <script src="../../Scripts/jsrender.min.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxfileupload.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxgrid.edit.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxcombobox.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxwindow.js" type="text/javascript"></script>

    <link href="../../Content/jqx.ui-redmond.css" rel="stylesheet" type="text/css" />
    <link href="../../css/jqx.office.css" rel="stylesheet" type="text/css" />
    <script src="../../Scripts/bootstrap-number-input.js" type="text/javascript"></script>
    <link href="../../css/bootstrap.min.css" rel="stylesheet" type="text/css" />
    <link href="../../css/wan-spinner.css" rel="stylesheet" type="text/css" />
    <script src="../../Scripts/wan-spinner.js" type="text/javascript"></script>
    <link href="../../css/bootstrap.vertical-tabs.css" rel="stylesheet" type="text/css" />
    <script src="../../Scripts/notify.js"></script>
    <script src="../../Scripts/bootstrap.min.js" type="text/javascript"></script>
    <link href="../../css/sweetalert.css" rel="stylesheet" type="text/css" />
    <script src="../../Scripts/RowSorter.js"></script>
    <script src="../../Scripts/sweetalert.min.js" type="text/javascript"></script>
    <script src="../../Scripts/jqxtooltip.js" type="text/javascript"></script>

    <%--start inserted by km for feedbackreport--%>
    <%--<script src="../../vendor/jquery/jquery.min.js"></script>--%>
    <%--<script src="../../vendor/pivot/jquery-1.8.3.min.js"></script>--%>
    <%--<link href="../../css/Pivot/c3.min.css" rel="stylesheet" />--%>
    <script src="../../vendor/Pivot/pivot.js"></script>
    <link href="../../css/Pivot/pivot.css" rel="stylesheet" />
    <%--<script src="../../vendor/Pivot/c3_renderers.js"></script>--%>
    <%--<script src="../../vendor/Pivot/nrecopivottableext.js"></script>--%>
    <%--<link href="../../css/Pivot/nrecopivottableext.css" rel="stylesheet" />--%>
    <%--end inserted by km for feedbackreport--%>
    <style>
        #tbldragdropCategory {
            width: 96%;
        }

        .flexbox-container {
            display: inline-flex;
            flex-direction: column;
        }

        .jqx-notification-success, .jqx-success {
            color: #ffffff !important;
            text-shadow: 0 -1px 0 rgba(0, 0, 0, 0.25) !important;
            background-color: #f9ba4c !important;
            background-repeat: repeat-x !important;
            background-image: linear-gradient(to bottom, #f89406, #f89406) !important;
            border-left-color: #f89406 !important;
            border-right-color: #f89406 !important;
            border-top-color: #f89406 !important;
            border-bottom-color: #f89406 !important;
        }

        .category {
            border-radius: 43px 0px 43px 0px;
            -moz-border-radius: 43px 0px 43px 0px;
            -webkit-border-radius: 43px 0px 43px 0px;
            border: 0px solid #000000;
            background-color: #edeaea;
            padding-left: 50px;
            padding-top: 20px;
        }

        .items {
            border-radius: 32px 32px 32px 32px;
            -moz-border-radius: 32px 32px 32px 32px;
            -webkit-border-radius: 32px 32px 32px 32px;
            border: 2px solid #000000;
            position: relative;
            float: left;
        }

        .buttoncolor {
            height: 60px;
            width: 60px;
        }
    </style>



    <div id='jqxWidget'>
        <div id='jqxTabs'>
            <ul>
                <li id="ItemsTab" style="color: black">Item Management</li>
                <li id="AdminTab" style="color: black;">User Management</li>
                <li id="FeedBackTab" style="color: black;">Customer FeedBack</li>
                <%-- <li id="FeedBackReport" style="color: black;">FeedBack Report</li>--%>
                <li id="ThemesTab" style="color: black;">Themes</li>
                <li id="SlideShowsTab" style="color: black;">Slide Shows</li>
                <li id="WebSlideShowsTab" style="color: black;">Web Slide Shows</li>
                <li id="PromotionTab" style="color: black; display: none">Manage Promotion</li>
            </ul>
            <div id="Tab1">
                <div>

                    <div class="category">
                        <div>
                            <input id="txtItemID" type="hidden" />
                        </div>
                        <div>
                            <table class="tableCSS">
                                <tr>
                                    <td style="text-align: right">Brand</td>
                                    <td>
                                        <p id="ddBrands" class="selectCSS"></p>
                                    </td>
                                    <td>
                                        <input id="btnBrands" type="button" value="+" class="addCSS" onclick="OpenBrand()" />
                                    </td>
                                </tr>
                                <tr>
                                    <td style="text-align: right">Category</td>
                                    <td>
                                        <p id="ddCategory" class="selectCSS"></p>
                                    </td>
                                    <td>
                                        <input id="btnCategory" type="button" value="+" class="addCSS" onclick="OpenCategory()" />
                                    </td>
                                    <td><b>IsExtra Items:</b>  &nbsp 
                                        <input type="checkbox" name="chkIsExtraItems" id="chkIsExtraItems" class="item" value="false" />
                                    </td>
                                </tr>
                                <tr class="noBorder">
                                    <td style="text-align: right">Item Name (English): 
                                    </td>
                                    <td>
                                        <input id="txtItemNameEng" type="text" />
                                    </td>
                                    <td style="text-align: right">Item Name (Arabic):
                                    </td>
                                    <td>
                                        <input id="txtItemNameAra" type="text" />
                                    </td>
                                </tr>
                                <tr class="nonExtra">
                                    <td style="text-align: right">Ingredient (English):
                                    </td>
                                    <td>
                                        <textarea id="txtIngEng" name="Text1" cols="28" rows="3"></textarea>
                                    </td>
                                    <td style="text-align: right">Ingredient (Arabic): 
                                    </td>
                                    <td>
                                        <textarea id="txtIngAra" name="Text1" cols="28" rows="3"></textarea>
                                    </td>
                                </tr>
                                <tr id="itemNameLanguage" class="noBorder">
                                    <td style="text-align: right">Item Name (Russian): 
                                    </td>
                                    <td>
                                        <input id="txtItemNameRus" type="text" />
                                    </td>
                                    <td style="text-align: right">Item Name (Mandarin):
                                    </td>
                                    <td>
                                        <input id="txtItemNameMan" type="text" />
                                    </td>
                                </tr>
                                <tr id="Languageingr">
                                    <td style="text-align: right">Ingredient (Russian):
                                    </td>
                                    <td>
                                        <textarea id="txtIngRus" name="Text1" cols="28" rows="3"></textarea>
                                    </td>
                                    <td style="text-align: right">Ingredient (Mandarin): 
                                    </td>
                                    <td>
                                        <textarea id="txtIngMan" name="Text1" cols="28" rows="3"></textarea>
                                    </td>
                                </tr>
                                <tr>
                                    <td style="text-align: right">Price: 
                                    </td>
                                    <td>
                                        <input id="txtPrice" type="text" />
                                    </td>
                                    <td style="text-align: right; display: none;">Description:
                                    </td>
                                    <td style="display: none;">
                                        <input id="txtDescription" type="text" />
                                    </td>
                                </tr>
                                <tr class="nonExtra">
                                    <td style="text-align: right">&nbsp Extra Items :&nbsp </td>
                                    <td>
                                        <div id="ddExtraItems" class="selectCSS">
                                        </div>
                                    </td>
                                    <td style="text-align: right">Comments</td>
                                    <td>
                                        <p id="ddExtraComments" class="selectCSS"></p>
                                    </td>
                                    <td>
                                        <input id="btnAddExtraComments" type="button" value="+" class="addCSS" onclick="OpenExtraComments()" />
                                    </td>
                                </tr>
                                <tr >
                                    <td style="text-align: right">&nbsp Select Image : &nbsp </td>
                                    <td>
                                        <div id="jqxFileUpload">
                                        </div>
                                    </td>
                                    <td class="nonExtra" style="text-align: right">Assign Branch</td>

                                    <td class="nonExtra">
                                        <p id="ddBranchs" class="selectCSS"></p>
                                    </td>
                                    <td class="nonExtra">
                                        <input id="btnBranches" type="button" value="+" class="addCSS" onclick="OpenBranch()" />
                                    </td>
                                </tr>

                                <tr class="nonExtra">
                                    <td style="text-align: right">&nbsp Select Video : &nbsp </td>
                                    <td>
                                        <div id="jqxVideoUpload">
                                        </div>
                                    </td>
                                    <td style="text-align: right">Video Name <b id="lblVideo"></b>
                                    </td>
                                </tr>

                                <tr>
                                    <td style="text-align: right"> Image:&nbsp 
                                    </td>
                                    <td>
                                        <div id="img">
                                        </div>
                                        <div id="lblFileName" style="font-size: 15px;">
                                        </div>
                                    </td>

                                    <td class="nonExtra" style="text-align: right">Show Items
                                    </td>

                                    <td class="nonExtra"><span style="margin-left: 40px">Yes<input type="radio" name="isItem" id="radio5" class="item" checked value="true" />
                                    </span>
                                        <span style="margin-left: 40px">No
                                            <input type="radio" name="isItem" id="radio6" class="item" value="false" />
                                        </span>
                                    </td>
                                </tr>
                                <tr>
                                </tr>
                                <tr>
                                    <td valign="middle" align="center" colspan="4">
                                        <input id="btnAddItem" type="button" value="Add" onclick="AddItem()" class="addCSS" />

                                        <input id="btnUpdateItem" type="button" value="Update" onclick="UpdateItem()"
                                            class="addCSS" />

                                        <input id="btnDeleteItem" type="button" value="Delete" onclick="DeleteItem()"
                                            class="addCSS" />

                                        <input id="btnCancleItem" type="button" value="Cancel" onclick="btnClearItem()"
                                            class="addCSS" />
                                    </td>
                                </tr>
                            </table>
                        </div>

                    </div>



                </div>
                <div id="ItemsTable">
                </div>
            </div>
            <div id="Tab2">

                <div class="category">
                    <table class="tableCSS" style="height: 150px" cellpadding="10px" cellspacing="10px">
                        <tr>
                            <td>
                                <input id="txtWaiterID" type="hidden" />
                                User Name:
                            </td>
                            <td>
                                <input id="txtWaiterName" type="text" />
                            </td>
                            <td>&nbsp;</td>
                            <td>Assign User Name:
                            </td>
                            <td>
                                <input id="txtUserName" type="text" />
                            </td>
                            <td>&nbsp;</td>


                        </tr>
                        <tr>
                            <td>Assign Password:
                            </td>
                            <td>
                                <input id="txtPassword" type="text" />
                            </td>
                            <td></td>
                            <td>Select Role
                            </td>
                            <td>
                                <div id="ddRole" />
                            </td>
                        </tr>
                        <tr>
                        </tr>
                        <tr>
                            <td>
                                <div id="lblCallCenter">Select Brands:</div>
                            </td>
                            <td colspan="6">
                                <div id="ddBrands3" />
                            </td>
                        </tr>
                    </table>
                    <div style="padding-bottom: 20px; padding-right: 20px;">
                        <table class="tableCSS">

                            <tr>

                                <td style="vertical-align: middle">
                                    <input id="btnAddWaiter" class="addCSS" type="button" value="Add" onclick="AddWaiter()" />
                                </td>
                                <td style="vertical-align: middle">
                                    <input id="btnUpdateWaiter" class="addCSS" type="button" value="Update" onclick="UpdateWaiter()" />
                                </td>
                                <td style="vertical-align: middle">
                                    <input id="btnDeleteWaiter" class="addCSS" type="button" value="Delete" onclick="DeleteWaiter()" />
                                </td>
                                <td style="vertical-align: middle">
                                    <input id="btnCancleWaiter" class="addCSS" type="button" value="Cancel" onclick="ClearWaiter()" />
                                </td>
                            </tr>
                        </table>
                    </div>
                </div>




                <div id="grdWaiter"></div>
            </div>
            <div id="Tab3">

                <div class="category">

                    <div class="form-group center col-12">
                        <table class="tableCSS">
                            <tr>
                                <td style="text-align: right">Enter Question</td>

                                <td>
                                    <input name="Enter Question" placeholder="Enter Question" class="form-control" type="text" id="txtQuestion">
                                </td>


                            </tr>
                            <tr>
                                <td style="text-align: right">Enter Question Sequence</td>

                                <td>
                                    <input name="Enter Question Sequence" placeholder="Enter Sequence" class="form-control" type="text" id="txtQuestionSeq">
                                </td>


                            </tr>
                            <tr>
                                <td style="text-align: right">Type Of Question</td>

                                <td>
                                    <p id="ddType" class="selectCSS"></p>
                                </td>
                            </tr>
                            <tr>
                                <td style="text-align: right">Select  Brand</td>

                                <td>
                                    <p id="ddBrandsLayout" class="selectCSS"></p>
                                </td>
                            </tr>

                        </table>

                        <div id="grdFeedBackLayout"></div>
                        <div style="padding-bottom: 20px; padding-right: 20px;">
                            <table class="tableCSS">

                                <tr>

                                    <td style="vertical-align: middle">
                                        <input id="btnAddFeedBackLayout" class="addCSS" type="button" value="Add" onclick="AddFeedBackLayout()" />
                                    </td>
                                    <td style="vertical-align: middle">
                                        <input id="btnUpdateFeedBackLayout" class="addCSS" type="button" value="Update" onclick="UpdateFeedBackLayout()" />
                                    </td>
                                    <td style="vertical-align: middle">
                                        <input id="btnDeleteFeedBackLayout" class="addCSS" type="button" value="Delete" onclick="DeleteFeedBackLayout()" />
                                    </td>
                                    <td style="vertical-align: middle">
                                        <input id="btnCancleFeedBackLayout" class="addCSS" type="button" value="Cancel" onclick="ClearFeedBackLayout()" />
                                    </td>

                                    <td style="vertical-align: middle">
                                        <input id="FeedBackLayoutID" type="text" style="display: none" />
                                    </td>
                                </tr>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
            <%--  <div id="Tab7">
                <div class="category">
                     <div class="row">
                <div class="col-2">
                    Select Start Date
                </div>
                <div class="col-3">
                    <div id="cmbStartDate">
                        <input id="StartDate" type="date" value="button" />

                    </div>
                </div>
            </div>

            <div class="row">
                <div class="col-2">
                    Select End Date
                </div>
                <div class="col-3">
                    <div id="cmbEndDate">
                        <input id="EndDate" type="date" data-date-format="yyyy-MM-dd 23:59:59" value="button" />
                    </div>
                </div>
            </div>

            <div class="row col-2 align-centre">

                <button id="add" type="button" class="addCSS" onclick="Search()">
                    <span class="glyphicon glyphicon-plus"></span> Search
                </button>
                <button id="Export" type="button" class="addCSS" onclick="exportPivotToExcel('output','Pivot Data');">
                    <span class="glyphicon glyphicon-plus"></span> Exporttotexcel
                </button>

            </div>

            <div id="output" style="margin:10px"></div>
                </div>                                            
            </div>--%>
            <div id="Tab4">
                <div>

                    <div class="category">

                        <div>
                            <input id="txtthemeID" type="hidden" />

                        </div>
                        <div>
                            <table class="tableCSS">
                                <tr>
                                    <td style="text-align: right">Brand</td>

                                    <td>
                                        <p id="ddBrandsThemes" class="selectCSS"></p>
                                    </td>
                                    <td>
                                </tr>

                                <tr class="noBorder">
                                    <td style="text-align: right">Theme Name: 
                                    </td>
                                    <td>
                                        <input id="txtThemeName" type="text" />
                                    </td>

                                </tr>

                                <%-- Category Active--%>
                                <tr>
                                    <td style="text-align: right;"><b>Category Active Image :</b>  </td>
                                    <td>
                                        <div id="jqxCategoryActive">
                                            <div id="imgCategoryActive" style="float: left; margin-right: 10px;">
                                            </div>
                                            <b id="lblCategoryActive" style="display: none"></b>
                                        </div>
                                    </td>

                                    <td style="text-align: right;">&nbsp <b>Category InActive Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxCategoryInActive">
                                            <div id="imgCategoryInActive" style="float: left; margin-right: 10px;"></div>
                                            <b id="lblCategoryInActive" style="display: none"></b>
                                        </div>
                                    </td>
                                </tr>
                                <%-- LeftArrow HomeScreen--%>
                                <tr>


                                    <td style="text-align: right;"><b>HomeScreen Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxHomeScreen">
                                            <div id="imgHomeScreen" style="float: left; margin-right: 10px;">
                                            </div>
                                            <b id="lblHomeScreen" style="display: none"></b>
                                        </div>
                                    </td>

                                    <td style="text-align: right;">&nbsp <b>Pop-Up Background Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxPopUpBackground">
                                            <div id="imgPopUpBackground" style="float: left; margin-right: 10px;">
                                            </div>
                                            <b id="lblPopUpBackground" style="display: none"></b>
                                        </div>

                                    </td>
                                </tr>
                                <%-- EnglishButton and arabic button--%>
                                <tr>


                                    <td>&nbsp <b>English Button Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxEnglishButton">
                                            <div id="imgEnglishButton" style="float: left; margin-right: 10px;">
                                            </div>
                                            <b id="lblEnglishButton" style="display: none"></b>
                                        </div>
                                    </td>
                                    <td style="text-align: right">&nbsp <b>Arabic Button Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxArabicButton">
                                            <div id="imgArabicButton" style="float: left; margin-right: 10px;">
                                            </div>
                                            <p id="lblArabicButton" style="display: none"></p>
                                        </div>
                                    </td>

                                </tr>
                                <%-- Pop up background Image--%>
                                <tr>
                                    <td style="text-align: right;">&nbsp <b>Close Button Image :</b> &nbsp </td>
                                    <td>
                                        <div id="jqxCloseButton">
                                            <div id="imgCloseButton" style="float: left; margin-right: 10px;">
                                            </div>
                                            <p id="lbCloseButton" style="display: none"></p>
                                        </div>
                                    </td>

                                    <td style="text-align: right;">&nbsp <b>Category Font Color :</b>   </td>
                                    <td>
                                        <input type="color" id="clrFontColor" class="buttoncolor" /></td>
                                </tr>
                                <tr>
                                    <td style="text-align: right;"><b>Font Color for  Item Name :</b>   </td>
                                    <td>
                                        <input type="color" id="clrFontColorItemName" class="buttoncolor" /></td>
                                    <td style="text-align: right;"><b>Font Color for  Ingredeint :</b>   </td>
                                    <td>
                                        <input type="color" id="clrFontColorIngName" class="buttoncolor" /></td>
                                </tr>

                                <tr>
                                    <td style="text-align: right;"><b>Font Color for Price :</b>   </td>
                                    <td>
                                        <input type="color" id="clrFontColorPrice" class="buttoncolor" /></td>
                                    <td style="text-align: right;"><b>Item Background Color :</b>   </td>
                                    <td>
                                        <input type="color" id="clrItemBackgroundColor" class="buttoncolor" /></td>
                                </tr>


                                <tr>
                                    <td valign="middle" align="center" colspan="4">
                                        <input id="btnAddtheme" type="button" value="Add" onclick="Addtheme()" class="addCSS" />

                                        <input id="btnUpdatetheme" type="button" value="Update" onclick="Updatetheme()"
                                            class="addCSS" />
                                        <input id="btnCancletheme" type="button" value="Cancel" onclick="Cleartheme()"
                                            class="addCSS" />
                                    </td>
                                </tr>
                            </table>
                        </div>

                    </div>



                </div>

                <div id="grdthemes" style="width: 96%"></div>

                <div style="text-align: center;">
                    <input style="margin: 20px; 0" type="button" id='jqxButton' value="Show the themes" class="addCSS" />
                </div>


            </div>
            <div id="Tab5">
                <div>

                    <div class="category">

                        <div id="ddSlideShowBrand">
                        </div>
                        <div>
                            <table class="tableCSS">


                                <%-- Category Active--%>
                                <tr>
                                    <td style="text-align: right;"><b>Slide Show Image:</b>  </td>
                                    <td>
                                        <div id="jqxSlideShows">

                                            <b id="lblSlideShows" style="display: none"></b>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </div>
                        <div id="SlideShowsTable"></div>
                        <div id="imgSlideShows" class="tableCSS"></div>
                    </div>
                </div>
            </div>
            <div id="Tab6">
                <div>

                    <div class="category">
                        <div id="ddWebSlideShowBrand">
                        </div>

                        <div>
                            <table class="tableCSS">


                                <%-- Category Active--%>
                                <tr>
                                    <td style="text-align: right;"><b>Slide Show Image:</b>  </td>
                                    <td>
                                        <div id="jqxWebSlideShows">

                                            <b id="lblWebSlideShows" style="display: none"></b>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </div>
                        <div id="WebSlideShowsTable"></div>
                        <div id="imgWebSlideShows" class="tableCSS"></div>
                    </div>
                </div>
            </div>
            <div id="Tab8">
                <div>

                    <div class="category">

                        <div id="ddPromtionBrand">
                        </div>
                        <div style="margin-top: 10px; margin-bottom: 10px;">
                            Show Promotion :
                            <input id="chkIsBrandPromotionShow" type="checkbox" onchange="chkBrandPromotionShowChange();" />
                        </div>
                        <div>
                            <table class="tableCSS">


                                <%-- Category Active--%>
                                <tr>
                                    <td style="text-align: right;"><b>Slide Show Image:</b>  </td>
                                    <td>
                                        <div id="jqxPromotion">

                                            <b id="lblPromotion" style="display: none"></b>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </div>
                        <div id="PromotionTable"></div>
                        <div id="imgPromotion" class="tableCSS"></div>
                    </div>
                </div>
            </div>

        </div>



        <%--------------------------------------------------------------Window Category------------------------------------------------------------%>


        <div id="Window">
            <div>
                <b>CATEGORY</b>
            </div>
            <div>
                <table class="tableCSS">
                    <tr style="display: none">
                        <td>
                            <input id="txtCategoryNo" type="hidden" />
                        </td>
                    </tr>
                    <tr>
                        <td>Select Brand</td>
                        <td>
                            <p id="ddBrands2" class="selectCSS"></p>
                        </td>
                    </tr>
                    <tr>
                        <td>Assign Branch</td>
                        <td>
                            <p id="ddBranchsCategoryView" class="selectCSS"></p>
                        </td>
                    </tr>
                    <tr>
                        <td>Category Name:</td>
                        <td>
                            <input id="txtCategoryName" type="text" />
                        </td>
                    </tr>
                    <tr>
                        <td>Category Name (Arabic):</td>
                        <td>
                            <input id="txtCategoryNameAra" type="text" />
                        </td>
                    </tr>
                    <tr style="display: none;">
                        <td>Sequence Number:</td>
                        <td>
                            <input id="txtSeqNo" type="text" />
                        </td>
                    </tr>
                    <tr>
                        <td>Show Category </td>
                        <td>
                            <span style="margin-left: 40px">Yes<input type="radio" name="isImage" id="radio3" class="image" checked value="true" />
                            </span>
                            <span style="margin-left: 40px">No
                                <input type="radio" name="isImage" id="radio4" class="image" value="false" />
                            </span>
                        </td>
                    </tr>
                </table>
                <div style="padding: 12px;">
                    <div class="row" style="display: none;">
                        <div class="col-lg-6">
                            <b>Is Sub Category </b>
                            <span style="margin-left: 20px">Yes<input type="radio" name="isSubCategory" id="subCategory" class="image" value="false" onclick="ShowMainCategory()" />
                            </span>
                            <span style="margin-left: 20px">No
                                    <input type="radio" name="isSubCategory" id="mainCategory" class="image" checked value="true" onclick="hideMainCategory()" />
                            </span>
                        </div>

                        <div class="col-lg-6" id="mainCatDisplay" style="display: none;">
                            <b>Select Main Category </b>
                            <div style="margin-left: 10px">
                                <div id="ddMainCategory"></div>
                            </div>
                        </div>
                    </div>



                    <div id="CatLanguage" style="display: none;">
                        <div>
                            <b>Category Name (Mandarian):</b>
                            <input id="txtCategoryNameMan" type="text" />
                        </div>

                        <div style="display: none;">
                            <b>Category Name (Russian):</b>
                            <input id="txtCategoryNameRus" type="text" />
                        </div>
                    </div>

                </div>
                <div style="padding-bottom: 20px; padding-right: 20px;">
                    <table class="tableCSS">
                        <tr>
                            <td valign="middle" height="80px">
                                <input id="btnAddCategory" type="button" value="Add" onclick="AddCategory()" class="addCSS" />
                            </td>
                            <td valign="middle" height="80px">
                                <input id="btnUpdateCategory" type="button" value="Update" onclick="UpdateCategory()"
                                    class="addCSS" />
                            </td>
                            <td valign="middle" height="80px">
                                <input id="btnDeleteCategory" type="button" value="Delete" onclick="DeleteCategory()"
                                    class="addCSS" />
                            </td>
                            <td valign="middle" height="80px">
                                <input id="btnCancleCategory" type="button" value="Cancel" onclick="ClearCategory()"
                                    class="addCSS " />
                            </td>
                        </tr>
                    </table>
                    <div id="grdCategory"></div>
                    <div id="CategoryTable"></div>

                </div>

            </div>
        </div>

        <%--------------------------------------------------------------Window Brands------------------------------------------------------------%>

        <div id="WinBrand">
            <div>
                <b>Edit Brand</b>
            </div>
            <div>
                <table class="tableCSS">
                    <tr style="display: none">
                        <td>
                            <input type="text" id="BrandID" />
                        </td>
                    </tr>
                    <tr>

                        <td>Brand Name
                        </td>
                        <td>
                            <input id="txtBrandName" type="text" />
                        </td>
                    </tr>
                    <tr>
                        <td>Brand Name Arabic
                        </td>
                        <td>
                            <input id="txtBrandNameAr" type="text" />
                        </td>
                    </tr>
                    <tr>
                        <td>Brand Sequence
                        </td>
                        <td>
                            <input id="txtBrandSeq" type="text" />
                        </td>
                    </tr>
                    <tr id="chklang">
                        <td>Languages
                        </td>
                        <td>
                            <input type="checkbox" id="chkRussian" name="Languages" class="L1" value="1">
                            Russian
                        </td>
                        <td>
                            <input type="checkbox" id="chkMandarin" name="Languages" class="L1" value="1">
                            Mandarin
                        </td>
                    </tr>
                    <tr>
                        <td>Select Theme
                        </td>
                        <td>
                            <div id="ddTheme" class="selectCSS"></div>
                        </td>
                    </tr>
                    <tr>
                        <td>Url
                        </td>
                        <td>
                            <input id="txtBrandurl" type="text" />
                        </td>
                    </tr>
                    <%-- <tr id="copyBrandtr">

                        <td>Select Copy Brand</td>

                        <td>
                            <p id="ddBrandsCopy" class="selectCSS"></p>
                        </td>
                    </tr>--%>

                    <tr style="display: none;">
                        <td style="text-align: right"><b>Brand Image:</b>  &nbsp 
                        </td>
                        <td>
                            <div id="imgBrand">
                            </div>
                            <div id="lblFileNameBrand" style="font-size: 15px;">
                            </div>
                        </td>
                    </tr>
                    <tr style="display: none;">
                        <td style="text-align: right">&nbsp <b>Select Image :</b> &nbsp </td>
                        <td>
                            <div id="jqxFileUploadBrand"></div>
                        </td>

                    </tr>

                </table>

                <div style="padding-bottom: 20px; padding-right: 20px;">
                    <table class="tableCSS">
                        <tr>
                            <td style="vertical-align: middle;">
                                <input id="btnAddBrand" type="button" value="Add" onclick="AddBrand()" class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnUpdateBrand" type="button" value="Update" onclick="UpdateBrand()"
                                    class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnDeleteBrand" type="button" value="Delete" onclick="DeleteBrand()"
                                    class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnCancleBrand" type="button" value="Cancel" onclick="ClearBrand()"
                                    class="addCSS" />
                            </td>
                        </tr>
                    </table>
                    <div id="grdBrand"></div>
                </div>
            </div>

        </div>

        <%--------------------------------------------------------------Window Branchs------------------------------------------------------------%>

        <div id="WinBranch">
            <div>
                <b>Add/Edit Branch</b>
            </div>
            <div>
                <table class="tableCSS">
                    <tr style="display: none">
                        <td>
                            <input type="text" id="BranchID" />
                        </td>
                    </tr>
                    <tr>
                        <td>Assign Brand</td>

                        <td>
                            <p id="ddBrandsAddBranchPopup" class="selectCSS"></p>
                        </td>
                        <%-- <td>
                                        <input id="btnBrands" type="button" value="+" class="addCSS" onclick="OpenBrand()" />
                                    </td>--%>
                    </tr>
                    <tr>

                        <td>Branch Name
                        </td>
                        <td>
                            <input id="txtBranchName" type="text" />
                        </td>
                    </tr>
                    <tr>
                        <td>Branch Name Arabic
                        </td>
                        <td>
                            <input id="txtBranchNameAr" type="text" />
                        </td>
                    </tr>
                    <tr id="copyBranchtr">
                        <td>Select Copy Branch</td>
                        <td>
                            <p id="ddBranchsCopy" class="selectCSS"></p>
                        </td>
                    </tr>

                </table>

                <div style="padding-bottom: 20px; padding-right: 20px;">
                    <table class="tableCSS">
                        <tr>
                            <td style="vertical-align: middle;">
                                <input id="btnAddBranch" type="button" value="Add" onclick="AddBranch()" class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnUpdateBranch" type="button" value="Update" onclick="UpdateBranch()"
                                    class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnDeleteBranch" type="button" value="Delete" onclick="DeleteBranch()"
                                    class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnCancleBranch" type="button" value="Cancel" onclick="ClearBranch()"
                                    class="addCSS" />
                            </td>
                        </tr>
                    </table>
                    <div id="grdBranch"></div>
                </div>
            </div>

        </div>


        <%--------------------------------------------------------------Window Generate QRcode------------------------------------------------------------%>

        <div id="WinGenerateQRcode">
            <div>
                <b>Generate QRcode</b>
            </div>
            <div>
                <table class="tableCSS">
                    <tr>
                        <td>Select Brand
                        </td>
                        <td>
                            <div id="ddGenerateQrBrands" class="selectCSS"></div>
                        </td>
                    </tr>
                    <tr>
                        <td>Select Branch
                        </td>
                        <td>
                            <div id="ddGenerateQrBranchList" class="selectCSS"></div>
                        </td>
                    </tr>
                </table>

                <div style="padding-bottom: 20px; padding-right: 20px;">
                    <table class="tableCSS">
                        <tr>
                            <td style="vertical-align: middle;">
                                <input id="btnGenerateQr" type="button" value="Generate" onclick="GenerateQrcode()" class="addCSS" />
                            </td>
                            <td style="vertical-align: middle">
                                <input id="btnClearQr" type="button" value="Clear" onclick="ClearQrcode()"
                                    class="addCSS" />
                            </td>
                        </tr>
                    </table>
                    <div id="divQRCodeImage"></div>
                    <div id="divBranchURL"></div>
                </div>
            </div>

        </div>
    </div>

    <script src="../../vendor/pivot/jquery.csv-0.71.min.js"></script>
    <script src="../../vendor/pivot/jquery-ui-1.9.2.custom.min.js"></script>
    <script src="../../vendor/pivot/c3.min.js"></script>
    <script src="../../vendor/pivot/d3.min.js"></script>
    <script src="../../MainJs/Items.js"></script>
    <script src="../../MainJs/PivotJS.js"></script>


</asp:Content>
