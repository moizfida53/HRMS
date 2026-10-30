/**********************************************************************************
  POS_02_ProcessOrder.sql
  ------------------------------------------------------------------------------
  sp_POS_ProcessOrder - replaces the HTTP call to
      {CallCenterUrl}/DmToCallCenterServices/ProcessOrderHD
  made by ItemsViewController.SubmitOrder (lines ~603-631).

  Run POS_01_Schema.sql first.

  RETURNS a single-row result set (not OUTPUT params) so it works with the
  existing DB.ExecuteStoredProcDataSet helper unchanged:

      Message ('Success' | 'Duplicate' | 'Fail'), InvoiceNo, TrackingCode,
      RunningOrder, BillAmount, Discount, DeliveryCharges, NetAmount, CustomerId,
      AddressID, ErrorMessage

  ------------------------------------------------------------------------------
  DESIGN NOTES
  ------------------------------------------------------------------------------
  * PRICES ARE RECOMPUTED FROM tblItems. The price posted by the browser is
    accepted only as a fallback when the item cannot be resolved, and the proc
    reports the mismatch. The current API-based flow trusts the browser price
    outright, which is an order-tampering hole; this closes it.

  * IDENTITY, not MAX()+1. tblInvoice.InvoiceNo is already BIGINT IDENTITY, so
    invoice numbering is race-free for free. The human-facing daily number
    (RunningOrder) is issued from tblPOS_DailyCounter under UPDLOCK/HOLDLOCK.

  * IDEMPOTENT via @ClientOrderGuid. A double-tap on "Process Order", or a
    retried request after a timeout, returns the ORIGINAL invoice instead of
    creating a second one.

  * FinalAmount and Change on tblInvoice, and TotalAmount on tblOrder, are
    COMPUTED columns and are therefore never written to here. Run
    POS_00b_ComputedCols.sql and confirm whether FinalAmount includes
    DeliveryCharges -- see the marked block in section 6.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_ProcessOrder') IS NOT NULL
    DROP PROCEDURE dbo.sp_POS_ProcessOrder;
GO

CREATE PROCEDURE dbo.sp_POS_ProcessOrder
      @BranchID          INT
    , @BrandID           INT
    , @InvoiceTypeID     INT            = 11          -- 11 = QR Menu Online
    , @OrderType         INT            = 2           -- 1 Pickup, 2 Delivery, 3 Dine-in
    , @SourceID          INT            = 1           -- 1 = QR Menu

    -- customer
    , @CustomerId        INT            = NULL
    , @CustomerName      NVARCHAR(200)  = NULL
    , @Mobile            NVARCHAR(30)   = NULL
    , @Mobile2           NVARCHAR(30)   = NULL
    , @Email             NVARCHAR(100)  = NULL
    , @CivilID           NVARCHAR(50)   = NULL

    -- address (delivery only)
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

    -- order
    , @DeliveryDate      DATETIME       = NULL
    , @PaymentTypeID     INT            = 4           -- 4 = Cash on Delivery
    , @DiscountTypeID    INT            = 0
    , @InvoiceDiscount   DECIMAL(18,3)  = 0
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

    DECLARE @InvoiceNo      BIGINT
          , @TrackingCode   VARCHAR(12)
          , @RunningOrder   INT
          , @BillAmount     DECIMAL(18,3) = 0
          , @Today          DATE = CAST(GETDATE() AS DATE)
          , @Now            DATETIME = GETDATE()
          , @PriceMismatch  INT = 0;

    /*======================================================================
      0. VALIDATION - fail fast, before opening a transaction
    ======================================================================*/
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems)
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = CAST(NULL AS BIGINT), TrackingCode = CAST(NULL AS VARCHAR(12)),
               RunningOrder = CAST(NULL AS INT), BillAmount = CAST(0 AS DECIMAL(18,3)),
               Discount = CAST(0 AS DECIMAL(18,3)), DeliveryCharges = CAST(0 AS DECIMAL(18,3)),
               NetAmount = CAST(0 AS DECIMAL(18,3)), CustomerId = CAST(NULL AS INT),
               AddressID = CAST(NULL AS INT), ErrorMessage = 'Cart is empty.';
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0)
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = CAST(NULL AS BIGINT), TrackingCode = CAST(NULL AS VARCHAR(12)),
               RunningOrder = CAST(NULL AS INT), BillAmount = CAST(0 AS DECIMAL(18,3)),
               Discount = CAST(0 AS DECIMAL(18,3)), DeliveryCharges = CAST(0 AS DECIMAL(18,3)),
               NetAmount = CAST(0 AS DECIMAL(18,3)), CustomerId = CAST(NULL AS INT),
               AddressID = CAST(NULL AS INT), ErrorMessage = 'Invalid or inactive branch.';
        RETURN;
    END

    /*======================================================================
      1. IDEMPOTENCY - has this exact submission already been processed?
    ======================================================================*/
    IF @ClientOrderGuid IS NOT NULL
    BEGIN
        SELECT @InvoiceNo = InvoiceNo FROM dbo.tblInvoice WHERE ClientOrderGuid = @ClientOrderGuid;

        IF @InvoiceNo IS NOT NULL
        BEGIN
            SELECT Message         = 'Duplicate'
                 , InvoiceNo       = i.InvoiceNo
                 , TrackingCode    = i.TrackingCode
                 , RunningOrder    = i.RunningOrder
                 , BillAmount      = i.BillAmount
                 , Discount        = i.Discount
                 , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
                 , NetAmount       = i.BillAmount - ISNULL(i.Discount,0) + ISNULL(i.DeliveryCharges,0)
                 , CustomerId      = i.CustomerId
                 , AddressID       = i.AddressID
                 , ErrorMessage    = CAST(NULL AS NVARCHAR(500))
            FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;
            RETURN;
        END
    END

    /*======================================================================
      2. RE-PRICE SERVER SIDE

      The client currently posts tblItems.HID as the item identifier (see
      ItemsViewController.SubmitOrder: ItemID = dtRow["HID"]). Because the
      order now lands in THIS database rather than the head-office one,
      tblOrder.ItemID should hold tblItems.ID. Both are resolved here:
      exact ID match wins, HID is the fallback.
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

    INSERT INTO @lines
        (ResolvedItemID, ItemName, Quantity, UnitPrice, ClientPrice, LineType, ParentItemID, CartItemUniqID, Comments, Extra)
    SELECT
          ResolvedItemID = it.ID
        , ItemName       = it.ITEM_NAME
        , Quantity       = CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          -- authoritative price from the item master; client price only if unresolved
        , UnitPrice      = CAST(ISNULL(it.PRICE, ISNULL(d.Price, 0)) AS DECIMAL(18,3))
        , ClientPrice    = d.Price
        , LineType       = d.LineType
        , ParentItemID   = d.ParentItemID
        , CartItemUniqID = d.CartItemUniqID
        , Comments       = d.Comments
        , Extra          = d.Extra
    FROM        @dtOrderItems d
    OUTER APPLY (
                    SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE
                    FROM   dbo.tblItems t
                    WHERE  ( d.ItemID IS NOT NULL AND t.ID  = d.ItemID )
                        OR ( d.HID    IS NOT NULL AND t.HID = d.HID    )
                        OR ( d.ItemID IS NOT NULL AND t.HID = d.ItemID )
                    ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END   -- prefer exact ID
                ) it;

    -- Report (do not silently swallow) any line where the browser price differed
    SELECT @PriceMismatch = COUNT(*)
    FROM   @lines
    WHERE  ClientPrice IS NOT NULL
      AND  ABS(ClientPrice - UnitPrice) > 0.001;

    SELECT @BillAmount = CAST(ISNULL(SUM(Quantity * UnitPrice), 0) AS DECIMAL(18,3)) FROM @lines;

    IF @BillAmount <= 0
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = CAST(NULL AS BIGINT), TrackingCode = CAST(NULL AS VARCHAR(12)),
               RunningOrder = CAST(NULL AS INT), BillAmount = CAST(0 AS DECIMAL(18,3)),
               Discount = CAST(0 AS DECIMAL(18,3)), DeliveryCharges = CAST(0 AS DECIMAL(18,3)),
               NetAmount = CAST(0 AS DECIMAL(18,3)), CustomerId = CAST(NULL AS INT),
               AddressID = CAST(NULL AS INT),
               ErrorMessage = N'No priceable items resolved from the cart.';
        RETURN;
    END

    -- Discount can never exceed the bill
    SET @InvoiceDiscount = CASE
                             WHEN ISNULL(@InvoiceDiscount,0) < 0 THEN 0
                             WHEN @InvoiceDiscount > @BillAmount THEN @BillAmount
                             ELSE @InvoiceDiscount
                           END;

    -- Delivery charge from the area master unless explicitly supplied
    IF @DeliveryCharges IS NULL
    BEGIN
        IF @OrderType = 2
            SELECT @DeliveryCharges = ISNULL(a.DeliveryCharges, 0)
            FROM   dbo.tblArea a WHERE a.AreaID = @AreaID;

        SET @DeliveryCharges = ISNULL(@DeliveryCharges, 0);
    END
    IF @OrderType <> 2 SET @DeliveryCharges = 0;   -- pickup / dine-in never carry delivery

    /*======================================================================
      3. TRANSACTION
    ======================================================================*/
    BEGIN TRY
        BEGIN TRANSACTION;

        /*---- 3.1 Customer: find by mobile, else create ------------------*/
        IF @CustomerId IS NULL AND NULLIF(LTRIM(RTRIM(@Mobile)),'') IS NOT NULL
            SELECT TOP 1 @CustomerId = id
            FROM   dbo.tblCustomer WITH (UPDLOCK, HOLDLOCK)
            WHERE  mobile = @Mobile AND IsDeleted = 0;

        IF @CustomerId IS NULL
        BEGIN
            INSERT INTO dbo.tblCustomer (firstName, mobile, Mobile2, email, CivilID, areaId, block, street, building, flat, landmark, BrandID)
            VALUES (@CustomerName, @Mobile, @Mobile2, @Email, @CivilID, @AreaID, @Block, @Street, @Building, @Flat, @AddressRemark, @BrandID);

            SET @CustomerId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            -- keep the newest name/email we were given
            UPDATE dbo.tblCustomer
               SET firstName  = COALESCE(NULLIF(@CustomerName,''), firstName)
                 , email      = COALESCE(NULLIF(@Email,''),        email)
                 , Mobile2    = COALESCE(NULLIF(@Mobile2,''),      Mobile2)
                 , ModifiedOn = @Now
             WHERE id = @CustomerId;
        END

        /*---- 3.2 Address (delivery only) --------------------------------*/
        IF @OrderType = 2 AND @AddressID IS NULL
           AND (@AreaID IS NOT NULL OR NULLIF(@Block,'') IS NOT NULL OR NULLIF(@Street,'') IS NOT NULL)
        BEGIN
            -- reuse an identical saved address rather than piling up duplicates
            SELECT TOP 1 @AddressID = AddressID
            FROM   dbo.tblCustomerAddress
            WHERE  CustomerID = @CustomerId AND IsDeleted = 0
              AND  ISNULL(AreaID,-1)   = ISNULL(@AreaID,-1)
              AND  ISNULL(Block,'')    = ISNULL(@Block,'')
              AND  ISNULL(Street,'')   = ISNULL(@Street,'')
              AND  ISNULL(Building,'') = ISNULL(@Building,'')
              AND  ISNULL(Flat,'')     = ISNULL(@Flat,'');

            IF @AddressID IS NULL
            BEGIN
                INSERT INTO dbo.tblCustomerAddress
                    (CustomerID, AreaID, Block, Street, Lane, Building, Floor, Flat, HouseNo, PACI, AddressRemark, Lat, Lng, Email)
                VALUES
                    (@CustomerId, @AreaID, @Block, @Street, @Lane, @Building, @Floor, @Flat, @HouseNo, @PACI, @AddressRemark, @Lat, @Lng, @Email);

                SET @AddressID = CAST(SCOPE_IDENTITY() AS INT);
            END
        END

        /*---- 3.3 Daily per-branch running number ------------------------
          UPDLOCK + HOLDLOCK on the key range: two simultaneous orders in the
          same branch serialise here and get 37 and 38, never 37 twice.
        -----------------------------------------------------------------*/
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @RunningOrder = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;

        IF @RunningOrder IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber)
            VALUES (@BranchID, @Today, 1);
            SET @RunningOrder = 1;
        END

        /*---- 3.4 Invoice header -----------------------------------------
          FinalAmount and Change are COMPUTED columns - never written here.
          >>> CONFIRM with POS_00b_ComputedCols.sql whether FinalAmount
              already includes DeliveryCharges. If it does NOT and the
              business wants it to, the computed column definition should be
              changed rather than folding the charge into BillAmount here --
              folding it in would corrupt every item-sales report.
        -----------------------------------------------------------------*/
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount
        )
        VALUES
        (
              @WaiterID, @BillAmount, @InvoiceDiscount, @Comments, 1, 0
            , @Now, @Now, @PaymentTypeID, 0
            , TRY_CAST(REPLACE(REPLACE(ISNULL(@Mobile,''),'+',''),' ','') AS BIGINT), @Mobile
            , @CustomerName, 1, @CustomerId, 1, 0            -- OrderStatusID 1 = Received
            , @BranchID, @AddressID, @BrandID, @DeliveryDate, @InvoiceTypeID
            , @DiscountTypeID, @DeliveryCharges, @OrderType, NULL
            , @ClientOrderGuid, @DiscountCode, @SourceID, @RunningOrder
            , DATEADD(MINUTE, ISNULL((SELECT DefaultPrepMinutes FROM dbo.tblPOS_BranchSetting WHERE BranchID = @BranchID), 20), @Now)
            , 0
        );

        SET @InvoiceNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        /*---- 3.5 Tracking code ------------------------------------------
          Format AAAA-9999, derived deterministically from the invoice number
          so it is unique by construction - no retry loop, no collision check.
        -----------------------------------------------------------------*/
        DECLARE @seed BIGINT = @InvoiceNo * 2654435761 % 456976;   -- Knuth multiplicative hash
        SET @TrackingCode =
              CHAR(65 + (@seed / 17576) % 26)
            + CHAR(65 + (@seed / 676)   % 26)
            + CHAR(65 + (@seed / 26)    % 26)
            + CHAR(65 +  @seed          % 26)
            + '-'
            + RIGHT('0000' + CAST(@InvoiceNo % 10000 AS VARCHAR(4)), 4);

        UPDATE dbo.tblInvoice SET TrackingCode = @TrackingCode WHERE InvoiceNo = @InvoiceNo;

        /*---- 3.6 Order lines - one set-based insert, no cursor ----------*/
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT
              @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
            , @WaiterID, 0, 0, 0, 0, 0
            , @Now, 0, 0, @DiscountTypeID, 0, @BranchID
            , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l
        ORDER BY l.Seq;

        /*---- 3.7 Status history -----------------------------------------*/
        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        VALUES (@InvoiceNo, 0, 1, NULL, N'System', N'Order placed from QR Menu');

        /*---- 3.8 Audit --------------------------------------------------*/
        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Create', N'QRMenu',
                CONCAT(N'Branch=', @BranchID, N'; Lines=', (SELECT COUNT(*) FROM @lines),
                       N'; Bill=', @BillAmount, N'; PriceMismatchLines=', @PriceMismatch));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        DECLARE @err NVARCHAR(500) = ERROR_MESSAGE();

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', NULL, 'CreateFailed', N'QRMenu', @err);

        SELECT Message = 'Fail', InvoiceNo = CAST(NULL AS BIGINT), TrackingCode = CAST(NULL AS VARCHAR(12)),
               RunningOrder = CAST(NULL AS INT), BillAmount = CAST(0 AS DECIMAL(18,3)),
               Discount = CAST(0 AS DECIMAL(18,3)), DeliveryCharges = CAST(0 AS DECIMAL(18,3)),
               NetAmount = CAST(0 AS DECIMAL(18,3)), CustomerId = CAST(NULL AS INT),
               AddressID = CAST(NULL AS INT), ErrorMessage = @err;
        RETURN;
    END CATCH

    /*======================================================================
      4. RESULT
    ======================================================================*/
    SELECT Message         = 'Success'
         , InvoiceNo       = @InvoiceNo
         , TrackingCode    = @TrackingCode
         , RunningOrder    = @RunningOrder
         , BillAmount      = @BillAmount
         , Discount        = @InvoiceDiscount
         , DeliveryCharges = @DeliveryCharges
         , NetAmount       = @BillAmount - @InvoiceDiscount + @DeliveryCharges
         , CustomerId      = @CustomerId
         , AddressID       = @AddressID
         , ErrorMessage    = CAST(NULL AS NVARCHAR(500));
