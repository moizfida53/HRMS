#nullable disable
// Image helpers that the old CategoryController borrowed from the old ItemsController
// (uploadGif, HandleImageUpload, HandleThumbnailImageUpload). Unchanged apart from
// IFormFile and the wwwroot-qr paths. System.Drawing needs a Windows server.
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using Microsoft.AspNetCore.Http;

namespace HRMS.Web.Areas.Items.Legacy
{
#pragma warning disable CA1416 // System.Drawing is Windows-only - the site runs on Windows/IIS
    public sealed class LegacyImageUpload
    {
        private readonly LegacyServer Server;
        public LegacyImageUpload(LegacyServer server) { Server = server; }

        public string RenameImanges(string Filename)
        {
            Filename = Filename.ToLower();
            Filename = Filename.Replace(" ", "_");
            Filename = Filename.Trim();
            Filename = Filename.Replace("%", "_");
            Filename = Filename.Replace("&", "_");
            Filename = Filename.Replace("#", "_");
            Filename = Filename.Replace("-", "_");
            Filename = Filename.Replace("@", "_");
            Filename = Filename.Replace("(", "_");
            Filename = Filename.Replace(")", "_");
            Filename = Filename.Replace("[", "_");
            Filename = Filename.Replace("]", "_");
            Filename = Filename.Replace("-", "_");
            return Filename;
        }

        public void uploadGif(IFormFile fileToUpload)
        {
            IFormFile file = fileToUpload;
            string imageUrls = "";
            string _FileName = "";
            string _path = "";
            try
            {
                if (file.Length > 0)
                {
                    var Filename = Path.GetFileName(file.FileName);
                    Filename = RenameImanges(Filename);
                    _path = Path.Combine(Server.MapPath("~/images"), Filename);

                    fileToUpload.SaveAs(_path);
                }
                System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");


            }
            catch
            {
                System.Diagnostics.Debug.WriteLine("File upload failed!!");

            }

        }

        public bool ThumbnailCallback()
        {
            return false;
        }
        private Image RezizeImage(Image img, int maxWidth, int maxHeight)
        {
            if (maxHeight == 150 && maxWidth == 300)
            {
                System.Drawing.Image thumbnailImage = img.GetThumbnailImage(64, 64, new System.Drawing.Image.GetThumbnailImageAbort(ThumbnailCallback), IntPtr.Zero);
                return thumbnailImage;
            }

            if (img.Height < maxHeight && img.Width < maxWidth) return img;
            using (img)
            {
                Double xRatio = (double)img.Width / maxWidth;
                Double yRatio = (double)img.Height / maxHeight;
                Double ratio = Math.Max(xRatio, yRatio);
                int nnx = (int)Math.Floor(img.Width / ratio);
                int nny = (int)Math.Floor(img.Height / ratio);
                Bitmap cpy = new Bitmap(nnx, nny, PixelFormat.Format32bppArgb);
                using (Graphics gr = Graphics.FromImage(cpy))
                {
                    gr.Clear(Color.Transparent);

                    // This is said to give best quality when resizing images
                    gr.InterpolationMode = InterpolationMode.HighQualityBicubic;

                    gr.DrawImage(img,
                        new Rectangle(0, 0, nnx, nny),
                        new Rectangle(0, 0, img.Width, img.Height),
                        GraphicsUnit.Pixel);
                }
                return cpy;
            }



        }
        private MemoryStream BytearrayToStream(byte[] arr)
        {
            return new MemoryStream(arr, 0, arr.Length);
        }
        public void HandleImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["Width"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["Height"].ToString());
            Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
        public void HandleThumbnailImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["ThumbnailWidth"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["ThumbnailHeight"].ToString());
            //Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            Size newSize = new Size();
            newSize.Width = MaxWidht;
            newSize.Height = Maxheight;
            Image img = ResizeThumbnailImage(Image.FromStream(BytearrayToStream(binaryImage)), newSize);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
        public static Image ResizeThumbnailImage(Image imgToResize, Size destinationSize)
        {
            var originalWidth = imgToResize.Width;
            var originalHeight = imgToResize.Height;

            //how many units are there to make the original length
            var hRatio = (float)originalHeight / destinationSize.Height;
            var wRatio = (float)originalWidth / destinationSize.Width;

            //get the shorter side
            var ratio = Math.Min(hRatio, wRatio);

            var hScale = Convert.ToInt32(destinationSize.Height * ratio);
            var wScale = Convert.ToInt32(destinationSize.Width * ratio);

            //start cropping from the center
            var startX = (originalWidth - wScale) / 2;
            var startY = (originalHeight - hScale) / 2;

            //crop the image from the specified location and size
            var sourceRectangle = new Rectangle(startX, startY, wScale, hScale);

            //the future size of the image
            var bitmap = new Bitmap(destinationSize.Width, destinationSize.Height);

            //fill-in the whole bitmap
            var destinationRectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);

            //generate the new image
            using (var g = Graphics.FromImage(bitmap))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(imgToResize, destinationRectangle, sourceRectangle, GraphicsUnit.Pixel);
            }

            return bitmap;

        }
        public void HandleWebImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["WebSlideShowImageWidth"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["WebSlideShowImageHeight"].ToString());
            Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
    }
#pragma warning restore CA1416
}
