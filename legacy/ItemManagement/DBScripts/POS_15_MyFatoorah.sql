/**********************************************************************************
  POS_15_MyFatoorah.sql
  ------------------------------------------------------------------------------
  MyFatoorah as a payment method.

      tblInvoicePaymentType        + MyFatoorah row
      tblPOS_PaymentLink           one row per payment attempt
      sp_POS_PaymentLink_Create    record an attempt before redirecting
      sp_POS_PaymentLink_Complete  credit the invoice, exactly once
      sp_POS_PaymentLink_Get       look an attempt up by reference

  WHY A LINK TABLE RATHER THAN JUST CALLING sp_POS_AddPayment
  -----------------------------------------------------------
  A hosted payment page can report success more than once, through more than
  one channel:

      * the customer is redirected back to CallBackUrl
      * MyFatoorah calls the webhook
      * the customer refreshes the callback page
      * an operator retries a link that had already been paid

  Without a record of the attempt, each of those credits the invoice again and
  the order ends up over-paid with no way to tell which entry was real. The
  Pending -> Paid transition here is a single conditional UPDATE, so only the
  first caller to win it books the payment. Everything after gets 'Duplicate'.

  Run after POS_09_ActionProcs.sql.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  1. Payment type
==============================================================================*/
IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE PaymentTypeName = N'MyFatoorah')
BEGIN
    INSERT INTO dbo.tblInvoicePaymentType
        (PaymentTypeName, PaymentTypeNameArb, Seqnum, IsActive, IsDeleted, createdon,
         IsCash, IsOnline, RequiresReference, IsCOD, LegacyColumn)
    VALUES
        (N'MyFatoorah', N'ماي فاتورة',
         ISNULL((SELECT MAX(Seqnum) FROM dbo.tblInvoicePaymentType), 0) + 1,
         1, 0, GETDATE(),
         0, 1, 1, 0,
         -- KNET and cards settle through MyFatoorah, so its takings belong in
         -- the K_NET legacy bucket the end-of-day report already reads.
         'K_NETAmount');
    PRINT '1.1  MyFatoorah payment type added';
END
ELSE PRINT '1.1  MyFatoorah payment type already exists';
GO

SELECT PaymentTypeID = ID, PaymentTypeName, IsOnline, RequiresReference, LegacyColumn
FROM   dbo.tblInvoicePaymentType WHERE PaymentTypeName = N'MyFatoorah';
GO


/*==============================================================================
  2. Payment attempts
==============================================================================*/
IF OBJECT_ID('dbo.tblPOS_PaymentLink') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_PaymentLink
    (
          LinkID            BIGINT IDENTITY(1,1) NOT NULL
        , InvoiceNo         BIGINT         NOT NULL
        , Provider          VARCHAR(30)    NOT NULL CONSTRAINT DF_PayLink_Provider DEFAULT ('MyFatoorah')
        , PaymentTypeID     INT            NULL
        -- our reference, sent as CustomerReference and echoed back by MyFatoorah
        , CustomerReference VARCHAR(60)    NOT NULL
        , ProviderInvoiceId VARCHAR(60)    NULL     -- MyFatoorah InvoiceId
        , ProviderPaymentId VARCHAR(60)    NULL     -- MyFatoorah PaymentId / transaction
        , Amount            DECIMAL(18,3)  NOT NULL
        , PaidAmount        DECIMAL(18,3)  NULL
        , CurrencyIso       VARCHAR(5)     NULL
        , PaymentUrl        NVARCHAR(1000) NULL
        , Status            VARCHAR(20)    NOT NULL CONSTRAINT DF_PayLink_Status DEFAULT ('Pending')
                                           -- Pending | Paid | Failed | Cancelled | Expired
        , FailureReason     NVARCHAR(500)  NULL
        , RawResponse       NVARCHAR(MAX)  NULL
        , CreatedBy         INT            NULL
        , CreatedOn         DATETIME       NOT NULL CONSTRAINT DF_PayLink_CreatedOn DEFAULT (GETDATE())
        , CompletedOn       DATETIME       NULL
        , CONSTRAINT PK_tblPOS_PaymentLink PRIMARY KEY CLUSTERED (LinkID)
    );

    -- The reference is how a callback or webhook finds its attempt. If two
    -- attempts could share one, a late callback could credit the wrong try.
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayLink_Reference
        ON dbo.tblPOS_PaymentLink (CustomerReference);

    CREATE NONCLUSTERED INDEX IX_PayLink_Invoice
        ON dbo.tblPOS_PaymentLink (InvoiceNo, Status) INCLUDE (Amount, CreatedOn);

    CREATE NONCLUSTERED INDEX IX_PayLink_ProviderInvoice
        ON dbo.tblPOS_PaymentLink (ProviderInvoiceId) WHERE ProviderInvoiceId IS NOT NULL;

    PRINT '2.1  tblPOS_PaymentLink created';
