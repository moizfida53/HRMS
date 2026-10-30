#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;

namespace HRMS.Web.Areas.Items.Models
{
    public class CategoriesManage
    {
        public int CAT_NUM { get; set; }
        public int MainCategory { get; set; }
        public Boolean ShowInTablet { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string PrinterName { get; set; }
        public int SEQ_NUM { get; set; }
        public string ImageName { get; set; }
        public int IsHaveSubCategory { get; set; }
    }
    public class ItemsList
    {
        public int id { get; set; }
        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string ITEM_NAME { get; set; }
        public string PRICE { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string Currency { get; set; }
        public int? qty { get; set; }
        public string TotalPrice { get; set; }
        public string Comments { get; set; }
        public int HID { get; set; }
        public bool ShowInTablet { get; set; }
        //public bool IsExtraItem { get; set; }
        public string Video { get; set; }
        public string ChoiceName { get; set; }
        public string ChoiceName_ARABIC { get; set; }
        public int MinGroupModifierSelection { get; set; }
    }
    public class ItemsListWithUID
    {
        public int UID { get; set; }
        public int id { get; set; }
        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string ITEM_NAME { get; set; }
        public string PRICE { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string Currency { get; set; }
        public int? qty { get; set; }
        public string TotalPrice { get; set; }
        public string Comments { get; set; }
        public int HID { get; set; }
        public bool ShowInTablet { get; set; }
        //public bool IsExtraItem { get; set; }
        public string Video { get; set; }
        public string ChoiceName { get; set; }
        public string ChoiceName_ARABIC { get; set; }
    }
    public class CartDetails
    {
        public int UID { get; set; }
        public int ItemId { get; set; }
        public int HID { get; set; }
        public int qty { get; set; }
        public string Comments { get; set; }
        public int ChoiceId  { get; set; }
        public int? CartItemUniqID { get; set; }
        public int? ParentItemId { get; set; }

    }

    public class BindCartChoices
    {
        public int UID { get; set; }
        public int ChoiceItemId { get; set; }
        public int GroupId { get; set; }
        public int MainItemId { get; set; }
        public int Price { get; set; }
        public string ItemName { get; set; }
    }
    public class BindCartExtraItems
    {
        public int UID { get; set; }
        public int ExtraItemId { get; set; }
        public int GroupId { get; set; }
        public int MainItemId { get; set; }
        public int Price { get; set; }
        public string ItemName { get; set; }
    }
    public class BindCartComments
    {
        public int UID { get; set; }
        public int CommentId { get; set; }
        public int MainItemId { get; set; }
        public string Comment { get; set; }
    }
    //public class Customer
    //{
    //    public int BranchID { get; set; }
    //    public int CustomerID { get; set; }
    //    public int AddressID { get; set; }
    //    public int AreaID { get; set; }
    //    public string AreaName { get; set; }
    //    public int ID { get; set; }
    //    public string CustomerNameEng { get; set; }
    //    public Int64 Mobile { get; set; }
    //    public Int64 Mobile2 { get; set; }
    //    public Int64 HomeNo { get; set; }
    //    public Int64 CivilID { get; set; }
    //    public string Block { get; set; }
    //    public string Street { get; set; }
    //    public string Lane { get; set; }
    //    public string Building { get; set; }
    //    public string Floor { get; set; }
    //    public string Flat { get; set; }
    //    public string Latitude { get; set; }
    //    public string Longitude { get; set; }
    //    public string Comment { get; set; }
    //    public string AddressRemarks { get; set; }
    //    public bool isPrint { get; set; }
    //    public string Email { get; set; }
    //}

    public class CustomerNew
    {
        public int? id { get; set; }
        public string CustomerName { get; set; }
        public string Mobile { get; set; }
        public string Mobile2 { get; set; }
        
        public string CivilID { get; set; }
        public bool? Deleted { get; set; }
        public int? TableNumber { get; set; }
        public int? NumberofGuests { get; set; }
        public bool? ReOrder { get; set; }
        public bool? TakeAway { get; set; }
    }
    public class Address
    {
        public int? id { get; set; }
        public int? CustomerId { get; set; }
        public string Email { get; set; }
        public int? Areaid { get; set; }
        public string AreaName { get; set; }
        public string Block { get; set; }
        public string Street { get; set; }
        public string Lane { get; set; }
        public string Building { get; set; }
        public string Flat { get; set; }
        public string Floor { get; set; }
        public string HouseNo { get; set; }
        public string PACI { get; set; }
        public string AddressRemark { get; set; }
        public string Lat { get; set; }
        public string Long { get; set; }
        public bool? Deleted { get; set; }
    }
    public class ItemViewOrder
    {

