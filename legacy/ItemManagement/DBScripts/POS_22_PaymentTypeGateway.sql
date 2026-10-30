/**********************************************************************************
  POS_22_PaymentTypeGateway.sql
  ------------------------------------------------------------------------------
  WHY THIS EXISTS

  Choosing Cash at checkout ended with

      "Your order NNN was created, but the payment page could not be opened.
       MyFatoorah.ApiToken is not set."

  Nothing in the code sends cash to a gateway. The decision is made from data:

      SubmitOrder -> POSOrderService.MapPaymentType -> tblInvoicePaymentType.IsOnline
                  -> IsOnlinePayment=true -> StartOnlinePayment -> MyFatoorah

  So the row the customer picked has IsOnline = 1. Either the head-office copy
  of tblInvoicePaymentType has that flag set on the cash row, or the tile
  labelled "Cash" is not the row anyone thinks it is. The second half of the
  message is a separate, real gap: MyFatoorah.ApiToken in Web.config is empty,
  so even a correctly-flagged online order cannot reach the gateway.

  WHAT THIS DOES

  Pins the two IDs the way you specified, and makes the gateway itself data
  rather than an assumption:

      ID 1  Cash on Delivery   IsCOD=1, IsCash=1, IsOnline=0, Provider = NULL
      ID 2  MyFatoorah         IsOnline=1, IsCOD=0, IsCash=0, Provider = 'MyFatoorah'

  Provider is a new column. Until now PaymentLinkService called MyFatoorah for
  ANY row with IsOnline=1 - so switching a second method on (Visa, a payment
  link) would silently send it to MyFatoorah too. With Provider, a method
  reaches a gateway only when it names one.

  SECTION 1 shows the table as it stands now - read it before running the rest.
  Run in SSMS against Pistachio_v4 with results-to-text. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - BEFORE
==============================================================================*/
PRINT '===== SECTION 1 : tblInvoicePaymentType as it is now =====';
SELECT   ID, PaymentTypeName, PaymentTypeNameArb
       , IsCash, IsCOD, IsOnline, IsActive, IsDeleted
       , ShownOnCheckout = CASE WHEN IsOnline = 1 THEN 'YES' ELSE 'no' END
FROM     dbo.tblInvoicePaymentType
ORDER BY ID;
GO


/*==============================================================================
  SECTION 2 - Provider column

  Names the gateway a method is paid through. NULL means "not an online
  method" - the safe default, because a NULL provider cannot start a payment.
==============================================================================*/
IF COL_LENGTH('dbo.tblInvoicePaymentType', 'Provider') IS NULL
BEGIN
    ALTER TABLE dbo.tblInvoicePaymentType ADD Provider VARCHAR(30) NULL;
    PRINT '2.1  tblInvoicePaymentType.Provider added';
END
ELSE PRINT '2.1  Provider column already exists';
GO


/*==============================================================================
  SECTION 3 - Pin ID 1 and ID 2

  Updated by ID, not by name: the name is whatever head office typed, the ID is
  what the checkout posts and what tblInvoice.PaymentType stores.
==============================================================================*/

-- ID 1 : Cash on Delivery. IsOnline = 0 is the line that stops a cash order
-- ever being handed to a gateway.
IF EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = 1)
BEGIN
    UPDATE dbo.tblInvoicePaymentType
       SET IsCOD    = 1
         , IsCash   = 1
         , IsOnline = 0
         , Provider = NULL
         , RequiresReference = 0
         , IsActive  = 1
         , IsDeleted = 0
     WHERE ID = 1;
    PRINT '3.1  ID 1 set to Cash on Delivery (IsOnline = 0)';
END
ELSE PRINT '3.1  !! No row with ID = 1 - check SECTION 1 output';

-- ID 2 : the online method, paid through MyFatoorah.
IF EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = 2)
BEGIN
    UPDATE dbo.tblInvoicePaymentType
       SET IsOnline = 1
         , IsCOD    = 0
         , IsCash   = 0
         , Provider = 'MyFatoorah'
         , RequiresReference = 1
         , IsActive  = 1
         , IsDeleted = 0
     WHERE ID = 2;
    PRINT '3.2  ID 2 set to online / MyFatoorah';