END
ELSE PRINT '2.1  tblPOS_PaymentLink already exists';
GO


/*==============================================================================
  3. sp_POS_PaymentLink_Create
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_PaymentLink_Create') IS NOT NULL DROP PROCEDURE dbo.sp_POS_PaymentLink_Create;
GO

CREATE PROCEDURE dbo.sp_POS_PaymentLink_Create
      @InvoiceNo         BIGINT
    , @CustomerReference VARCHAR(60)
    , @Amount            DECIMAL(18,3)
    , @CurrencyIso       VARCHAR(5)   = 'KWD'
    , @Provider          VARCHAR(30)  = 'MyFatoorah'
    , @PaymentTypeID     INT          = NULL
    , @CreatedBy         INT          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Due DECIMAL(18,3), @Paid DECIMAL(18,3), @Status INT, @Err NVARCHAR(400) = NULL;

    SELECT @Due = i.FinalAmount + ISNULL(i.DeliveryCharges,0), @Status = i.OrderStatusID
    FROM   dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @Due IS NULL                       SET @Err = N'Order not found.';
    ELSE IF @Status = 7                   SET @Err = N'Order is cancelled.';
    ELSE IF @Amount IS NULL OR @Amount <= 0 SET @Err = N'Amount must be greater than zero.';
    ELSE IF (@Paid + @Amount) > @Due + 0.001
        SET @Err = CONCAT(N'Amount exceeds the balance due. Due ', @Due, N', already paid ', @Paid, N'.');

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', LinkID=CAST(NULL AS BIGINT), ErrorMessage=@Err;
        RETURN;
    END

    -- An unfinished attempt for the same amount is reused rather than stacked:
    -- two live payment links for one order is how an order gets paid twice.
    DECLARE @LinkID BIGINT;

    SELECT TOP 1 @LinkID = LinkID
    FROM   dbo.tblPOS_PaymentLink
    WHERE  InvoiceNo = @InvoiceNo AND Status = 'Pending' AND Amount = @Amount
      AND  CreatedOn > DATEADD(MINUTE, -30, GETDATE())
    ORDER BY LinkID DESC;

    IF @LinkID IS NOT NULL
    BEGIN
        SELECT Message='Reused', LinkID=@LinkID, ErrorMessage=CAST(NULL AS NVARCHAR(400));
        RETURN;
    END

    INSERT INTO dbo.tblPOS_PaymentLink
        (InvoiceNo, Provider, PaymentTypeID, CustomerReference, Amount, CurrencyIso, CreatedBy)
    VALUES
        (@InvoiceNo, @Provider, @PaymentTypeID, @CustomerReference, @Amount, @CurrencyIso, @CreatedBy);

    SET @LinkID = CAST(SCOPE_IDENTITY() AS BIGINT);

    SELECT Message='Success', LinkID=@LinkID, ErrorMessage=CAST(NULL AS NVARCHAR(400));
END
GO


/*==============================================================================
  4. sp_POS_PaymentLink_SetProvider   (store what the gateway returned)
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_PaymentLink_SetProvider') IS NOT NULL DROP PROCEDURE dbo.sp_POS_PaymentLink_SetProvider;
GO

CREATE PROCEDURE dbo.sp_POS_PaymentLink_SetProvider
      @LinkID            BIGINT
    , @ProviderInvoiceId VARCHAR(60)
    , @PaymentUrl        NVARCHAR(1000) = NULL
    , @RawResponse       NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.tblPOS_PaymentLink
       SET ProviderInvoiceId = @ProviderInvoiceId
         , PaymentUrl        = @PaymentUrl
         , RawResponse       = @RawResponse
     WHERE LinkID = @LinkID;
END
GO


/*==============================================================================
  5. sp_POS_PaymentLink_Complete

  THE IDEMPOTENCY GUARD. The conditional UPDATE below is the whole point: only
  the first caller to move an attempt out of 'Pending' books the payment. The
  redirect, the webhook and a page refresh all race here, and only one wins.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_PaymentLink_Complete') IS NOT NULL DROP PROCEDURE dbo.sp_POS_PaymentLink_Complete;
GO

CREATE PROCEDURE dbo.sp_POS_PaymentLink_Complete
      @CustomerReference VARCHAR(60)
    , @Success           BIT
    , @ProviderPaymentId VARCHAR(60)   = NULL
    , @PaidAmount        DECIMAL(18,3) = NULL
    , @FailureReason     NVARCHAR(500) = NULL
    , @RawResponse       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LinkID BIGINT, @InvoiceNo BIGINT, @Amount DECIMAL(18,3),
            @PaymentTypeID INT, @Now DATETIME = GETDATE();

    SELECT @LinkID = LinkID, @InvoiceNo = InvoiceNo, @Amount = Amount, @PaymentTypeID = PaymentTypeID
    FROM   dbo.tblPOS_PaymentLink WHERE CustomerReference = @CustomerReference;

    IF @LinkID IS NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT),
               ErrorMessage=N'Unknown payment reference.';
        RETURN;
    END

    /*---- failure: record it, credit nothing --------------------------------*/
    IF @Success = 0
    BEGIN
        UPDATE dbo.tblPOS_PaymentLink
           SET Status = 'Failed', FailureReason = @FailureReason,
               RawResponse = ISNULL(@RawResponse, RawResponse), CompletedOn = @Now
         WHERE LinkID = @LinkID AND Status = 'Pending';

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'PaymentFailed', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Reason=', ISNULL(@FailureReason, N'')));

        SELECT Message='Failed', InvoiceNo=@InvoiceNo, ErrorMessage=@FailureReason;
        RETURN;
    END

    /*---- success: claim the attempt ---------------------------------------
      Only the caller whose UPDATE actually changes a row proceeds to book the
      payment. Anything arriving second sees @@ROWCOUNT = 0 and returns
      'Duplicate' without touching the ledger.
    ------------------------------------------------------------------------*/
    UPDATE dbo.tblPOS_PaymentLink
       SET Status            = 'Paid'
         , ProviderPaymentId = @ProviderPaymentId
         , PaidAmount        = ISNULL(@PaidAmount, Amount)
         , RawResponse       = ISNULL(@RawResponse, RawResponse)
         , CompletedOn       = @Now
     WHERE LinkID = @LinkID
       AND Status = 'Pending';          -- <= the guard

    IF @@ROWCOUNT = 0
    BEGIN
        SELECT Message='Duplicate', InvoiceNo=@InvoiceNo,
               ErrorMessage=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType
        WHERE PaymentTypeName = N'MyFatoorah' AND ISNULL(IsDeleted,0) = 0;

    -- Reuse sp_POS_AddPayment rather than inserting directly, so the legacy
    -- per-method columns and PaidDate stay in step with everything else.
    EXEC dbo.sp_POS_AddPayment
          @InvoiceNo     = @InvoiceNo
        , @PaymentTypeID = @PaymentTypeID
        , @Amount        = @Amount
        , @ReferenceNo   = @ProviderPaymentId
        , @IsRefund      = 0
        , @UserName      = N'MyFatoorah'
        , @Comments      = @CustomerReference;

    -- A gateway that reports a different figure to the one requested is worth
    -- knowing about; it is logged rather than silently accepted.
    IF @PaidAmount IS NOT NULL AND ABS(@PaidAmount - @Amount) > 0.001
        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'PaymentAmountMismatch', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Requested=', @Amount, N' Reported=', @PaidAmount));

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500));
END
GO


