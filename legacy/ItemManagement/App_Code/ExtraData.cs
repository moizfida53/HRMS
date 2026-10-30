using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

/// <summary>
/// Summary description for Order
/// </summary>
public class ExtraData
{
    public ExtraData(int ExtraID, string Extra,double Price, bool selected)
    {
        this.ExtraID = ExtraID;
        this.Extra = Extra;
        this.selected = selected;
        this.Price = Price;
    }
    public int ExtraID { get; set; }
    public string Extra { get; set; }
    public bool selected { get; set; }
    public double Price { get; set; }
}