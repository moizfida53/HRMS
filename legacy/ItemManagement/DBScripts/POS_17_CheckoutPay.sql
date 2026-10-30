/**********************************************************************************
  POS_17_CheckoutPay.sql
  ------------------------------------------------------------------------------
  Support for taking online payment from the CUSTOMER checkout, not just the POS.

      sp_POS_IsOnlinePaymentType   is this method one that must be paid now?

  Run after POS_16_PaymentImages.sql.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_IsOnlinePaymentType') IS NOT NULL DROP PROCEDURE dbo.sp_POS_IsOnlinePaymentType;
GO

CREATE PROCEDURE dbo.sp_POS_IsOnlinePaymentType
      @PaymentTypeID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Returns 1 / 0 rather than a row, so the caller cannot mistake "no such
    -- payment type" for "not online" - both are 0, and both mean do not
    -- redirect to a gateway.
    SELECT CAST(CASE WHEN EXISTS (
               SELECT 1 FROM dbo.tblInvoicePaymentType
               WHERE  ID = @PaymentTypeID
                 AND  IsOnline = 1
                 AND  ISNULL(IsDeleted,0) = 0
                 AND  ISNULL(IsActive,1) = 1
           ) THEN 1 ELSE 0 END AS INT);
END
GO

PRINT 'sp_POS_IsOnlinePaymentType created.';
GO

/* Check which methods will send the customer to a gateway:
   SELECT ID, PaymentTypeName, IsOnline, IsCOD
   FROM   dbo.tblInvoicePaymentType
   WHERE  ISNULL(IsDeleted,0) = 0
   ORDER BY Seqnum, ID;
*/
