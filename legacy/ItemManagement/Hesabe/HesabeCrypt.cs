using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Jar
{
    public class HesabeCrypt
    {
        private readonly string _key;
        private readonly string _iv;

        /// <summary>
        /// Constructor to initialize the HesabeCrypt encryption/decryption library
        /// </summary>
        /// <param name="key"></param>
        /// <param name="iv"></param>
        public HesabeCrypt(string key, string iv)
        {
            _key = key;
            _iv = iv;
        }

        /// <summary>
        /// Method to encrypt the orignal text
        /// </summary>
        /// <param name="plainText"></param>
        /// <returns></returns>
        public string Encrypt(string plainText)
        {
            byte[] array;

            using (Aes aes = Aes.Create())
            {
                aes.Key = Encoding.UTF8.GetBytes(_key);
                aes.IV = Encoding.UTF8.GetBytes(_iv);

                ICryptoTransform encryptor = aes.CreateEncryptor(aes.Key, aes.IV);

                using (MemoryStream memoryStream = new MemoryStream())
                {
                    using (CryptoStream cryptoStream = new CryptoStream((Stream)memoryStream, encryptor, CryptoStreamMode.Write))
                    {
                        using (StreamWriter streamWriter = new StreamWriter((Stream)cryptoStream))
                        {
                            streamWriter.Write(plainText);
                        }

                        array = memoryStream.ToArray();
                    }
                }
            }

            // Converts byte array to string
            return ByteArrayToString(array);
        }

        /// <summary>
        /// Method to convert byte array to string
        /// </summary>
        /// <param name="ba"></param>
        /// <returns></returns>
        private static string ByteArrayToString(byte[] ba)
        {
            StringBuilder hex = new StringBuilder(ba.Length * 2);
            foreach (byte b in ba)
                hex.AppendFormat("{0:x2}", b);
            return hex.ToString();
        }

        /// <summary>
        /// Method to decrypt the ciphertext into unencrypted original text
        /// </summary>
        /// <param name="cipherText"></param>
        /// <returns></returns>
        public string Decrypt(string cipherText)
        {
            // Converts string to byte array
            byte[] buffer = StringToByteArray(cipherText);

            using (Aes aes = Aes.Create())
            {
                aes.Key = Encoding.UTF8.GetBytes(_key);
                aes.IV = Encoding.UTF8.GetBytes(_iv);
                aes.Padding = PaddingMode.None;

                ICryptoTransform decryptor = aes.CreateDecryptor(aes.Key, aes.IV);

                using (MemoryStream memoryStream = new MemoryStream(buffer))
                {
                    using (CryptoStream cryptoStream = new CryptoStream((Stream)memoryStream, decryptor, CryptoStreamMode.Read))
                    {
                        using (StreamReader streamReader = new StreamReader((Stream)cryptoStream))
                        {
                            return streamReader.ReadToEnd();
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Method to convert hex based string to byte array
        /// </summary>
        /// <param name="hex"></param>
        /// <returns></returns>
        private static byte[] StringToByteArray(String hex)
        {
            int NumberChars = hex.Length;
            byte[] bytes = new byte[NumberChars / 2];
            for (int i = 0; i < NumberChars; i += 2)
                bytes[i / 2] = Convert.ToByte(hex.Substring(i, 2), 16);
            return bytes;
        }
    }
}
