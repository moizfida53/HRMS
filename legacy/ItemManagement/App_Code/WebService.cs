using System;
using System.Collections.Generic;
using System.Web.Services;
using System.Data;
using System.Data.SqlClient;
using Jar.Helper;
using System.Web.Mvc;
using Jar.Models;
using System.Web.Script.Serialization;
using System.Web.Script.Services;
using Newtonsoft.Json;

[WebService(Namespace = "http://tempuri.org/")]
[WebServiceBinding(ConformsTo = WsiProfiles.BasicProfile1_1)]
public class WebService : System.Web.Services.WebService
{


    [WebMethod]
    public DataSet GetData(string tablename)
    {
        DataSet ds = null;
        try
        {
            ds = DBFunction.GetData("select * from " + tablename, new Dictionary<string, object>());
        }
        catch (Exception ex)
        {

            return null;
        }
        return ds;
    }
    [WebMethod]
    public DataSet GetBrandData(string Password)
    {
        DataSet ds = null;
        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@Password",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Password
                                    },
                               };

            ds = DB.ExecuteStoredProcDataSet("sp_BrandData", spa);
        }
        catch (Exception ex)
        {

            return null;
        }
        return ds;
    }

    [WebMethod]
    public DataSet GetImageSlideShow(int brandID)
    {
        DataSet ds = null;
        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    },
                               };
            ds = DB.ExecuteStoredProcDataSet("Image_Slideshow", spa);
        }
        catch (Exception ex)
        {

            return null;
        }
        return ds;
    }
    [WebMethod]
    public DataSet GetCategoryData(int BrandID)
    {

        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryMobile", spa);
            return ds;
        }
        catch (Exception ex)
        {

            return null;
        }
    }


    [WebMethod]
    public string JsonGetCategoryData(int BrandID)
    {

        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryMobile", spa);
            DataTable expCategory = ds.Tables[0];
            string jsonexpCategory = JsonConvert.SerializeObject(expCategory);
            return jsonexpCategory;

        }
        catch (Exception ex)
        {

            return null;
        }
    }

    [WebMethod]
    public DataSet GetSettingData()
    {

        try
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_getSetting");
            return ds;
        }
        catch (Exception ex)
        {

            return null;
        }
    }
    [WebMethod]
    public DataSet GetItemData(int BrandID)
    {
        try
        {
            SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemMobile", spa);
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }

    [WebMethod]
    public DataSet GetItemChoices()
    {
        try
        {
            //SqlParameter[] spa ={ new SqlParameter(){
            //                           ParameterName="@BrandID",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=BrandID
            //                        },
            //                   };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemChoices");
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }
    [WebMethod]
    public DataSet GetItemExtras()
    {
        try
        {
            //SqlParameter[] spa ={ new SqlParameter(){
            //                           ParameterName="@BrandID",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=BrandID
            //                        },
            //                   };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemExtras");
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }

    [WebMethod]
    public DataSet GetItemComments()
    {
        try
        {
            //SqlParameter[] spa ={ new SqlParameter(){
            //                           ParameterName="@BrandID",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=BrandID
            //                        },
            //                   };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemComments");
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }

    [WebMethod]
    public DataSet GetComments()
    {
        try
        {

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetComments");
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }


    [WebMethod]
    public DataSet GetTheme(int BrandID)
    {
        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ThemeID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetTheme", spa);
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }
    [WebMethod]
    [ScriptMethod(UseHttpGet = true, ResponseFormat = ResponseFormat.Json)]
    public void GetJsonTheme()
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetThemes");
        List<Brand> Brand = new List<Brand>();
        DataTable dtgrdBrand = ds.Tables[0];
        try
        {

            if (dtgrdBrand.Rows.Count > 0)
            {
                foreach (DataRow dtRow in dtgrdBrand.Rows)
                {
                    Brand.Add(new Brand
                    {
                        ThemeID = Convert.ToInt32(dtRow["ThemeID"].ToString()),
                        ThemeName = dtRow["ThemeName"].ToString(),
                    });
                }
            }

            Context.Response.Write(js.Serialize(Brand));
        }
        catch (Exception ex)
        {
            Context.Response.Write(js.Serialize(ex.ToString()));
        }
    }

    [WebMethod]
    [ScriptMethod(UseHttpGet = true, ResponseFormat = ResponseFormat.Json)]
    public void HelloWorld()
    {
        JavaScriptSerializer js = new JavaScriptSerializer();
        Context.Response.Clear();
        Context.Response.ContentType = "application/json";
        Brand emp = new Brand();
        emp.BrandName = "testName";
        Context.Response.Write(js.Serialize(emp));


    }

    [WebMethod]
    public DataSet GetFeedBack(int BrandID)
    {
        try
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

            DataSet ds = DB.ExecuteStoredProcDataSet("Mobile_GetFeedBackLayout", spa);
            return ds;
        }
        catch (Exception ex)
        {
            return null;
        }
    }

    [WebMethod]
    public string AddFeedBack(string json)
    {
        try
        {

            //LogFunction.LogDebug("Processing Order :" + TableNO);
            //LogFunction.LogDebug("json : " + json);
            List<FeedBackData> orders = JsonConvert.DeserializeObject<List<FeedBackData>>(json);
            Dictionary<string, object> Param = new Dictionary<string, object>();
            //string status = Convert.ToString(ds.Tables[0].Rows[0][0]);

            foreach (FeedBackData o in orders)
            {
                Param = new Dictionary<string, object>();
                Param.Add("@UDID", o.IMEI);
                Param.Add("@CustomerMobile", o.ContactNo);
                Param.Add("@CustomerName", o.CustomerName);
                Param.Add("@CustomerEmail", o.Email);
                Param.Add("@Question", o.Question);
                Param.Add("@ResponseType", o.TypeID);
                Param.Add("@Response", o.Response);
                Param.Add("@branchName", o.BrandName);
                Param.Add("@Date", o.Date);

                DBFunction.ExecuteQuery("FeedbackData_Add", Param, true);
            }           
            return "1";
        }
        catch (Exception ex)
        {
            //return ex.StackTrace.ToString();       
            return ex.ToString(); ;
        }
    }


}
