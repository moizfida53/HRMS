namespace Jar
{

    public static class HesabeConstants
    {
        public const string VERSION = "2.0";

        public const string CHECKOUT_URL = "https://sandbox.hesabe.com/checkout";
        public const string PAYMENT_URL = "https://sandbox.hesabe.com/payment";

        // Get below values from Merchant Panel, Profile section
        public const string ACCESS_CODE = "__SET_IN_LOCAL_CONFIG__";
        public const string MERCHANT_KEY = "__SET_IN_LOCAL_CONFIG__";
        public const string MERCHANT_IV = "__SET_IN_LOCAL_CONFIG__";
        public const string MERCHANT_CODE = "__SET_IN_LOCAL_CONFIG__";

        // This URL are defined by you to get the response from Payment Gateway
        //public const string RESPONSE_URL = "https://localhost:5001/PaymentSuccess";
        //public const string FAILURE_URL = "https://localhost:5001/PaymentFailure";

        public const string RESPONSE_URL = "https://localhost:44365/Payment/PaymentSuccess";
        public const string FAILURE_URL = "https://localhost:44365/Payment/PaymentFailure";
    }

    /// <summary>
    /// Supported payment types by Hesabe
    /// </summary>
    public enum HesabePaymentType
    {
        ChooseLater = 0,
        Knet = 1,
        MPGS = 2
    }
}
