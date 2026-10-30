using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;

namespace Jar.Models
{
    public class mobileData
    {

        

        public class brandData
        {
            public int brandSeq { get; set; }
            public string brandName { get; set; }
            public string brandNameAr { get; set; }
            public int brandID { get; set; }
            public int russian { get; set; }
            public int mandarin { get; set; }
            public int themeID { get; set; }
            public string brandLogo { get; set; }
            public bool feedback { get; internal set; }
            public string currency { get; internal set; }
            public string Telephone { get; internal set; }
            public string facebook { get; internal set; }
            public string instagram { get; internal set; }
            public bool orderTaking { get; internal set; }
        }


        public class themeData
        {
            public string separatorLine { get; set; }                              
            public string leftArrow { get; set; }
            public string leftBottom { get; set; }
            public string leftTop { get; set; }
            public string rightArrow { get; set; }
            public string rightBottom { get; set; }
            public string rightTop { get; set; }
            public int brandID { get; set; }
            public string themeName { get; set; }
            public int themeID { get; set; }
            public string categoryActive { get; set; }
            public string categoryInActive { get; set; }
            public string setting { get; set; }         
            public string englishButton { get; set; }
            public string arabicButton { get; set; }
            public string mandarinButton { get; set; }
            public string russianButton { get; set; }
            public string closeButton { get; set; }
            public string homeScreen { get; set; }         
            public string popUpBackground { get; set; }
            public string FontColor { get; set; }
            public string FontColorItemName { get;  set; }
            public string FontColorIngName { get;  set; }
            public string FontColorPrice { get;  set; }
            public string itemBackgroundColor { get;  set; }
            public string BrandName { get; internal set; }
        }


    }
}