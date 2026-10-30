#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using System;
using System.Collections.Generic;
using System.Linq;

namespace HRMS.Web.Areas.Items.Models
{
    public class image
    {

        public int CAT_NUM { get; set; }
        public string CAT_NAME { get; set; }
        public int Seq_Num { get; set; }
        public Boolean ShowInTablet { get; set; }
        public string CAT_NAME_ARABIC { get; set; }
        public string Imagename { get; set; }
    }
}