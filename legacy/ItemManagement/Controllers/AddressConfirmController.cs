using Jar.Helper;
using Jar.Models;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using System.Web;
using System.Web.Mvc;
using System.Web.Script.Serialization;

namespace Jar.Controllers
{
    public class AddressConfirmController : Controller
    {
        public ActionResult Index(string InvoiceNo)
        {
            if (string.IsNullOrEmpty(InvoiceNo))
            {
                return Redirect("/ItemsViewNew/Index");
            }
            else
            {
                ItemsViewController objitemview = new ItemsViewController();
                ViewBag.IsCartVisible = Convert.ToBoolean(System.Configuration.ConfigurationManager.AppSettings["IsCartVisible"]);
                ViewBag.LoginUser = "Customer";
                ViewBag.CallcWebServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                return View();
            }
        }

        [HttpPost]
        public JsonResult GetInvoiceAddress(string InoiceNumber)
        {
            try
            {
                string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                if (!string.IsNullOrEmpty(webServiceUrl))
                {
                    var data = new
                    {
                        InoiceNumber = InoiceNumber,
                    };
                    string inputJson = (new JavaScriptSerializer()).Serialize(data);
                    WebClient client = new WebClient();
                    client.Headers["Content-type"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    string jsonstr = client.UploadString(webServiceUrl + "/DmToCallCenterServices/GetInvoiceAddress", inputJson);
                    result str = JsonConvert.DeserializeObject<result>(jsonstr);
                    return Json(str, JsonRequestBehavior.AllowGet);
                }
                return Json(new { Message = "HO URL not found." }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "AddressConfirmController", "GetInvoiceAddress", null);
                return Json(new { Message = "Error,Invalid Invoice No." }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult UpdateAddress(string InvoiceNo, Address addressInfo)
        {
            try
            {

                string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                if (!string.IsNullOrEmpty(webServiceUrl))
                {
                    var data = new
                    {
                        invoiceId = 0,
                        InvoiceNo = InvoiceNo,
                        addressInfo = addressInfo,
                        isOnlyAddressupdate = 1
                    };
                    string inputJson = (new JavaScriptSerializer()).Serialize(data);
                    WebClient client = new WebClient();
                    client.Headers["Content-type"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    string jsonstr = client.UploadString(webServiceUrl + "/DmToCallCenterServices/UpdateInvoiceAddress", inputJson);
                    result str = JsonConvert.DeserializeObject<result>(jsonstr);
                    //return Json(str, JsonRequestBehavior.AllowGet);
                    return Json(new { Message = "Success", dtresult = "" }, JsonRequestBehavior.AllowGet);
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "SubmitOrder", null);
                //AuditTrail("SubmitOrder", ex.ToString());
            }
            return Json(new { Message = "Fail", dtresult = "" }, JsonRequestBehavior.AllowGet);
        }
    }
}
