using Newtonsoft.Json;

namespace Jar
{
    /// <summary>
    /// Response recieved from the checkout API
    /// </summary>
    public class HesabeCheckoutResponse
    {
        [JsonProperty("status")]
        public bool Status { get; set; }

        [JsonProperty("code")]
        public long Code { get; set; }

        [JsonProperty("message")]
        public string Message { get; set; }

        [JsonProperty("response")]
        public HesabeCheckoutResponseData Response { get; set; }
    }

    /// <summary>
    /// Contains the token from the response in the checkout api
    /// </summary>
    public partial class HesabeCheckoutResponseData
    {
        [JsonProperty("data")]
        public string Data { get; set; }
    }
}
