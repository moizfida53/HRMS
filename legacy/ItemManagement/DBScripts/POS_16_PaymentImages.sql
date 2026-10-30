/**********************************************************************************
  POS_16_PaymentImages.sql
  ------------------------------------------------------------------------------
  Payment methods on the customer checkout become data-driven.

      tblInvoicePaymentType + Image        file name inside /images
      sp_GetOnlinePaymentTypes             what checkout is allowed to show

  >>> READ THIS BEFORE RUNNING <<<
  The checkout will now show ONLY rows with IsOnline = 1, as requested. In the
  seeded data that means:

      SHOWN    KNET, Visa, MasterCard, Payment Link, MyFatoorah
      HIDDEN   Cash (IsCash=1), Cash on Delivery (IsCOD=1), Wallet, Split

  So cash on delivery disappears from the customer's choices entirely. If that
  is not what you want, section 3 has a one-line change that keeps COD on the
  page alongside the online methods.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  1. Image column
     Stores a FILE NAME ("knetIcon.png"), resolved against /images by the app.
     A full path or an absolute URL is also accepted, so a CDN can be used
     later without a schema change.
==============================================================================*/
IF COL_LENGTH('dbo.tblInvoicePaymentType', 'Image') IS NULL
BEGIN
    ALTER TABLE dbo.tblInvoicePaymentType ADD Image NVARCHAR(200) NULL;
    PRINT '1.1  tblInvoicePaymentType.Image added';
END
ELSE PRINT '1.1  Image column already exists';
GO

-- Only images that actually exist in /images today are seeded. Inventing file
-- names would produce broken icons that look like a code fault.
UPDATE dbo.tblInvoicePaymentType SET Image = N'knetIcon.png'
 WHERE Image IS NULL AND (PaymentTypeName LIKE N'%KNET%' OR PaymentTypeName LIKE N'%K-NET%');

UPDATE dbo.tblInvoicePaymentType SET Image = N'cash.png'
 WHERE Image IS NULL AND (IsCash = 1 OR IsCOD = 1);

UPDATE dbo.tblInvoicePaymentType SET Image = N'credit-card.png'
 WHERE Image IS NULL AND (PaymentTypeName LIKE N'%Visa%'
                       OR PaymentTypeName LIKE N'%Master%'
                       OR PaymentTypeName LIKE N'%MyFatoorah%'
                       OR PaymentTypeName LIKE N'%Link%');
GO

PRINT '';
PRINT '>>> Set the rest yourself, e.g.:';
PRINT '    UPDATE dbo.tblInvoicePaymentType SET Image = N''myfatoorah.png'' WHERE PaymentTypeName = N''MyFatoorah'';';
PRINT '    (drop the file into the /images folder of the site)';
GO


/*==============================================================================
  2. Display order
     Seqnum already exists but is not reliably set; checkout needs a stable
     order or the buttons move around between page loads.
==============================================================================*/
UPDATE dbo.tblInvoicePaymentType SET Seqnum = ID WHERE Seqnum IS NULL OR Seqnum = 0;
GO


/*==============================================================================
  3. sp_GetOnlinePaymentTypes

  @IncludeCOD = 1 adds cash on delivery back alongside the online methods.
  Flip it in the controller if you want COD on the checkout page.
==============================================================================*/
IF OBJECT_ID('dbo.sp_GetOnlinePaymentTypes') IS NOT NULL DROP PROCEDURE dbo.sp_GetOnlinePaymentTypes;
GO

CREATE PROCEDURE dbo.sp_GetOnlinePaymentTypes
      @IncludeCOD BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   PaymentTypeID     = ID
           , PaymentTypeName
           , PaymentTypeNameArb
           , Image
           , IsOnline
           , IsCOD
           , IsCash
           , RequiresReference
           , Seqnum
    FROM     dbo.tblInvoicePaymentType
    WHERE    ISNULL(IsDeleted, 0) = 0
      AND    ISNULL(IsActive, 1) = 1
      AND    ( IsOnline = 1 OR (@IncludeCOD = 1 AND IsCOD = 1) )
    ORDER BY Seqnum, ID;
END
GO

PRINT 'sp_GetOnlinePaymentTypes created.';
GO


/*==============================================================================
  4. What checkout will show
==============================================================================*/
PRINT '';
PRINT '--- Shown on checkout (IsOnline = 1) ---';
EXEC dbo.sp_GetOnlinePaymentTypes @IncludeCOD = 0;

PRINT '';
PRINT '--- Everything, so you can see what is hidden and set images ---';
SELECT   ID, PaymentTypeName, PaymentTypeNameArb, Image
       , IsOnline, IsCOD, IsCash
       , ShownOnCheckout = CASE WHEN IsOnline = 1 THEN 'YES' ELSE 'no' END
FROM     dbo.tblInvoicePaymentType
WHERE    ISNULL(IsDeleted,0) = 0
ORDER BY Seqnum, ID;
GO
