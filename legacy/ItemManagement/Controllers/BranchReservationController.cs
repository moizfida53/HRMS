using Jar.Helper;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Mail;
using System.Web;
using System.Web.Mvc;
using System.Xml;
using System.Xml.Linq;
using System.Xml.Serialization;

namespace Jar.Controllers
{
    public class BranchReservationController : Controller
    {
        //
        // GET: /BranchReservation/
        public ActionResult Index()
        {
            return View();
        }

        public ActionResult IndexNew()
        {
            return View();
        }

        public JsonResult GetReservationData(string slotIds, string FromDate, string ToDate)
        {
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            //var UserName = cookie["UserName"].ToString();
            //var Name = cookie["WaiterName"].ToString();
            //var RoleID = Convert.ToInt32(cookie["RoleID"]);
            //var WaiterID = Convert.ToInt32(cookie["WaiterID"]);
            try
            {
                DataSet ds = null;
                if (FromDate == "" && ToDate == "")
                {
                    SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@slotIds",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=slotIds },
                                    };
                    ds = DB.ExecuteStoredProcDataSet("sp_GetReservationData", spa);
                }
                else
                {
                    SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@slotIds",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=slotIds },
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.DateTime,
                                       Value=Convert.ToDateTime(FromDate)},
                                       new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.DateTime,
                                       Value=Convert.ToDateTime(ToDate)},
                                    };
                    ds = DB.ExecuteStoredProcDataSet("sp_GetReservationData", spa);
                }


                List<ReservationData> lstReservationData = new List<ReservationData>();
                DataTable dtReservation = ds.Tables[0];
                if (dtReservation.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtReservation.Rows)
                    {
                        lstReservationData.Add(new ReservationData
                        {
                            id = Convert.ToInt32(dtRow["id"].ToString()),
                            branchId = Convert.ToInt32(dtRow["branchId"].ToString()),
                            sloteId = Convert.ToInt32(dtRow["sloteId"].ToString()),
                            reservationDate = dtRow["reservationDate"].ToString(),
                            customerName = dtRow["customerName"].ToString(),
                            customerMobile = dtRow["customerMobile"].ToString(),
                            customerEmail = dtRow["customerEmail"].ToString(),
                            comments = dtRow["comments"].ToString(),
                            TableName = dtRow["TableName"].ToString(),
                            DiningArea = dtRow["DiningArea"].ToString(),
                            confirmationId = dtRow["confirmationId"].ToString(),
                            TransactionDate = dtRow["TransactionDate"].ToString(),
                            slotName = dtRow["slotName"].ToString(),
                            slotNameArabic = dtRow["slotNameArabic"].ToString(),
                            branchName = dtRow["branchName"].ToString(),
                            status = Convert.ToInt32(dtRow["status"].ToString()),
                        });
                    }
                }
                var pagedata = new
                {
                    page = 1,
                    pages = 1,
                    perpage = -1,
                    total = lstReservationData.Count(),
                    sort = "desc",
                    field = "id"
                };

                var temp = Json(new
                {
                    meta = pagedata,
                    data = lstReservationData,
                }, JsonRequestBehavior.AllowGet);
                return temp;
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetReservationData", null);
                return Json("'Fail':'true'");
            }
        }

        [HttpPost]
        public JsonResult SetArrived(int Reservationid)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@Reservationid",
                                         SqlDbType=SqlDbType.Int,
                                       Value=Reservationid
                                    },
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_SetArrived", spa1);
                //if (ds != null && ds.Tables.Count > 0)
                //{
                //    DataTable dtItems = ds.Tables[0];
                //    if (dtItems.Rows.Count > 0)
                //    {

                //    }
                //}

                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "SetArrived", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }


        [HttpPost]
        public JsonResult GetAvailability(int TableSeatingCount, string reservationDate, string DiningArea)
        {
            try
            {
                DateTime dtt = Convert.ToDateTime(reservationDate);
                SqlParameter[] spa1 ={
                                        //new SqlParameter(){
                                        //ParameterName="@TableStructureID",
                                        //SqlDbType=SqlDbType.NVarChar,
                                        //Value=TableStructureID
                                        //},
                                        new SqlParameter(){
                                        ParameterName="@TableSeatingCount",
                                        SqlDbType=SqlDbType.Int,
                                        Value=TableSeatingCount
                                        },
                                        new SqlParameter(){
                                        ParameterName="@reservationDate",
                                        SqlDbType=SqlDbType.DateTime,
                                        Value=dtt
                                        },
                                        new SqlParameter(){
                                        ParameterName="@DiningArea",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=DiningArea
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAvailability", spa1);
                if (ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        DataTable dt = ds.Tables[0];
                        string jsonData = JsonConvert.SerializeObject(dt);
                        return Json(new { Message = "Success", dtresult = jsonData }, JsonRequestBehavior.AllowGet);
                    }
                }
                return Json(new { Message = "Success", dtLabels = "" }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetAvailability", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult SubmitReservationData(int branchid, int slotId, string reservationDate,
                                      string customerName, string customerMobile, string customerEmail,
                                       string comments, int TableSeatingCount, string DiningArea)
        {
            try
            {
                DateTime dtt = Convert.ToDateTime(reservationDate);
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@branchid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=branchid
                                        },
                                        new SqlParameter(){
                                        ParameterName="@slotId",
                                        SqlDbType=SqlDbType.Int,
                                        Value=slotId
                                        },
                                        new SqlParameter(){
                                        ParameterName="@reservationDate",
                                        SqlDbType=SqlDbType.DateTime,
                                        Value=dtt
                                        },
                                        new SqlParameter(){
                                        ParameterName="@customerName",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=customerName
                                        },
                                        new SqlParameter(){
                                        ParameterName="@customerMobile",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=customerMobile
                                        },
                                        new SqlParameter(){
                                        ParameterName="@customerEmail",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=customerEmail
                                        },
                                        new SqlParameter(){
                                        ParameterName="@comments",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=comments
                                        },
                                        new SqlParameter(){
                                        ParameterName="@TableSeatingCount",
                                        SqlDbType=SqlDbType.Int,
                                        Value=TableSeatingCount
                                        },
                                        new SqlParameter(){
                                        ParameterName="@DiningArea",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=DiningArea
                                        },
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_SubmitReservationData", spa1);

                if (ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Columns.Count == 1)
                    {
                        var errormsg = ds.Tables[0].Rows[0][0].ToString();
                        return Json(new { Message = "Success", dtLabels = errormsg }, JsonRequestBehavior.AllowGet);
                    }

                    if (ds.Tables[0].Rows.Count > 0)
                    {

                        try
                        {
                            DataTable dtsms = ds.Tables[1];
                            string MobileNumber = dtsms.Rows[0]["MobileNumber"].ToString();
                            string SMS_Content = dtsms.Rows[0]["SMS_Content"].ToString();
                            string username = dtsms.Rows[0]["username"].ToString();
                            string customerId = dtsms.Rows[0]["customerId"].ToString();
                            string senderText = dtsms.Rows[0]["senderText"].ToString();
                            string Password = dtsms.Rows[0]["Password"].ToString();

                            SendSms(SMS_Content, MobileNumber, username, Password, customerId, senderText);
                        }
                        catch{}
                        
                        DataTable dt = ds.Tables[0];
                        string result = SendMail(dt);


                        if (result == "Success")
                        {
                            string jsonData = JsonConvert.SerializeObject(dt);
                            return Json(new { Message = "Success", dtresult = jsonData }, JsonRequestBehavior.AllowGet);
                        }
                        else
                        {
                            string jsonData = JsonConvert.SerializeObject(dt);
                            return Json(new { Message = "Email not sent!", dtresult = jsonData }, JsonRequestBehavior.AllowGet);
                        }
                    }
                }
                return Json(new { Message = "Success", dtLabels = "" }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "SubmitReservationData", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

        }


        public void SendSms(string SMS_Content, string recipientNumbers, string username, string Password, string customerId, string senderText)
        {
            try
            {
                WebClient webClient = new WebClient();
                webClient.Headers["Accept"] = "application/json";
                webClient.QueryString.Add("username", username);
                webClient.QueryString.Add("Password", Password);
                webClient.QueryString.Add("senderText", senderText);
                webClient.QueryString.Add("recipientNumbers", recipientNumbers);
                webClient.QueryString.Add("messageBody", SMS_Content);
                webClient.QueryString.Add("customerId", customerId);
                webClient.QueryString.Add("isBlink", "false");
                webClient.QueryString.Add("isFlash", "false");
                webClient.QueryString.Add("defdate", "");


                string result = webClient.DownloadString("http://sms.channelsmedia.com/SMSGateway/Services/Messaging.asmx/Http_SendSMS");
                SendingSMSResult response = result.ParseXML<SendingSMSResult>();

                Insert_SMSLog(response, SMS_Content, recipientNumbers);



            }


            catch (Exception eex)
            {
                string asdsa = eex.ToString();
            }
        }

        public void Insert_SMSLog(SendingSMSResult result, string sms, string mobile)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@SMS",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=sms
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Mobile ",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=mobile
                                        }, new SqlParameter(){
                                        ParameterName="@smsID",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=result.messageId
                                        }, new SqlParameter(){
                                        ParameterName="@netpoints",
                                        SqlDbType=SqlDbType.Decimal,
                                        Value=result.NetPoints
                                        },new
                                        SqlParameter(){
                                        ParameterName="@vendorrespond",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=result.Message
                                        },

                                    };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_Reservation_SMSLog", spa);
        }

        public void TestAPI()
        {
            try
            {
                WebClient webClient = new WebClient();
                webClient.Headers["Accept"] = "application/json";
                webClient.QueryString.Add("username", "madeleine22nm");
                webClient.QueryString.Add("Password", "nm@678");
                webClient.QueryString.Add("customerId", "348");

                string result = webClient.DownloadString("http://sms.channelsmedia.com/SMSGateway/Services/Messaging.asmx/Http_AuthenticateUser");
                AuthenticationResult response = result.ParseXML<AuthenticationResult>();
            }


            catch (Exception eex)
            {
                string asdsa = eex.ToString();
            }
        }



        public string SendMail(DataTable dt)
        {
            string returnmsg = "";
            try
            {
                string FilePath = Server.MapPath("~\\EmailTemplate\\ReservationConfirmMail.html");
                StreamReader str = new StreamReader(FilePath);
                string MailText = str.ReadToEnd();
                MailText = MailText.Replace("[ConfirmationID]", dt.Rows[0]["confirmationId"].ToString().Trim());
                MailText = MailText.Replace("[CustomerName]", dt.Rows[0]["customerName"].ToString().Trim());
                MailText = MailText.Replace("[ReservationDate]", dt.Rows[0]["reservationDate"].ToString().Trim());
                MailText = MailText.Replace("[SlotName]", dt.Rows[0]["slotName"].ToString().Trim());
                MailText = MailText.Replace("[comments]", dt.Rows[0]["comments"].ToString().Trim());
                str.Close();

                MailMessage mail = new MailMessage();
                mail.IsBodyHtml = true;
                mail.To.Add(dt.Rows[0]["customerEmail"].ToString());
                string FromEmail = ConfigurationManager.AppSettings["FromEmail"].ToString();
                string Subject = ConfigurationManager.AppSettings["Subject"].ToString();
                string SMTPHost = ConfigurationManager.AppSettings["SMTPHost"].ToString();
                int SMTPPort = Convert.ToInt32(ConfigurationManager.AppSettings["SMTPPort"].ToString());
                bool IsSSL = Convert.ToBoolean(ConfigurationManager.AppSettings["IsSSL"].ToString());
                string SenderEmail = ConfigurationManager.AppSettings["FromEmail"].ToString();
                string SenderPassword = ConfigurationManager.AppSettings["SenderPassword"].ToString();


                mail.From = new MailAddress(FromEmail);
                mail.Sender = new MailAddress(SenderEmail);
                mail.Subject = Subject;
                mail.Body = MailText;



                SmtpClient smtp = new SmtpClient();
                smtp.Host = SMTPHost;
                smtp.Timeout = int.MaxValue;
                //smtp.UseDefaultCredentials = true;
                //////smtp.DeliveryMethod = System.Net.Mail.SmtpDeliveryMethod.Network;


                smtp.Port = SMTPPort;
                smtp.EnableSsl = IsSSL;
                smtp.Credentials = new System.Net.NetworkCredential
                (SenderEmail, SenderPassword);// Enter seders User name and password	

                smtp.Send(mail);

                returnmsg = "Success";
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "SendMail", null);
                returnmsg = "Fail";
            }
            return returnmsg;
        }

        [HttpPost]
        public JsonResult GetTimeSlotData(string selectedDate, string DiningArea)
        {
            try
            {
                DateTime dtt = Convert.ToDateTime(selectedDate);
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@reservationDate",
                                        SqlDbType=SqlDbType.DateTime,
                                        Value=dtt
                                        },
                                        new SqlParameter(){
                                        ParameterName="@DiningArea",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=DiningArea
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetTimeSlotDataDateWise", spa);
                DataTable dt = new DataTable();
                if (ds.Tables.Count > 0)
                {
                    dt = ds.Tables[0];
                }
                string TimeSlotjsonData = JsonConvert.SerializeObject(dt);
                return Json(new { Message = "Success", dtTimeSlotresult = TimeSlotjsonData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetTimeSlotData", null);
                return Json("'Fail':'true'");
            }
        }

        [HttpPost]
        public JsonResult GetBookedTableData(string reservationDate, string DiningArea, int timeslotid)
        {
            try
            {
                DateTime dtt = Convert.ToDateTime(reservationDate);
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@reservationDate",
                                        SqlDbType=SqlDbType.DateTime,
                                        Value=dtt
                                        },
                                        new SqlParameter(){
                                        ParameterName="@DiningArea",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=DiningArea
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Timeslotid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=timeslotid
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBranchTablesReservations", spa);
                DataTable dt = new DataTable();
                DataTable dt1 = new DataTable();
                if (ds.Tables.Count > 0)
                {
                    dt = ds.Tables[0];
                }

                if (ds.Tables.Count > 1)
                {
                    dt1 = ds.Tables[1];
                }
                string TablejsonData = JsonConvert.SerializeObject(dt);
                string TimeSlotjsonData = JsonConvert.SerializeObject(dt1);
                return Json(new { Message = "Success", dtTableresult = TablejsonData, dtTimeSlotresult = TimeSlotjsonData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetBookedTableData", null);
                return Json("'Fail':'true'");
            }
        }

        [HttpPost]
        public JsonResult GetAvailableTableDataForChangeTable(int ReservationId, int selectedTableid)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@ReservationId",
                                        SqlDbType=SqlDbType.Int,
                                        Value=ReservationId
                                        },
                                        new SqlParameter(){
                                        ParameterName="@selectedTableid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=selectedTableid
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAvilableTablesForChangeTable", spa);
                DataTable dt = new DataTable();
                if (ds.Tables.Count > 0)
                {
                    dt = ds.Tables[0];
                }

                string TablejsonData = JsonConvert.SerializeObject(dt);
                return Json(new { Message = "Success", dtTableresult = TablejsonData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetAvailableTableDataForChangeTable", null);
                return Json("'Fail':'true'");
            }
        }


        [HttpPost]
        public JsonResult UpdateReservedTable(int currentTableid, int NewTableid, int Reservationid)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@currentTableid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=currentTableid
                                        },
                                        new SqlParameter(){
                                        ParameterName="@NewTableid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=NewTableid
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Reservationid",
                                        SqlDbType=SqlDbType.Int,
                                        Value=Reservationid
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateReservedTable", spa);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "UpdateReservedTable", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        [HttpGet]
        public JsonResult GetReservationStatus()
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetReservationStatus");
                DataTable dt = new DataTable();
                dt = ds.Tables[0];
                string ReservationStatus = JsonConvert.SerializeObject(dt);
                return Json(new { Message = "Success", dtReservationStatus = ReservationStatus }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "GetTimeSlotData", null);
                return Json("'Fail':'true'");
            }
        }


        [HttpPost]
        public JsonResult ReservationStatus(int ReservationStatusId, int ReservationId)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                        ParameterName="@ReservationStatusId",
                                        SqlDbType=SqlDbType.Int,
                                        Value=ReservationStatusId
                                        },
                                        new SqlParameter(){
                                        ParameterName="@ReservationId",
                                        SqlDbType=SqlDbType.Int,
                                        Value=ReservationId
                                        },

                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_ChangeReservationStatus", spa);
                if (ds.Tables[0].Rows.Count > 0)
                {
                    DataTable dtsms = ds.Tables[0];
                    string MobileNumber = dtsms.Rows[0]["MobileNumber"].ToString();
                    string SMS_Content = dtsms.Rows[0]["SMS_Content"].ToString();
                    string username = dtsms.Rows[0]["username"].ToString();
                    string customerId = dtsms.Rows[0]["customerId"].ToString();
                    string senderText = dtsms.Rows[0]["senderText"].ToString();
                    string Password = dtsms.Rows[0]["Password"].ToString();

                    SendSms(SMS_Content, MobileNumber, username, Password, customerId, senderText);
                }

                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "UpdateReservedTable", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

    }

}