END
ELSE PRINT '3.2  !! No row with ID = 2 - check SECTION 1 output';
GO

-- Every other method stays off the customer's checkout until someone decides
-- which gateway it is paid through. An online method with no provider would
-- fail at the gateway step, which is the failure this file exists to remove.
UPDATE dbo.tblInvoicePaymentType
   SET IsOnline = 0
 WHERE ID NOT IN (1, 2)
   AND IsOnline = 1
   AND Provider IS NULL;
PRINT '3.3  Other IsOnline rows with no Provider switched off - see SECTION 5';
GO


/*==============================================================================
  SECTION 4 - sp_GetOnlinePaymentTypes, now returning Provider

  Same shape as POS_16 plus Provider, so the checkout can tell a gateway method
  from a cash one without inferring it from the name.
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
           , Provider
           , Seqnum
    FROM     dbo.tblInvoicePaymentType
    WHERE    ISNULL(IsDeleted, 0) = 0
      AND    ISNULL(IsActive, 1) = 1
      AND    ( IsOnline = 1 OR (@IncludeCOD = 1 AND IsCOD = 1) )
    ORDER BY Seqnum, ID;
END
GO

PRINT 'sp_GetOnlinePaymentTypes recreated (with Provider).';
GO


/*==============================================================================
  SECTION 5 - sp_POS_GetPaymentProvider

  Answers "which gateway does this order go to?" for PaymentLinkService.
  Returns one row: the provider name, or NULL when the method is not online.
  A caller that gets NULL must not contact any gateway.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetPaymentProvider') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetPaymentProvider;
GO

CREATE PROCEDURE dbo.sp_POS_GetPaymentProvider
      @PaymentTypeID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   PaymentTypeID = ID
           , PaymentTypeName
           , IsOnline      = CAST(ISNULL(IsOnline, 0) AS BIT)
           -- An inactive or deleted method reports no provider: it must not be
           -- possible to pay through a method that has been withdrawn.
           , Provider      = CASE WHEN ISNULL(IsOnline,0) = 1
                                   AND ISNULL(IsDeleted,0) = 0
                                   AND ISNULL(IsActive,1)  = 1
                                  THEN Provider ELSE NULL END
    FROM     dbo.tblInvoicePaymentType
    WHERE    ID = @PaymentTypeID;
END
GO

PRINT 'sp_POS_GetPaymentProvider created.';
GO


/*==============================================================================
  SECTION 6 - AFTER

  Expect exactly one row with ShownOnCheckout = YES (ID 2, MyFatoorah), and
  ID 1 showing OfferedAsCOD = YES. The checkout lists the online methods plus
  COD, because Payment.cshtml now posts includeCOD = true.
==============================================================================*/
PRINT '===== SECTION 6 : after =====';
SELECT   ID, PaymentTypeName, Provider
       , IsCash, IsCOD, IsOnline, IsActive, IsDeleted
       , ShownOnCheckout = CASE WHEN IsOnline = 1 THEN 'YES' ELSE 'no' END
       , OfferedAsCOD    = CASE WHEN IsCOD    = 1 THEN 'YES' ELSE 'no' END
FROM     dbo.tblInvoicePaymentType
ORDER BY ID;

PRINT '';
PRINT '--- exactly what the checkout page will list ---';
EXEC dbo.sp_GetOnlinePaymentTypes @IncludeCOD = 1;

PRINT '';
PRINT '--- gateway routing for the two pinned IDs ---';
EXEC dbo.sp_POS_GetPaymentProvider @PaymentTypeID = 1;
EXEC dbo.sp_POS_GetPaymentProvider @PaymentTypeID = 2;
GO

/*==============================================================================
  ONE THING THIS SCRIPT CANNOT DO

  MyFatoorah.ApiToken in Web.config is still empty, so ID 2 will fail at the
  gateway with "MyFatoorah.ApiToken is not set." Paste the token from the
  MyFatoorah portal (Integration Settings > API Key) and match BaseUrl to it:
      test token -> https://apitest.myfatoorah.com
      live token -> https://api.myfatoorah.com
==============================================================================*/
