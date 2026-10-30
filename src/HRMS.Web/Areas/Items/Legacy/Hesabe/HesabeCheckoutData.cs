#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using Newtonsoft.Json;

namespace HRMS.Web.Areas.Items.Legacy.Hesabe
{
    /// <summary>
    /// Hesabe checkout data where all parameters needs to be defined before encrypting and passing to the checkout api
    /// </summary>
    public class HesabeCheckoutData
    {
        [JsonProperty("amount")]
        public float Amount { get; set; }

        [JsonProperty("paymentType")]
        public int PaymentType { get; set; }

        [JsonProperty("orderReferenceNumber")]
        public string OrderReferenceNumber { get; set; }

        [JsonProperty("version")]
        public string Version { get; set; }

        [JsonProperty("variable1")]
        public string Variable1 { get; set; }

        [JsonProperty("variable2")]
        public string Variable2 { get; set; }

        [JsonProperty("variable3")]
        public string Variable3 { get; set; }

        [JsonProperty("variable4")]
        public string Variable4 { get; set; }

        [JsonProperty("variable5")]
        public string Variable5 { get; set; }

        [JsonProperty("merchantCode")]
        public string MerchantCode { get; set; }

        [JsonProperty("responseUrl")]
        public string ResponseUrl { get; set; }

        [JsonProperty("failureUrl")]
        public string FailureUrl { get; set; }
    }
}