END
GO

PRINT 'sp_POS_ProcessOrder created.';
GO


/**********************************************************************************
  SMOKE TEST - run after POS_01 and POS_02
**********************************************************************************/
/*
DECLARE @items dbo.TVP_POS_OrderItem;
INSERT INTO @items (ItemID, HID, ParentItemID, CartItemUniqID, LineType, Quantity, Price, Comments, Extra)
SELECT TOP 2 ID, HID, NULL, ROW_NUMBER() OVER (ORDER BY ID), 1, 2, PRICE, NULL, NULL
FROM dbo.tblItems WHERE PRICE > 0;

EXEC dbo.sp_POS_ProcessOrder
      @BranchID        = 1
    , @BrandID         = 1
    , @InvoiceTypeID   = 11
    , @OrderType       = 2
    , @CustomerName    = N'Test Customer'
    , @Mobile          = N'96560770626'
    , @AreaID          = 1
    , @Block           = N'4'
    , @Street          = N'Test Street'
    , @PaymentTypeID   = 4
    , @ClientOrderGuid = NEWID()
    , @dtOrderItems    = @items;

SELECT TOP 5 InvoiceNo, TrackingCode, RunningOrder, BillAmount, Discount, DeliveryCharges,
             FinalAmount, OrderStatusID, CustomerId, AddressID
FROM dbo.tblInvoice ORDER BY InvoiceNo DESC;

SELECT * FROM dbo.tblOrder ORDER BY OrderID DESC;

-- Idempotency check: run the EXEC twice with the SAME @ClientOrderGuid.
-- The second call must return Message = 'Duplicate' and create no new rows.
*/
