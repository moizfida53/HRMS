#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;

namespace HRMS.Web.Areas.Items.Models
{
    public class Cat_Items : Category2
    {
        public int ID { get; set; }
        public int CAT_NUM2 { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string ITEM_DESC_ENG { get; set; }
        public string EXTRA { get; set; }
        public int[] EXTRAID { get; set; }
        public string COMMENT { get; set; }
        public int[] COMMENTID { get; set; }
        public int Seq_No { get; set; }
        public int Seq_Num { get;  set; }
    }
 

    public class Category2: Brand
    {
        public int CAT_NUM { get; set; }
        public int MainCategory { get; set; }
        public Boolean ShowInTablet { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string PrinterName { get; set; }
        public int SEQ_NUM { get; set; }
        public string CatNameMan { get;  set; }
        public string CatNameRus { get;  set; }
        public List<Branch> BranchData { get; set; }
        public bool Deleted { get; set; }
    }

    public class Categories
    {
        public int CAT_NUM { get; set; }
        public int MainCategory { get; set; }
        public Boolean ShowInTablet { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string PrinterName { get; set; }
        public int SEQ_NUM { get; set; }
       
    }

    public class Extras2
    {
        public int ID { get; set; }
        public string Extra { get; set; }
        public decimal Price { get; set; }
        public int ExtraID { get; set; }
    }

    public class Comments2
    {
        public int ID { get; set; }
        public int CommentID { get; set; }
        public string Comment { get; set; }
    }

    public class Table
    {
        public int ID { get; set; }
        public int TableID { get; set; }
        public string Table_No { get; set; }
        public string Capacity { get; set; }
        public int TableType { get; set; }
    }

    public class TableType
    {
        public int ID { get; set; }
        public string Description { get; set; }
    }
   
    public class Brand
    {
        public int BrandSeq { get; set; }
        public string BrandName { get; set; }
        public string BrandNameAr { get; set; }
        public decimal DeliveryCharges { get; set; }
        public int BrandID { get; set; }
        public int Russian { get;  set; }
        public int Mandarin { get;  set; }
        public int ThemeID { get;  set; }
        public string ThemeName { get;  set; }
        public string BrandLogo { get;  set; }
        public string BrandUrl { get; set; }
    }

    public class Branch
    {
        public int BranchId { get; set; }
        public string branchName { get; set; }
        public string BranchNameAra { get; set; }
        public int BrandID { get; set; }
        public string BrandName { get; set; }
        public string BrandNameAra { get; set; }
        public int CopyBranchID { get; set; }
        public bool IsActive { get; set; }
    }
    

    public class ItemCategory
    {
        public int ID { get; set; }
        public int CAT_NUM { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string ITEM_DESC_ENG { get; set; } 
        public int Seq_No { get; set; }
        public int Seq_Num { get; set; }
    }

}