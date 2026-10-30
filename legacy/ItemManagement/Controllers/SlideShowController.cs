using Jar.Helper;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using static Jar.Models.mobileData;
namespace Jar.Controllers
{
    public class SlideShowController : Controller
    {
        //
        // GET: /SlideShow/

        public ActionResult SlideShows()
        {
            //return View();
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            if (cookie != null)
            {
                if (!string.IsNullOrEmpty(cookie["WaiterID"]))
                {
                    //WaiterID = Convert.ToInt32(cookie["WaiterID"]);
                    //BrandID = Convert.ToInt32(cookie["BrandID"]);
                    //RoleID = Convert.ToInt32(cookie["RoleID"]);

                    //ViewBag.WaiterID = WaiterID;
                    //ViewBag.BrandID = BrandID;
                    //ViewBag.RoleID = RoleID;
                    return View();
                }
            }
            return RedirectToAction("Index", "Login");
        }

        public ActionResult Index()
        {
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            if (cookie != null)
            {
                if (!string.IsNullOrEmpty(cookie["WaiterID"]))
                {
                    //WaiterID = Convert.ToInt32(cookie["WaiterID"]);
                    //BrandID = Convert.ToInt32(cookie["BrandID"]);
                    //RoleID = Convert.ToInt32(cookie["RoleID"]);

                    //ViewBag.WaiterID = WaiterID;
                    //ViewBag.BrandID = BrandID;
                    //ViewBag.RoleID = RoleID;
                    return View();
                }
            }
            return RedirectToAction("Index", "Login");
        }

        public JsonResult GetWebImageSlideShow(int BrandID)
        {

            List<Jar.Models.Items> Items = new List<Jar.Models.Items>();
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("WebSlideshow_GetImages", spa);

                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {
                        Items.Add(new Jar.Models.Items
                        {

                            IMAGENAME = dtRow["WebSlideImageName"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["WebImageSequence"].ToString()),
                            ID = Convert.ToInt32(dtRow["id"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult UploadFile(HttpPostedFileBase fileToUpload)
        {
            string imageUrls = "";
            string _path = "";

            HttpFileCollectionBase files = Request.Files;
            if (files.Count > 0)
            {
                for (int i = 0; i < files.Count; i++)
                {
                    HttpPostedFileBase file = files[i];
                    try
                    {
                        if (file.ContentLength > 0)
                        {
                            var Filename = file.FileName;
                            //string strpath = Path.GetExtension(Filename);
                            //Filename = RenameImanges(Filename);

                            string strpath = Path.GetExtension(Filename);
                            //Filename = RenameImanges(Filename) + strpath;
                            Filename = RenameImanges(Filename);


                            ItemsController objitemcont = new ItemsController();

                            if (strpath == ".gif")
                            {
                                objitemcont.uploadGif(fileToUpload);
                                return Json(Filename);
                            }
                            _path = Path.Combine(Server.MapPath("~/images/webSlide"), Filename);
                            //_Thumbnailpath = Path.Combine(Server.MapPath("~/ThumbnailImages"), Filename);
                            byte[] fileData = null;
                            using (var binaryReader = new BinaryReader(file.InputStream))
                            {
                                fileData = binaryReader.ReadBytes(file.ContentLength);
                            }

                            objitemcont.HandleImageUpload(fileData, _path);
                            //objitemcont.HandleThumbnailImageUpload(fileData, _Thumbnailpath);

                            //imageUrls = "/images/" + Filename;
                            imageUrls = Filename;
                        }
                        //System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");
                    }
                    catch (Exception ex)
                    {
                        //return Json(ViewBag.Message);
                        return Json(new { Message = "Fail," + ex.Message + "" }, JsonRequestBehavior.AllowGet);
                    }
                }
            }
            else
            {
                return Json(new { Message = "Fail, Please Select file." }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Success", FileName = imageUrls }, JsonRequestBehavior.AllowGet);

        }
        public JsonResult AddWebSlideShowImage(string ImageName, int brandID)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ImageName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    }
                               };

            DB.ExecuteStoredProc("WebSlideShows_Add", spa);
            return Json(new { Message = "Success"}, JsonRequestBehavior.AllowGet);

        }
        public string RenameImanges(string Filename)
        {
            Filename = Filename.ToLower();
            Filename = Filename.Replace(" ", "_");
            Filename = Filename.Trim();
            Filename = Filename.Replace("%", "_");
            Filename = Filename.Replace("&", "_");
            Filename = Filename.Replace("#", "_");
            Filename = Filename.Replace("-", "_");
            Filename = Filename.Replace("@", "_");
            Filename = Filename.Replace("(", "_");
            Filename = Filename.Replace(")", "_");
            Filename = Filename.Replace("[", "_");
            Filename = Filename.Replace("]", "_");
            Filename = Filename.Replace("-", "_");
            return Filename;
        }
    }
}
