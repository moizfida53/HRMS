#nullable disable
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using HRMS.Web.Areas.Items.Legacy;
using HRMS.Web.Areas.Items.Legacy.Hesabe;
using HRMS.Web.Areas.Items.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;
using HRMS.Web.Areas.Items.Models;
using System.Threading.Tasks;

namespace HRMS.Web.Areas.Items.Controllers 
{
    //[EnableCors(origins: "*", headers: "*", methods: "*")]
    // The customer-facing QR menu: open to everyone, no HRMS sign-in.
    [Microsoft.AspNetCore.Authorization.AllowAnonymous, IgnoreAntiforgeryToken]
    public class PaymentController : LegacyController
    {
        //private readonly ILogger<PaymentController> _logger;
        //public PaymentController(ILogger<PaymentController> logger)
        //{
        //    _logger = logger;
        //}

        //
        // GET: /Payment/
        public ActionResult Index()
        {
            return View();
        }

        [HttpPost]
        //public async Task<ActionResult> Index(HesabeCheckoutData paymentData)
        public async Task<ActionResult> Index(HesabeCheckoutData paymentData)
        {
            // Fill the payment data class object with the configuration values from the merchant profile
            paymentData.MerchantCode = HesabeConstants.MERCHANT_CODE;
            paymentData.FailureUrl = HesabeConstants.FAILURE_URL;
            paymentData.ResponseUrl = HesabeConstants.RESPONSE_URL;
            paymentData.Version = HesabeConstants.VERSION;

            // Initialize the HesabeCrypt encryption/decryption library using the KEY and IV from the configuration
            var hesabeCrypt = new HesabeCrypt(HesabeConstants.MERCHANT_KEY, HesabeConstants.MERCHANT_IV);

            // Serialize the payment data into JSON string
            var paymentDataJsonSerialized = JsonConvert.SerializeObject(paymentData);

            // Encrypt the JSON Serialized string
            var encryptedPaymentData = hesabeCrypt.Encrypt(paymentDataJsonSerialized);

            // POST the serialized string to the checkout API and recieve back the reponse
            var checkoutApiEncryptedResponse = await HesabeApiHelper.PostCheckoutApi(encryptedPaymentData);

            // Decrypt the response from the checkout API
            var checkoutApiDecryptedResponse = hesabeCrypt.Decrypt(checkoutApiEncryptedResponse);

            // Deserialize the JSON string into an object
            var checkoutApiResponse = JsonConvert.DeserializeObject<HesabeCheckoutResponse>(checkoutApiDecryptedResponse);

            // Redirect the user to the payment page using the token from the checkout API response
            //return Redirect($"{HesabeConstants.PAYMENT_URL}?data={checkoutApiResponse.Response.Data}");
            var urlstr = $"{HesabeConstants.PAYMENT_URL}?data={checkoutApiResponse.Response.Data}";
            return Json(new { Message = "Success",url= urlstr }, JsonRequestBehavior.AllowGet);

            //return Json(new { Message = "Success",url= "https://kpaytest.com.kw/kpg/PaymentHTTP.htm?param=paymentInit&trandata=432f8d4edfb04447a55c74b2b09c78b7b2e7c7ab20485079dc59cc1bd38cc5f03ba319c6c54d888e2045941348c1f80a697cc4b94ada02af51b07ba2a826421769705068bbfe0a9390badc7c5a6dc3c392c519442e7d5735f462719d5080c4391aed9341516f33e2245c9b26a697c12ff8e2639cf37fe7582fe3148f98878d87f718e3fafa301ae8776c5cfb1b1d3b4c1cb2610d9d6ca2aa7bfdd7c40568dcb9a5fb7179f94f9f9bbb8fc31b73c934b341202b5de94ade1f9736385e67fb36f5e78d866208bdaef2d166a550fc1a1219f53800f1b636f55922d95005d56e17c498696d1669984b952e2ddfb2d93e9c50512ae29804354d1d123191dacf5871948df2b586672720719ef160d4baeaa8b9266a7d2fe5f277bfcf30a37c1467c41d16ce06eaf91a82c8ba0322a8f7e76b31a92a09856ac29082e47bede2a85b7b65&tranportalId=144301&responseURL=https://sandbox.hesabe.com/api/response/knet/1&errorURL=https://sandbox.hesabe.com/api/response/knet/1" }, JsonRequestBehavior.AllowGet);
            //return Redirect("https://kpaytest.com.kw/kpg/PaymentHTTP.htm?param=paymentInit&trandata=432f8d4edfb04447a55c74b2b09c78b7b2e7c7ab20485079dc59cc1bd38cc5f03ba319c6c54d888e2045941348c1f80a697cc4b94ada02af51b07ba2a826421769705068bbfe0a9390badc7c5a6dc3c392c519442e7d5735f462719d5080c4391aed9341516f33e2245c9b26a697c12ff8e2639cf37fe7582fe3148f98878d87f718e3fafa301ae8776c5cfb1b1d3b4c1cb2610d9d6ca2aa7bfdd7c40568dcb9a5fb7179f94f9f9bbb8fc31b73c934b341202b5de94ade1f9736385e67fb36f5e78d866208bdaef2d166a550fc1a1219f53800f1b636f55922d95005d56e17c498696d1669984b952e2ddfb2d93e9c50512ae29804354d1d123191dacf5871948df2b586672720719ef160d4baeaa8b9266a7d2fe5f277bfcf30a37c1467c41d16ce06eaf91a82c8ba0322a8f7e76b31a92a09856ac29082e47bede2a85b7b65&tranportalId=144301&responseURL=https://sandbox.hesabe.com/api/response/knet/1&errorURL=https://sandbox.hesabe.com/api/response/knet/1");
        }