// NOTE: Generated code may require at least .NET Framework 4.5 or .NET Core/Standard 2.0.
/// <remarks/>
[System.SerializableAttribute()]
[System.ComponentModel.DesignerCategoryAttribute("code")]
[System.Xml.Serialization.XmlTypeAttribute(AnonymousType = true, Namespace = "http://itbsms.com/")]
[System.Xml.Serialization.XmlRootAttribute(Namespace = "http://itbsms.com/", IsNullable = false)]
public partial class AuthenticationResult
{




    private string messageField;

    private bool resultField;

    private ushort customerIdField;

    private decimal netPointsField;

    private System.DateTime balanceExpirationDateField;

    private string[] sendersField;

    /// <remarks/>
    public string Message
    {
        get
        {
            return this.messageField;
        }
        set
        {
            this.messageField = value;
        }
    }

    /// <remarks/>
    public bool Result
    {
        get
        {
            return this.resultField;
        }
        set
        {
            this.resultField = value;
        }
    }

    /// <remarks/>
    public ushort CustomerId
    {
        get
        {
            return this.customerIdField;
        }
        set
        {
            this.customerIdField = value;
        }
    }

    /// <remarks/>
    public decimal NetPoints
    {
        get
        {
            return this.netPointsField;
        }
        set
        {
            this.netPointsField = value;
        }
    }

