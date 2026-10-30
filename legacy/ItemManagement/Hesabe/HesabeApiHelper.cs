using System.Net.Http;
using System.Threading.Tasks;

namespace Jar
{
    /// <summary>
    /// Hesabe Checkout API helper
    /// </summary>
    public static class HesabeApiHelper
    {
        /// <summary>
        /// Method to make POST API call to the checkout API in order to retrive the token
        /// </summary>
        /// <param name="encryptedPaymentData"></param>
        /// <returns>Returns encrypted data containing the token</returns>
        public static async Task<string> PostCheckoutApi(string encryptedPaymentData)
        {
            using (var httpClient = new HttpClient())
            {
                httpClient.DefaultRequestHeaders.Clear();
                httpClient.DefaultRequestHeaders.Add("accessCode", HesabeConstants.ACCESS_CODE);

                using (var response = await httpClient.PostAsync($"{HesabeConstants.CHECKOUT_URL}?data={encryptedPaymentData}", null))
                {
                    return await response.Content.ReadAsStringAsync();
                }
            }
        }
    }
}
