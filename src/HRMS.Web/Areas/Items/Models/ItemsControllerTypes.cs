#nullable disable
// Types that lived at the bottom of the old ItemsController.cs.
namespace HRMS.Web.Areas.Items.Controllers
{
    public class Comments
    {
        public int ID { get; set; }
        public string comments_eng { get; set; }
        public string comments_arb { get; set; }
    }
    public class ModifierGroups
    {
        public int ID { get; set; }
        public string GroupNameEng { get; set; }
        public string GroupNameArb { get; set; }
        public int? TypeID { get; set; }
        public string TypeName { get; set; }
        public int? MinSelect { get; set; }
        public int? MaxSelect { get; set; }
        public int? Seq_Num { get; set; }
    }
    
    public class CartComments
    {
        public int II { get; set; }
        public int CI { get; set; }
        public string comments_eng { get; set; }
        public string comments_arb { get; set; }
    }
    public class CartExtraItems
    {
        public int II { get; set; }
        public int EI { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
    }

    public class Allergens
    {
        public int id { get; set; }
        public string name { get; set; }
        public string Name_arabic { get; set; }
        public string image { get; set; }
    }
}
