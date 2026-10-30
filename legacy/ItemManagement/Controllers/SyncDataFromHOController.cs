using Jar.Helper;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Web.Http;
using System.Web.Mvc;

namespace Jar.Controllers
{
    public class SyncDataFromHOController : Controller
    {

        public string CheckBranchUrl()
        {
            return "Success";
        }
        [System.Web.Http.HttpPost]
        public string SyncBrandDbCategory([FromBody] string Dataset, string BranchURL)
        {
            try
            {
                List<SyncCategory> value = JsonConvert.DeserializeObject<List<SyncCategory>>(Dataset);
                DataTable dt = DB.ToDataTable(value);
                SqlParameter[] spa1 ={
                                           new SqlParameter(){
                                           ParameterName="@dttblCategorySync",
                                            Value =dt
                                        }
                    };
                DB.ExecuteStoredProcDataSet("sp_InsertIntoBrandSyncCategory", spa1);
                //return new HttpResponseMessage(HttpStatusCode.OK);
                //return BranchURL + " Update Category Successfully.";
                return "Success";
            }
            catch (Exception ex)
            {
                throw ex;
            }
        }
        [System.Web.Http.HttpPost]
        public string SyncBrandDbItems([FromBody] string Dataset, string BranchURL)
        {
            try
            {
                List<SyncItems> value = JsonConvert.DeserializeObject<List<SyncItems>>(Dataset);
                DataTable dt = DB.ToDataTable(value);
                SqlParameter[] spa1 ={
                                           new SqlParameter(){
                                           ParameterName="@dttblItemsSync",
                                            Value =dt
                                        }
                    };
                DB.ExecuteStoredProcDataSet("sp_InsertIntoBrandSyncItems", spa1);
                return "Success";

            }
            catch (Exception ex)
            {
                throw ex;
            }
        }
    }
    public class SyncCategory
    {
        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public string SEQ_NUM { get; set; }
        public string PrinterName { get; set; }
        public string ImageName { get; set; }
        public bool? ShowInTablet { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public int? BrandID { get; set; }
        public bool? DineIn { get; set; }
        public bool? HomeDelivery { get; set; }
        public bool? Deleted { get; set; }
        public int? MainCategory { get; set; }
        public bool isactive { get; set; }
        public int? HID { get; set; }
    }
    public class SyncItems
    {
        public int ID { get; set; }
        public int? CAT_NUM { get; set; }
        public string ITEM_NAME { get; set; }
        public decimal? PRICE { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string ITEM_DESC_ENG { get; set; }
        public int? Seq_Num { get; set; }
        public bool? Deleted { get; set; }
        public decimal? CostPrice { get; set; }
        public int? Franchise_GroupID { get; set; }
        public bool isactive { get; set; }
        public int? HID { get; set; }
        public bool? isExtra { get; set; }
        public bool? Ischoice { get; set; }
    }
}