        //[HttpGet("PaymentFailure")]
        public ActionResult PaymentFailure(string data)
        {
            // Initialize the HesabeCrypt encryption/decryption library using the KEY and IV from the configuration
            var hesabeCrypt = new HesabeCrypt(HesabeConstants.MERCHANT_KEY, HesabeConstants.MERCHANT_IV);

            //Decrypt the response recieved in the data query string 
            var dataDecrypted = hesabeCrypt.Decrypt(data);

            //Trim the junk characters from the derypted response if any.
            dataDecrypted = dataDecrypted.Substring(0, dataDecrypted.LastIndexOf("}") + 1);

            //Desrialize the decrypted response
            var paymentResponse = JsonConvert.DeserializeObject<HesabePaymentResponse>(dataDecrypted);

            return View(paymentResponse);
        }

        //[HttpGet("PaymentSuccess")]
        public ActionResult PaymentSuccess(string data)
        {
            // Initialize the HesabeCrypt encryption/decryption library using the KEY and IV from the configuration
            var hesabeCrypt = new HesabeCrypt(HesabeConstants.MERCHANT_KEY, HesabeConstants.MERCHANT_IV);

            //Decrypt the response recieved in the data query string 
            var dataDecrypted = hesabeCrypt.Decrypt(data);

            //Trim the junk characters from the derypted response if any.
            dataDecrypted = dataDecrypted.Substring(0, dataDecrypted.LastIndexOf("}") + 1);

            //Desrialize the decrypted response
            var paymentResponse = JsonConvert.DeserializeObject<HesabePaymentResponse>(dataDecrypted);

            return View(paymentResponse);
        }


        //[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public ActionResult Error()
        {
            return View();
            //return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }

        public ActionResult APIResultRedirect(string id)
        {
            if (!string.IsNullOrEmpty(id))
            {
                //List<int> TagIds = id.Split(',').Select(int.Parse).ToList();
                //if (TagIds.Count() > 0)
                //{
                //    ViewBag.BrandId = TagIds[0];
                //    if (TagIds.Count() > 1)
                //    {
                //        ViewBag.Branchid = TagIds[1];
                //    }
                //    else
                //    {
                //        ViewBag.Branchid = 0;
                //    }
                //}
                ViewBag.UrlString = id;
            }
            else
            {
                ViewBag.UrlString = "";
                //ViewBag.BrandId = 0;
                //ViewBag.Branchid = 0;
            }
            return View();
        }

    }
}
