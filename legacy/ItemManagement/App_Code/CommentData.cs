using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

/// <summary>
/// Summary description for Order
/// </summary>
public class CommentData
{
    public CommentData(int CommentID, string Comment, bool selected)
    {
        this.CommentID = CommentID;
        this.Comment = Comment;
        this.selected = selected;
    }
    public int CommentID { get; set; }
    public string Comment { get; set; }
    public bool selected { get; set; }
}