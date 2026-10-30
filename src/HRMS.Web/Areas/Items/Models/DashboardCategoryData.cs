#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using HRMS.Web.Areas.Items.Models;

namespace HRMS.Web.Areas.Items.Controllers
{
    internal class DashboardCategoryData : CategoriesManage
    {
        public string CategoryName { get; set; }
        public int Visits { get; set; }
    }
}