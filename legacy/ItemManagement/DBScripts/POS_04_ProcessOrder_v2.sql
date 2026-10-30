/**********************************************************************************
  POS_04_ProcessOrder_v2.sql
  ------------------------------------------------------------------------------
  Replaces sp_POS_ProcessOrder from POS_02. Run AFTER POS_03_Reconcile.sql.

  WHAT CHANGED vs POS_02
  ----------------------
  1. Uses the head-office lookups (tblOrderStatus, tblInvoicePaymentType,
     tblInvoiceType_Master) instead of the dropped tblPOS_* duplicates.

  2. DISCOUNT IS NOW CALCULATED SERVER-SIDE from tblDiscountCode +
     tblDiscount_Type. The browser previously posted InvoiceDiscount as a plain
     number, so anyone could send any discount they liked. The posted value is
     now only a fallback for when no code was used.

  3. Validates the delivery area against TblArea_Mapping, so an order is not
     silently routed to a branch that does not serve that area. Reported as a
     Warning rather than a hard failure -- rejecting at the final click loses
     the sale; the POS should surface it instead.

  4. Records prepaid (KNET / Visa / online) payments into tblInvoicePayment and
     mirrors them into the legacy per-method column on tblInvoice
     (CashAmount / K_NETAmount / VisaAmount / ...), so the existing end-of-day
     and shift reports keep working unchanged.

  NOTE ON FinalAmount
  -------------------
  FinalAmount stays a computed column = BillAmount - Discount, i.e. WITHOUT
  DeliveryCharges (confirmed decision). The amount the customer actually pays is
  returned separately as NetPayable = FinalAmount + DeliveryCharges. Anything
  that shows a total to a customer -- receipt, POS grid, tracking page -- must
  use NetPayable, not FinalAmount.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_ProcessOrder') IS NOT NULL DROP PROCEDURE dbo.sp_POS_ProcessOrder;
GO

CREATE PROCEDURE dbo.sp_POS_ProcessOrder
      @BranchID          INT
    , @BrandID           INT
    , @InvoiceTypeID     INT            = NULL        -- NULL = resolve 'QR Menu Online'
    , @OrderType         INT            = 2           -- 1 Pickup, 2 Delivery, 3 Dine-in
    , @SourceID          INT            = 1

    , @CustomerId        INT            = NULL
    , @CustomerName      NVARCHAR(200)  = NULL
    , @Mobile            NVARCHAR(30)   = NULL
    , @Mobile2           NVARCHAR(30)   = NULL
    , @Email             NVARCHAR(100)  = NULL
    , @CivilID           NVARCHAR(50)   = NULL

    , @AddressID         INT            = NULL
    , @AreaID            INT            = NULL
    , @Block             NVARCHAR(50)   = NULL
    , @Street            NVARCHAR(500)  = NULL
    , @Lane              NVARCHAR(100)  = NULL
    , @Building          NVARCHAR(50)   = NULL
    , @Floor             NVARCHAR(50)   = NULL
    , @Flat              NVARCHAR(50)   = NULL
    , @HouseNo           NVARCHAR(50)   = NULL
    , @PACI              NVARCHAR(50)   = NULL
    , @AddressRemark     NVARCHAR(500)  = NULL
    , @Lat               NVARCHAR(50)   = NULL
    , @Lng               NVARCHAR(50)   = NULL

    , @DeliveryDate      DATETIME       = NULL
    , @PaymentTypeID     INT            = NULL        -- NULL = resolve 'Cash on Delivery'
    , @IsPrepaid         BIT            = 0           -- 1 = money already taken online
    , @PaymentReference  NVARCHAR(100)  = NULL
    , @DiscountTypeID    INT            = 0
    , @InvoiceDiscount   DECIMAL(18,3)  = 0           -- fallback only; a code overrides it
    , @DiscountCode      NVARCHAR(50)   = NULL
    , @DeliveryCharges   DECIMAL(18,3)  = NULL        -- NULL = derive from tblArea
    , @WaiterID          INT            = 0
    , @Comments          NVARCHAR(500)  = NULL
    , @ClientOrderGuid   UNIQUEIDENTIFIER = NULL

    , @dtOrderItems      dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceNo     BIGINT
          , @TrackingCode  VARCHAR(12)
          , @RunningOrder  INT
          , @BillAmount    DECIMAL(18,3) = 0
          , @Discount      DECIMAL(18,3) = 0
          , @Today         DATE     = CAST(GETDATE() AS DATE)
          , @Now           DATETIME = GETDATE()
          , @Warning       NVARCHAR(500) = NULL
          , @PriceMismatch INT = 0
          , @LegacyCol     SYSNAME = NULL
          , @IsCOD         BIT = 0;

    /*----------------------------------------------------------------------
      Shared shape for every early return
    ----------------------------------------------------------------------*/
    DECLARE @FailMsg NVARCHAR(500);

    /*======================================================================
      0. VALIDATION
    ======================================================================*/
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems) SET @FailMsg = N'Cart is empty.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0)
        SET @FailMsg = N'Invalid or inactive branch.';

    IF @FailMsg IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=@FailMsg;
        RETURN;
    END

    /*======================================================================
      1. RESOLVE LOOKUPS BY MEANING, NOT BY HARD-CODED ID

      The head-office tables use IDENTITY keys, so the actual IDs differ per
      deployment. Resolving by name here means the proc works against any
      seeded set without a code change.
    ======================================================================*/
    -- The real head-office channel list is:
    --   1 On Line Order | 2 Dine In | 3 Take Away | 4 Call Centre | 5 Talabat
    -- 'On Line Order' IS the QR menu channel.
    IF @InvoiceTypeID IS NULL
        SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master
        WHERE  Name IN (N'On Line Order', N'Online Order', N'QR Menu Online')
        ORDER BY ID;

    -- Deliberately NO fallback to Call Centre. Filing a QR order as a
    -- call-centre order is worse than leaving the channel unset: it is
    -- invisible, and it corrupts every channel report from that point on.

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCOD = 1 AND ISNULL(IsDeleted,0)=0;
    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCash = 1 AND ISNULL(IsDeleted,0)=0;

    IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID AND ISNULL(IsDeleted,0)=0)
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'Unknown payment type.';
        RETURN;
    END

    SELECT @LegacyCol = LegacyColumn, @IsCOD = IsCOD
    FROM   dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID;

    /*======================================================================
      2. IDEMPOTENCY
    ======================================================================*/
    IF @ClientOrderGuid IS NOT NULL
    BEGIN
        SELECT @InvoiceNo = InvoiceNo FROM dbo.tblInvoice WHERE ClientOrderGuid = @ClientOrderGuid;

        IF @InvoiceNo IS NOT NULL
        BEGIN
            SELECT Message='Duplicate', InvoiceNo=i.InvoiceNo, TrackingCode=i.TrackingCode,
                   RunningOrder=i.RunningOrder, BillAmount=i.BillAmount, Discount=i.Discount,
                   DeliveryCharges=ISNULL(i.DeliveryCharges,0),
                   FinalAmount=i.FinalAmount,
                   NetPayable=i.FinalAmount + ISNULL(i.DeliveryCharges,0),
                   CustomerId=i.CustomerId, AddressID=i.AddressID, PaymentTypeID=i.PaymentType,
                   Warning=CAST(NULL AS NVARCHAR(500)), ErrorMessage=CAST(NULL AS NVARCHAR(500))
            FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;
            RETURN;
        END
    END

    /*======================================================================
      3. RE-PRICE FROM tblItems
    ======================================================================*/
    DECLARE @lines TABLE
    (
          Seq            INT IDENTITY(1,1) PRIMARY KEY
        , ResolvedItemID INT           NULL
        , ItemName       NVARCHAR(200) NULL
        , Quantity       INT           NOT NULL
        , UnitPrice      DECIMAL(18,3) NOT NULL
        , ClientPrice    DECIMAL(18,3) NULL
        , LineType       TINYINT       NOT NULL
        , ParentItemID   INT           NULL
        , CartItemUniqID INT           NULL
        , Comments       NVARCHAR(MAX) NULL
        , Extra          NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, ClientPrice, LineType, ParentItemID, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, ISNULL(d.Price,0)) AS DECIMAL(18,3))
          , d.Price, d.LineType, d.ParentItemID, d.CartItemUniqID, d.Comments, d.Extra
    FROM        @dtOrderItems d
    OUTER APPLY (
                    SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE
                    FROM   dbo.tblItems t
                    WHERE  (d.ItemID IS NOT NULL AND t.ID  = d.ItemID)
                        OR (d.HID    IS NOT NULL AND t.HID = d.HID)
                        OR (d.ItemID IS NOT NULL AND t.HID = d.ItemID)
                    ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END
                ) it;

    SELECT @PriceMismatch = COUNT(*) FROM @lines
    WHERE  ClientPrice IS NOT NULL AND ABS(ClientPrice - UnitPrice) > 0.001;

    SELECT @BillAmount = CAST(ISNULL(SUM(Quantity * UnitPrice),0) AS DECIMAL(18,3)) FROM @lines;

    IF @BillAmount <= 0
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'No priceable items resolved from the cart.';
        RETURN;
    END

    /*======================================================================
      4. DISCOUNT - computed here, never trusted from the browser
    ======================================================================*/
    IF NULLIF(LTRIM(RTRIM(@DiscountCode)),'') IS NOT NULL
    BEGIN
        DECLARE @dtId INT, @dtPct INT, @dtIsPct BIT;

        SELECT TOP 1 @dtId = dt.Id, @dtPct = dt.DiscountPercentage, @dtIsPct = dt.isPercentage
        FROM   dbo.tblDiscountCode dc
        JOIN   dbo.tblDiscount_Type dt ON dt.Id = dc.DiscountTypeId
        WHERE  dc.DiscountCode = @DiscountCode
          AND  ISNULL(dc.Isactive,0) = 1
          AND  ISNULL(dt.IsActive,0) = 1
          AND  ISNULL(dt.IsDeleted,0) = 0;

        IF @dtId IS NULL
        BEGIN
            SET @Discount = 0;
            SET @Warning  = N'Discount code not valid - no discount applied.';
        END
        ELSE
        BEGIN
            SET @DiscountTypeID = @dtId;
            SET @Discount = CASE WHEN ISNULL(@dtIsPct,0) = 1
                                 THEN CAST(@BillAmount * ISNULL(@dtPct,0) / 100.0 AS DECIMAL(18,3))
                                 ELSE CAST(ISNULL(@dtPct,0) AS DECIMAL(18,3))
                            END;
        END
    END
    ELSE IF @DiscountTypeID > 0
    BEGIN
        SELECT TOP 1 @Discount = CASE WHEN ISNULL(dt.isPercentage,0) = 1
                                      THEN CAST(@BillAmount * ISNULL(dt.DiscountPercentage,0) / 100.0 AS DECIMAL(18,3))
                                      ELSE CAST(ISNULL(dt.DiscountPercentage,0) AS DECIMAL(18,3)) END
        FROM   dbo.tblDiscount_Type dt
        WHERE  dt.Id = @DiscountTypeID AND ISNULL(dt.IsActive,0)=1 AND ISNULL(dt.IsDeleted,0)=0;

        SET @Discount = ISNULL(@Discount, 0);
    END
    ELSE
        SET @Discount = ISNULL(@InvoiceDiscount, 0);   -- legacy fallback

    IF @Discount < 0 SET @Discount = 0;
    IF @Discount > @BillAmount SET @Discount = @BillAmount;

    /*======================================================================
      5. DELIVERY CHARGE + AREA / BRANCH VALIDATION
    ======================================================================*/
    IF @OrderType = 2
    BEGIN
        IF @DeliveryCharges IS NULL
            SELECT @DeliveryCharges = ISNULL(a.DeliveryCharges,0) FROM dbo.tblArea a WHERE a.AreaID = @AreaID;

        SET @DeliveryCharges = ISNULL(@DeliveryCharges, 0);

        -- Does this branch actually serve this area?
        IF @AreaID IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID)
           AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @BranchID)
        BEGIN
            SET @Warning = ISNULL(@Warning + N' ', N'')
                         + N'Branch does not serve this delivery area - review or transfer the order.';
        END
    END
    ELSE
        SET @DeliveryCharges = 0;

    /*======================================================================
      6. TRANSACTION
    ======================================================================*/
    BEGIN TRY
        BEGIN TRANSACTION;

        /*---- 6.1 Customer -----------------------------------------------*/
        IF @CustomerId IS NULL AND NULLIF(LTRIM(RTRIM(@Mobile)),'') IS NOT NULL
            SELECT TOP 1 @CustomerId = id FROM dbo.tblCustomer WITH (UPDLOCK, HOLDLOCK)
            WHERE mobile = @Mobile AND IsDeleted = 0;

        IF @CustomerId IS NULL
        BEGIN
            INSERT INTO dbo.tblCustomer (firstName, mobile, Mobile2, email, CivilID, areaId, block, street, building, flat, landmark, BrandID)
            VALUES (@CustomerName, @Mobile, @Mobile2, @Email, @CivilID, @AreaID, @Block, @Street, @Building, @Flat, @AddressRemark, @BrandID);
            SET @CustomerId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE dbo.tblCustomer
               SET firstName  = COALESCE(NULLIF(@CustomerName,''), firstName)
                 , email      = COALESCE(NULLIF(@Email,''),        email)
                 , Mobile2    = COALESCE(NULLIF(@Mobile2,''),      Mobile2)
                 , ModifiedOn = @Now
             WHERE id = @CustomerId;

        /*---- 6.2 Address ------------------------------------------------*/
        IF @OrderType = 2 AND @AddressID IS NULL
           AND (@AreaID IS NOT NULL OR NULLIF(@Block,'') IS NOT NULL OR NULLIF(@Street,'') IS NOT NULL)
        BEGIN
            SELECT TOP 1 @AddressID = AddressID FROM dbo.tblCustomerAddress
            WHERE CustomerID = @CustomerId AND IsDeleted = 0
              AND ISNULL(AreaID,-1)   = ISNULL(@AreaID,-1)
              AND ISNULL(Block,'')    = ISNULL(@Block,'')
              AND ISNULL(Street,'')   = ISNULL(@Street,'')
              AND ISNULL(Building,'') = ISNULL(@Building,'')
              AND ISNULL(Flat,'')     = ISNULL(@Flat,'');

            IF @AddressID IS NULL
            BEGIN
                INSERT INTO dbo.tblCustomerAddress
                    (CustomerID, AreaID, Block, Street, Lane, Building, Floor, Flat, HouseNo, PACI, AddressRemark, Lat, Lng, Email)
                VALUES (@CustomerId, @AreaID, @Block, @Street, @Lane, @Building, @Floor, @Flat, @HouseNo, @PACI, @AddressRemark, @Lat, @Lng, @Email);
                SET @AddressID = CAST(SCOPE_IDENTITY() AS INT);
            END
        END

        /*---- 6.3 Daily per-branch number --------------------------------*/
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @RunningOrder = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;

        IF @RunningOrder IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @RunningOrder = 1;
        END

        /*---- 6.4 Invoice header -----------------------------------------*/
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate
        )
        VALUES
        (
              @WaiterID, @BillAmount, @Discount, @Comments, 1, 0
            , @Now, @Now, @PaymentTypeID, 0
            , TRY_CAST(REPLACE(REPLACE(ISNULL(@Mobile,''),'+',''),' ','') AS BIGINT), @Mobile
            , @CustomerName, 1, @CustomerId, 1, 0                     -- OrderStatusID 1 = Received
            , @BranchID, @AddressID, @BrandID, @DeliveryDate, @InvoiceTypeID
            , @DiscountTypeID, @DeliveryCharges, @OrderType, NULL
            , @ClientOrderGuid, @DiscountCode, @SourceID, @RunningOrder
            , DATEADD(MINUTE, ISNULL((SELECT DefaultPrepMinutes FROM dbo.tblPOS_BranchSetting WHERE BranchID=@BranchID),20), @Now)
            , 0, CASE WHEN @IsPrepaid = 1 THEN @Now ELSE NULL END
        );

        SET @InvoiceNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        /*---- 6.5 Tracking code ------------------------------------------*/
        DECLARE @seed BIGINT = @InvoiceNo * 2654435761 % 456976;
        SET @TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                          + CHAR(65 + (@seed/26)%26)    + CHAR(65 +  @seed%26)
                          + '-' + RIGHT('0000' + CAST(@InvoiceNo % 10000 AS VARCHAR(4)), 4);

        UPDATE dbo.tblInvoice SET TrackingCode = @TrackingCode WHERE InvoiceNo = @InvoiceNo;

        /*---- 6.6 Order lines --------------------------------------------*/
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , @WaiterID, 0, 0, 0, 0, 0
             , @Now, 0, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;

        /*---- 6.7 Prepaid payment ----------------------------------------
          Money already taken online is recorded now. Cash / COD stays unpaid
          until the POS Pay action collects it.
        -----------------------------------------------------------------*/
        IF @IsPrepaid = 1
        BEGIN
            DECLARE @Paid DECIMAL(18,3) = (@BillAmount - @Discount) + @DeliveryCharges;

            INSERT INTO dbo.tblInvoicePayment
                (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, ReferenceNo, IsRefund, ReceivedOn, isdeleted)
            SELECT @PaymentTypeID, @InvoiceNo, pt.PaymentTypeName, @BranchID, @Paid, @PaymentReference, 0, @Now, 0
            FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID;

            -- Mirror into the legacy per-method column so end-of-day reports still add up.
            IF @LegacyCol IS NOT NULL
            BEGIN
                DECLARE @sql NVARCHAR(MAX) =
                    N'UPDATE dbo.tblInvoice SET ' + QUOTENAME(@LegacyCol) + N' = @amt WHERE InvoiceNo = @inv;';
                EXEC sp_executesql @sql, N'@amt DECIMAL(18,3), @inv BIGINT', @amt = @Paid, @inv = @InvoiceNo;
            END
        END

        /*---- 6.8 Status history + audit ---------------------------------*/
        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        VALUES (@InvoiceNo, 0, 1, NULL, N'System', N'Order placed from QR Menu');

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Create', N'QRMenu',
                CONCAT(N'Branch=', @BranchID, N'; Lines=', (SELECT COUNT(*) FROM @lines),
                       N'; Bill=', @BillAmount, N'; Disc=', @Discount,
                       N'; Deliv=', @DeliveryCharges,
                       N'; PriceMismatchLines=', @PriceMismatch,
                       N'; Warning=', ISNULL(@Warning,N'none')));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(500) = ERROR_MESSAGE();

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', NULL, 'CreateFailed', N'QRMenu', @err);

        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=@Warning, ErrorMessage=@err;
        RETURN;
    END CATCH

    /*======================================================================
      7. RESULT
         FinalAmount = BillAmount - Discount        (matches the DB column)
         NetPayable  = FinalAmount + DeliveryCharges (what the customer pays)
    ======================================================================*/
    SELECT Message         = 'Success'
         , InvoiceNo       = @InvoiceNo
         , TrackingCode    = @TrackingCode
         , RunningOrder    = @RunningOrder
         , BillAmount      = @BillAmount
         , Discount        = @Discount
         , DeliveryCharges = @DeliveryCharges
         , FinalAmount     = @BillAmount - @Discount
         , NetPayable      = (@BillAmount - @Discount) + @DeliveryCharges
         , CustomerId      = @CustomerId
         , AddressID       = @AddressID
         , PaymentTypeID   = @PaymentTypeID
         , Warning         = @Warning
         , ErrorMessage    = CAST(NULL AS NVARCHAR(500));
