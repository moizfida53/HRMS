#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;
using HRMS.Web.Areas.Items.Controllers;

namespace HRMS.Web.Areas.Items.Models
{
    public class Category
    {
        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public string ITEM_NAME { get; set; }
    }

    public class Extra
    {
        public int ExtraID { get; set; }
        public string ExtraName { get; set; }
        public string ExtraNameArabic { get; set; }
        public int ItemID { get; set; }
        public int BrandID { get; set; }
        public string ImageName { get; set; }
        public string Price { get; set; }
    }

    public class CatSequance
    {
        public int CAT_NUM { get; set; }
        public int SEQ_NUM { get; set; }
    }

    public class ItemSequance
    {
        public int ItemId { get; set; }
        public int SEQ_NUM { get; set; }
    }

    public class ItemImageDto
    {
        public string ImageName { get; set; }
        public int Seq_No { get; set; }
    }

    public class Items
    {       
        public int ID { get; set; }
        public string OrderID { get; set; }
        public string catNameArabic { get; set; }
        public string catNameRus { get; set; }
        public string catNameMan { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public string ITEM_DESC_ENG { get; set; }
        public string IMAGENAME { get; set; }
        public string INGREDIENT_ARABIC { get; set; }
        public string INGREDIENT { get; set; }
        public int Seq_Num { get; set; }
        public Boolean ShowInTablet { get; set; }
        public string PRICE { get; set; }
        public string CAT_NAME { get; set; }
        public int CAT_NUM { get; set; }             
        public string TotalPrice { get; set; }     
        public int BrandID { get; set; }
        public string ItemNameMan { get;  set; }
        public string ItemNameRus { get;  set; }
        public string INGREDIENT_Man { get;  set; }
        public string INGREDIENT_Rus { get;  set; }
        public string Video { get;  set; }
        public string BrandName { get; internal set; }
        public int HID { get; internal set; }
        public List<Branch> BranchData { get; set; }

        public Boolean IsExtraItems { get; set; }
        public List<Items> ExtraItems { get; set; }
        public List<Items> Choices { get; set; }
        public List<ItemsComments> Comments { get; set; }
        // Selected allergens from the Edit Item modal's "Select Allergen" multi-select.
        // IMPORTANT: do NOT gate AddItem/UpdateItem's sync on "Allergens != null" - when
        // the user deselects every allergen, the client sends an empty JS array, but
        // classic ASP.NET MVC's JSON model binder has a known quirk where a truly empty
        // array often binds to null instead of an empty List<T> (same reason
        // ExtraItems/Choices below are handled as null-OR-Count==0 in UpdateItem). That
        // makes "null" ambiguous between "field submitted empty" and "field never sent
        // because the section was hidden (ShowAllergen=0 for the brand)". Use
        // IsAllergenSectionVisible (an explicit bool, immune to array-binding quirks) to
        // decide whether to sync at all; use Allergens (treating null the same as empty)
        // only to decide WHAT to sync once IsAllergenSectionVisible says to proceed.
        public List<Allergens> Allergens { get; set; }
        public bool IsAllergenSectionVisible { get; set; }

        //new added on 29-11-2020
        public string Currency { get; set; }
        public Boolean IsActive { get; set; }
        public Boolean Ischoice { get; set; }
    }




    public class Waiter2
    {
        public int ID { get; set; }
        public string NAME { get; set; }
        public string USERNAME { get; set; }
        public string PASSWORDNAME { get; set; }
        public string DELETEPASSWORD { get; set; }
       
    }
    public class FeedBackLayout
    {

        public int id { get; set; }
        public int BrandID { get; set; }
        public string Type { get; set; }
        public string Question { get; set; }
        public int TypeId { get; set; }
        public int Sequence { get; set; }
    }

    public class FeedBackData
    {

        public string CustomerName { get; set; }
        public string Email { get; set; }
        public string IMEI { get; set; }
        public string Question { get; set; }
        public string Response { get; set; }
        public string BrandName { get; set; }
        public int ContactNo { get; set; }
        public int TypeID { get; set; }



        
        public string BranchName { get; set; }
      
        public string Date { get; set; }      
        public string ResponseType { get; set; }
     
    }
    public class FeedBackDataNew
    {

        public string CustomerName { get; set; }
        public string Email { get; set; }
        public string ContactNo { get; set; }
        public string Question { get; set; }
        public string ResponseType { get; set; }
        public string DateTime { get; set; }
        public string BranchName { get; set; }
        public string IMEI { get; set; }
        public string Response { get; set; }
        //public string BrandName { get; set; }

    }

    public class GroupModifierTypes
    {
        public int ID { get; set; }
        public string TypeName_TMM { get; set; }
    }


    public class Group_Modifier_Master
    {
        public int ID { get; set; }
        public string GroupNameEng { get; set; }
        public string GroupNameArb { get; set; }
        public int Type { get; set; }
        public int MinSelect { get; set; }
        public int MaxSelect { get; set; }
        public int Seq_Num { get; set; }
        public string SortingType { get; set; }
    }
    public class AssignGroupModifier
    {
        public int MainItemId { get; set; }
        public int GroupId { get; set; }
        public int ItemID { get; set; }
        public int Seq_Num { get; set; }
    }

}