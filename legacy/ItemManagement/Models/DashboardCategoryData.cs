using Jar.Models;

namespace Jar.Controllers
{
    internal class DashboardCategoryData : CategoriesManage
    {
        public string CategoryName { get; set; }
        public int Visits { get; set; }
    }
}