END
GO

PRINT 'sp_POS_ProcessOrder (v2) created.';
GO

/**********************************************************************************
  SMOKE TEST
**********************************************************************************/
/*
DECLARE @items dbo.TVP_POS_OrderItem;
INSERT INTO @items (ItemID, HID, ParentItemID, CartItemUniqID, LineType, Quantity, Price, Comments, Extra)
SELECT TOP 2 ID, HID, NULL, ROW_NUMBER() OVER (ORDER BY ID), 1, 2, PRICE, NULL, NULL
FROM dbo.tblItems WHERE PRICE > 0 AND ISNULL(IsActive,1) = 1;

DECLARE @g UNIQUEIDENTIFIER = NEWID();

EXEC dbo.sp_POS_ProcessOrder
      @BranchID=1, @BrandID=1, @OrderType=2
    , @CustomerName=N'Test Customer', @Mobile=N'96560770626'
    , @AreaID=1, @Block=N'4', @Street=N'Test Street'
    , @ClientOrderGuid=@g, @dtOrderItems=@items;

-- Run the SAME EXEC again: must return Message='Duplicate' and create nothing new.
EXEC dbo.sp_POS_ProcessOrder
      @BranchID=1, @BrandID=1, @OrderType=2
    , @CustomerName=N'Test Customer', @Mobile=N'96560770626'
    , @AreaID=1, @Block=N'4', @Street=N'Test Street'
    , @ClientOrderGuid=@g, @dtOrderItems=@items;

SELECT TOP 5 InvoiceNo, TrackingCode, RunningOrder, BillAmount, Discount, DeliveryCharges,
             FinalAmount, FinalAmount + ISNULL(DeliveryCharges,0) AS NetPayable,
             OrderStatusID, PaymentType, CustomerId, AddressID
FROM dbo.tblInvoice ORDER BY InvoiceNo DESC;

SELECT * FROM dbo.tblOrder ORDER BY OrderID DESC;
SELECT * FROM dbo.tblPOS_OrderStatusHistory ORDER BY HistoryID DESC;
SELECT TOP 5 * FROM dbo.tblPOS_AuditLog ORDER BY AuditID DESC;
*/
