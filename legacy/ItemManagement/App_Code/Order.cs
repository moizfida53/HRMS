using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

/// <summary>
/// Summary description for Order
/// </summary>
public class Order
{
    public Order(int ItemID, int TableNO, string ItemName, int Qty, double Price, List<CommentData> Comments, List<ExtraData> Extras, bool SendtoPrinter, int OrderID, string OrderComment)
    {
        this.ItemID = ItemID;
        this.TableNO = TableNO;
        this.ItemName = ItemName;
        this.Quantity = Qty;
        this.Price = Price;
        this.Comments = Comments;
        this.Extras = Extras;
        this.SendtoPrinter = SendtoPrinter;
        this.OrderComment = OrderComment;
    }
    public int ItemID { get; set; }
    public int TableNO { get; set; }
    public string ItemName { get; set; }
    public int Quantity { get; set; }
    public int OrderID { get; set; }
    public double Price { get; set; }
    public List<CommentData> Comments { get; set; }
    public List<ExtraData> Extras { get; set; }
    public bool SendtoPrinter { get; set; }
    public string OrderComment { get; set; }
}