        public DateTime DeliveryDate { get; set; }
        public string DD { get; set; }
        public int WaiterID { get; set; }
        public string WaiterName { get; set; }
        public int CustomerID { get; set; }
        public int AddressID { get; set; }
        public int TableID { get; set; }
        public string MobileNo { get; set; }
        public string InvoiceNo { get; set; }
        public string OrderID { get; set; }
        public string ItemID { get; set; }
        public string ItemName { get; set; }
        public decimal Price { get; set; }
        public int Quantity { get; set; }
        public decimal TotalPrice { get; set; }
        public string Comments { get; set; }
        public string Extra { get; set; }
        public string Table_No { get; set; }
        public string BillAmount { get; set; }
        public string Password { get; set; }
        public string OverallComment { get; set; }
        public string IsTk { get; set; }
        public string Cat_No { get; set; }
        public string OrderTime { get; set; }
        public int BranchID { get; set; }
        public int BrandID { get; set; }
        public int ExistingCustomer { get; set; }
        public int PickupOrder { get; set; }
        public string InvoiceType { get; set; }
        public string CustomerNameEng { get; set; }
        public string InvoiceDate { get; set; }
        public int Reorder { get; set; }
        public string CashAmount { get; internal set; }
        public string K_NETAmount { get; internal set; }
        public string Driver { get; internal set; }
        public Boolean PreparedStatus { get; set; }
        public bool ExistingOrder { get; set; }
        public bool Prepared { get; set; }
        public int IsDiscount { get; set; }
        public decimal Discount { get; set; }

        //if isfullbillDiscount then update discount in invoice table
        public int isfullbillDiscount { get; set; }
        public decimal InvoceDiscount { get; set; }
        public int? HID { get; set; }
        public int? BID { get; set; }
        public int? CartItemUniqID { get; set; }
        public int? ParentItemID { get; set; }
    }
    public class DriverTrackingData
    {
        public string InvoiceNo { get; set; }
        public int DriverId { get; set; }
        public string DriverName { get; set; }
        public string DriverColor { get; set; }
        public string DriverImage { get; set; }

        public string FromLat { get; set; }
        public string FromLong { get; set; }
        public string FromDateTime { get; set; }

        public string ToLat { get; set; }
        public string ToLong { get; set; }

        public string CurrentLat { get; set; }
        public string CurrentLong { get; set; }

        public string CustomerName { get; set; }
        public string CustomerAddress { get; set; }

    }
    public class ItemExtraComments
    {
        public int id { get; set; }
        public string comments_arb { get; set; }
        public string comments_eng { get; set; }
    }
    public class Sections
    {
        public int id { get; set; }
        public string sectionName { get; set; }
        public string SectionNameArabic { get; set; }
    }
    public class SectionBranch
    {
        public int id { get; set; }
        public string branchName { get; set; }
        public string branchNameAra { get; set; }
        public int brandId { get; set; }
        public int sectionId { get; set; }
        public string branchImg { get; set; }
    }


    public class ExtraItemsList
    {
        public int id { get; set; }
        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string ITEM_NAME { get; set; }
        public string PRICE { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public string INGREDIENT { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string IMAGENAME { get; set; }
        public string Currency { get; set; }
        public int? qty { get; set; }
        public string TotalPrice { get; set; }
        public string Comments { get; set; }
        public int HID { get; set; }
        public bool ShowInTablet { get; set; }
        //public bool IsExtraItem { get; set; }
        public string Video { get; set; }
        public string ChoiceName { get; set; }
        public string ChoiceName_ARABIC { get; set; }


        public int GroupId { get; set; }
        public string groupnameEng { get; set; }
        public string groupnamearb { get; set; }
        public int? MinSelect { get; set; }
        public int? maxselect { get; set; }


    }

    public class ItemsAllergenList
    {
        public int itemId { get; set; }
        public int allergenId { get; set; }
        public string allergenName { get; set; }
        public string allergenNameArabic { get; set; }
        public string image { get; set; }
    }
}