    /// <remarks/>
    public System.DateTime BalanceExpirationDate
    {
        get
        {
            return this.balanceExpirationDateField;
        }
        set
        {
            this.balanceExpirationDateField = value;
        }
    }

    /// <remarks/>
    [System.Xml.Serialization.XmlArrayItemAttribute(IsNullable = false)]
    public string[] Senders
    {
        get
        {
            return this.sendersField;
        }
        set
        {
            this.sendersField = value;
        }
    }
}


// NOTE: Generated code may require at least .NET Framework 4.5 or .NET Core/Standard 2.0.
/// <remarks/>
[System.SerializableAttribute()]
[System.ComponentModel.DesignerCategoryAttribute("code")]
[System.Xml.Serialization.XmlTypeAttribute(AnonymousType = true, Namespace = "http://itbsms.com/")]
[System.Xml.Serialization.XmlRootAttribute(Namespace = "http://itbsms.com/", IsNullable = false)]
public partial class SendingSMSResult
{

    private string messageField;

    private bool resultField;

    private decimal netPointsField;

    private string messageIdField;

    private object rejectedNumbersField;

    /// <remarks/>
    public string Message
    {
        get
        {
            return this.messageField;
        }
        set
        {
            this.messageField = value;
        }
    }

    /// <remarks/>
    public bool Result
    {
        get
        {
            return this.resultField;
        }
        set
        {
            this.resultField = value;
        }
    }

    /// <remarks/>
    public decimal NetPoints
    {
        get
        {
            return this.netPointsField;
        }
        set
        {
            this.netPointsField = value;
        }
    }

    /// <remarks/>
    public string messageId
    {
        get
        {
            return this.messageIdField;
        }
        set
        {
            this.messageIdField = value;
        }
    }

    /// <remarks/>
    public object RejectedNumbers
    {
        get
        {
            return this.rejectedNumbersField;
        }
        set
        {
            this.rejectedNumbersField = value;
        }
    }
}





public class ReservationData
{
    public int id { get; set; }
    public int branchId { get; set; }
    public int sloteId { get; set; }
    public string reservationDate { get; set; }
    public string customerName { get; set; }
    public string customerMobile { get; set; }
    public string customerEmail { get; set; }
    public string comments { get; set; }
    public string TableName { get; set; }
    public string DiningArea { get; set; }
    public string confirmationId { get; set; }
    public string TransactionDate { get; set; }
    public string slotName { get; set; }
    public string slotNameArabic { get; set; }
    public string branchName { get; set; }
    public int status { get; set; }
}

