#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;

namespace HRMS.Web.Areas.Items.Models
{

    public class Allergen
    {
        public int id { get; set; }
        public string name { get; set; }
        public string image { get; set; }
    }
    public class Allergen_Assign
    {
        public int id { get; set; }
        public int itemid { get; set; }
        public int allergenid { get; set; }
    }

    public class AllergenMasterData
    {
        public int allergenid { get; set; }
        public string name { get; set; }
        public string image { get; set; }
        public int Allergen_AssignID { get; set; }
        public int itemid { get; set; }
        public string arabicname { get; set; }
        
    }
}