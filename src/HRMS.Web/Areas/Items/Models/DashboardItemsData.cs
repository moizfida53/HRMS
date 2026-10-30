#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
namespace HRMS.Web.Areas.Items.Controllers
{
    internal class DashboardItemsData
    {
        public string ItemName { get; set; }
        public string CategoryName { get; set; }
        public int Visits { get; set; }
    }
}