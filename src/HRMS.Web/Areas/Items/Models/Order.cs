#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;

namespace HRMS.Web.Areas.Items.Models
{
    public class UserLogin
    {
        public string Username { get; set; }
        public string Password { get; set; }
        public int WaiterID { get; internal set; }
        public int RoleID { get; internal set; }
        public bool Authentication { get; internal set; }
        public string PORT { get; internal set; }
    }
    public class DineIn
    {
        public int TableID { get; set; }
        public string Table_No { get; set; }
        public string Capacity { get; set; }
        public bool Status { get; set; }
        public int TableType { get; set; }
        public string BillAmount { get; set; }
        public string InvoiceNo { get; set; }
        public string Table_Desc { get; set; }
        public string InvoiceDate { get; set; }
        public string InvoiceTime { get; set; }
        public decimal Xaxis { get; set; }
        public decimal Yaxis { get; set; }
        public int Mobile { get; set; }
        public string CustomerName { get; set; }
        public string InvoiceTime2 { get; set; }
        public string Comments { get; set; }
        public string Neighborhood { get; set; }
        public string DriverName { get; set; }
        public int OrderStatusID { get; set; }
        public string OrderStatusName { get; set; }
        public int StatusAll { get; set; }
    }

    public class Order
    {
        public int TableID { get; set; }
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
        
    }

    public class TotalBillAmount
    {
        public decimal BillAmount { get; set; }
    }

    public class Waiter
    {
        public int ID { get; set; }
        public string NAME { get; set; }
        public string USERNAME { get; set; }
        public string PASSWORD { get; set; }
        public string DELETEPASSWORD { get; set; }
        public int[] TableID { get; set; }
        public int Floor { get; set; }       
        public string BrandID { get;  set; }
        public string BrandName { get;  set; }
        public int Role_ID { get;  set; }
        public string RoleName { get;  set; }
    }

    public class Comments
    {
        public string Comment { get; set; }
        public string ItemID { get; set; }
    }

    public class ItemsComments
    {
        public int id { get; set; }
        public string ItemID { get; set; }
    }

    public class Extras
    {
        public int ExtraID { get; set; }
        public string Extra { get; set; }
        public decimal PriceExtra { get; set; }
        public string ItemID { get; set; }
    }

    public class TakeOrder
    {
        public int Person { get; set; }
        public string Name { get; set; }
        public int ID { get; set; }
    }

    public class GridItems
    {
        public string ItemName { get; set; }
        public string OrderID { get; set; }
        public string ItemID { get; set; }
        public string TotalPrice { get; set; }
        public string SentToPrinter { get; set; }
        public string Quantity { get; set; }
        public string Price { get; set; }
        public string Comment { get; set; }
        public string Extra { get; set; }
        public string ExtraID { get; set; }
    }

    public class DiscountPer
    {
        public string DiscountP { get; set; }
        public string BillAmount { get; set; }
    }

    public class Discount
    {
        public string DiscountAmount { get; set; }
        public string BillAmount { get; set; }
    }

    public class PayType
    {
        public string PaymentType { get; set; }
    }

    public class ReceiveCash
    {
        public string ReceivedCash { get; set; }
        public string FinalAmount { get; set; }
        public string CashAmount { get; set; }
        public string Cash { get; set; }
        public string BillAmount { get; set; }
        public string DiscountAmount { get; set; }
        public string Master { get; set; }
        public string Visa { get; set; }
        public string Knet { get; set; }
        public string Change { get; set; }
        
    }

    public class Arrange
    {
        public int TableID { get; set; }
        public decimal X { get; set; }
        public decimal Y { get; set; }
    }

    public class CancleOrder
    {
        public string NewItem { get; set; }
    }
    public class WaiterLogin
    {
        public int BranchId { get; set; }
        public string Password { get; set; }
    }

    public class WaiterLoginData
    {
        public string Message { get; set; }
        public List<WaiterUser> dtLoginData { get; set; }
    }
    public class WaiterUser
    {
        public int ID { get; set; }
        public string UserName { get; set; }
        public string Name { get; set; }
        public int? Role { get; set; }
        public int TableType { get; set; }
        public string KitchenView { get; set; }
        public int BranchID { get; set; }
        public string BranchName { get; set; }
        public int? StoreID { get; set; }
        public int? AreaID { get; set; }
        public int? BrandID { get; set; }
        public string BrandName { get; set; }
    }

}