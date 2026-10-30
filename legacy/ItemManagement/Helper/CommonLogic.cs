using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Configuration;

namespace Jar.Helper
{
    public class CommonLogic
    {

        public CommonLogic()
        {
        }
        public static string ConnectionString(string paramName)
        {
            string tmpS = string.Empty;
            if ((WebConfigurationManager.ConnectionStrings[paramName] != null))
            {
                try
                {
                    tmpS = WebConfigurationManager.ConnectionStrings[paramName].ConnectionString;
                }
                catch
                {
                    tmpS = string.Empty;
                }
            }
            return tmpS;
        }
    }
}