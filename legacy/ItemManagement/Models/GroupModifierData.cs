using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace Jar.Models
{
    public class GroupModifierMaster
    {
        public int ID { get; set; }
        public string GroupNameEng { get; set; }
        public string GroupNameArb { get; set; }
        public int? Type { get; set; }
        public int? MinSelect { get; set; }
        public int? MaxSelect { get; set; }
        public int? Seq_Num { get; set; }
        public int? BrandId { get; set; }
    }

    public class GroupModifierType
    {
        public int ID { get; set; }
        public string TypeName_Deliverect { get; set; }
        public string TypeName_TMM { get; set; }
    }


    public class GroupModifierSubDetails
    {
        public int ID { get; set; }
        public int? GroupID { get; set; }
        public int? ItemID { get; set; }
        public int? ExtraID { get; set; }
        public int? Seq_Num { get; set; }
    }

    public class GroupModifierDetails
    {
        public int ID { get; set; }
        public int? MainItemId { get; set; }
        public int? GroupId { get; set; }
        public bool? Deleted { get; set; }
        public int? ItemID { get; set; }
        public int? Seq_Num { get; set; }
        public decimal? PRICE { get; set; }
    }
}