/*==============================================================================
  6. sp_POS_PaymentLink_Get
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_PaymentLink_Get') IS NOT NULL DROP PROCEDURE dbo.sp_POS_PaymentLink_Get;
GO

CREATE PROCEDURE dbo.sp_POS_PaymentLink_Get
      @LinkID            BIGINT      = NULL
    , @CustomerReference VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT   l.LinkID, l.InvoiceNo, l.Provider, l.PaymentTypeID, l.CustomerReference
           , l.ProviderInvoiceId, l.ProviderPaymentId, l.Amount, l.PaidAmount
           , l.CurrencyIso, l.PaymentUrl, l.Status, l.FailureReason
           , l.CreatedOn, l.CompletedOn
           , CustomerName = i.CustomerName
           , Mobile       = i.MobileText
    FROM     dbo.tblPOS_PaymentLink l
    LEFT JOIN dbo.tblInvoice i ON i.InvoiceNo = l.InvoiceNo
    WHERE    (@LinkID IS NULL            OR l.LinkID = @LinkID)
      AND    (@CustomerReference IS NULL OR l.CustomerReference = @CustomerReference);
END
GO

PRINT 'MyFatoorah objects created.';
GO

/* Useful later:
   SELECT TOP 20 LinkID, InvoiceNo, CustomerReference, Amount, Status,
                 ProviderInvoiceId, ProviderPaymentId, CreatedOn, CompletedOn
   FROM   dbo.tblPOS_PaymentLink ORDER BY LinkID DESC;

   -- attempts that never came back; chase these with GetPaymentStatus
   SELECT * FROM dbo.tblPOS_PaymentLink
   WHERE Status = 'Pending' AND CreatedOn < DATEADD(MINUTE,-30,GETDATE());
*/
