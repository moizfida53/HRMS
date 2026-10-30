/**********************************************************************************
  POS_01_Schema.sql
  ------------------------------------------------------------------------------
  Database : Pistachio_v4
  Purpose  : Prepare the schema for (a) direct order insert from the QR menu and
             (b) the POS Admin Panel.

  SAFE TO RUN: every existing table touched here is currently EMPTY
               (tblInvoice 0 rows, tblOrder 0 rows, tblCustomer 0 rows),
               so the type changes below cost nothing. They become expensive
               and risky once live orders exist -- run this BEFORE go-live.

  The script is idempotent: re-running it is a no-op.

  BACK UP THE DATABASE FIRST.
**********************************************************************************/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*==============================================================================
  SECTION 1 - FIX EXISTING TABLES
==============================================================================*/

/*------------------------------------------------------------------------------
  1.1  tblOrder.InvoiceNo : varchar(500) -> bigint

  tblInvoice.InvoiceNo is bigint IDENTITY. tblOrder.InvoiceNo is varchar(500).
  Every join between them currently forces an implicit conversion, which makes
  the index on the varchar side unusable -- SQL Server scans instead of seeks.
  On the POS orders grid that is the difference between a few milliseconds and
  a full table scan per page. Fix it now while the table is empty.
------------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.columns c
           JOIN sys.tables t ON t.object_id = c.object_id
           JOIN sys.types  y ON y.user_type_id = c.user_type_id
           WHERE t.name = 'tblOrder' AND c.name = 'InvoiceNo' AND y.name = 'varchar')
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblOrder)
        THROW 50001, 'tblOrder is not empty - convert InvoiceNo manually, do not run blind.', 1;

    ALTER TABLE dbo.tblOrder ALTER COLUMN InvoiceNo BIGINT NULL;
    PRINT '1.1  tblOrder.InvoiceNo converted to BIGINT';
END
ELSE PRINT '1.1  tblOrder.InvoiceNo already BIGINT - skipped';
GO

/*------------------------------------------------------------------------------
  1.2  tblCustomer.id : make it an IDENTITY

  Currently int NOT NULL with no identity and no default, so every insert would
  have to invent a key under a lock. Table is empty, so rebuild it properly.
  Also adds the columns the POS needs (created date, soft delete, brand).
------------------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM sys.columns c
               JOIN sys.tables t ON t.object_id = c.object_id
               WHERE t.name = 'tblCustomer' AND c.name = 'id' AND c.is_identity = 1)
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblCustomer)
        THROW 50002, 'tblCustomer is not empty - migrate manually.', 1;

    DROP TABLE dbo.tblCustomer;

    CREATE TABLE dbo.tblCustomer
    (
          id            INT IDENTITY(1,1) NOT NULL
        , firstName     NVARCHAR(50)   NULL
        , lastName      NVARCHAR(50)   NULL
        , mobile        NVARCHAR(20)   NULL
        , email         NVARCHAR(100)  NULL
        , areaId        INT            NULL
        , block         NVARCHAR(50)   NULL
        , street        NVARCHAR(500)  NULL
        , building      NVARCHAR(50)   NULL
        , flat          NVARCHAR(50)   NULL
        , landmark      NVARCHAR(50)   NULL
        -- POS additions
        , BrandID       INT            NULL
        , CivilID       NVARCHAR(50)   NULL
        , Mobile2       NVARCHAR(20)   NULL
        , Notes         NVARCHAR(1000) NULL
        , IsBlocked     BIT            NOT NULL CONSTRAINT DF_tblCustomer_IsBlocked DEFAULT (0)
        , IsDeleted     BIT            NOT NULL CONSTRAINT DF_tblCustomer_IsDeleted DEFAULT (0)
        , CreatedOn     DATETIME       NOT NULL CONSTRAINT DF_tblCustomer_CreatedOn DEFAULT (GETDATE())
        , ModifiedOn    DATETIME       NULL
        , CONSTRAINT PK_tblCustomer PRIMARY KEY CLUSTERED (id)
    );
    PRINT '1.2  tblCustomer rebuilt with IDENTITY + POS columns';
END
ELSE PRINT '1.2  tblCustomer.id already IDENTITY - skipped';
GO

-- Mobile is the natural key customers are looked up by. Filtered unique index
-- prevents the duplicate-customer mess that phone-keyed systems always develop.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tblCustomer_Mobile')
    CREATE UNIQUE NONCLUSTERED INDEX UX_tblCustomer_Mobile
        ON dbo.tblCustomer (mobile)
        WHERE mobile IS NOT NULL AND IsDeleted = 0;
GO

/*------------------------------------------------------------------------------
  1.3  tblInvoice - add the columns the POS needs

  NOTE ON Mobile: the existing column is BIGINT. '+96560770626' loses its '+'
  and any leading zero when stored as a number, and cannot hold a formatted
  or international number. A text column is added alongside; the bigint one is
  kept populated so any existing report keeps working.
------------------------------------------------------------------------------*/
IF COL_LENGTH('dbo.tblInvoice','MobileText')      IS NULL ALTER TABLE dbo.tblInvoice ADD MobileText      NVARCHAR(30)  NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','CustomerName')    IS NULL ALTER TABLE dbo.tblInvoice ADD CustomerName    NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','OrderType')       IS NULL ALTER TABLE dbo.tblInvoice ADD OrderType       INT           NOT NULL CONSTRAINT DF_tblInvoice_OrderType DEFAULT (2);  -- 1=Pickup 2=Delivery 3=DineIn
GO
IF COL_LENGTH('dbo.tblInvoice','TrackingCode')    IS NULL ALTER TABLE dbo.tblInvoice ADD TrackingCode    VARCHAR(12)   NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','ClientOrderGuid') IS NULL ALTER TABLE dbo.tblInvoice ADD ClientOrderGuid UNIQUEIDENTIFIER NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','DiscountCode')    IS NULL ALTER TABLE dbo.tblInvoice ADD DiscountCode    NVARCHAR(50)  NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','SourceID')        IS NULL ALTER TABLE dbo.tblInvoice ADD SourceID        INT           NOT NULL CONSTRAINT DF_tblInvoice_SourceID DEFAULT (1);   -- 1=QR Menu 2=Call Centre 3=Counter 4=Aggregator
GO
IF COL_LENGTH('dbo.tblInvoice','PromisedTime')    IS NULL ALTER TABLE dbo.tblInvoice ADD PromisedTime    DATETIME      NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','CancelReasonID')  IS NULL ALTER TABLE dbo.tblInvoice ADD CancelReasonID  INT           NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','CancelComments')  IS NULL ALTER TABLE dbo.tblInvoice ADD CancelComments  NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','CancelDisposition') IS NULL ALTER TABLE dbo.tblInvoice ADD CancelDisposition TINYINT   NULL;  -- 1=Waste 2=Reuse
GO
IF COL_LENGTH('dbo.tblInvoice','PrintCount')      IS NULL ALTER TABLE dbo.tblInvoice ADD PrintCount      INT           NOT NULL CONSTRAINT DF_tblInvoice_PrintCount DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblInvoice','LastPrintedOn')   IS NULL ALTER TABLE dbo.tblInvoice ADD LastPrintedOn   DATETIME      NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','ModifiedOn')      IS NULL ALTER TABLE dbo.tblInvoice ADD ModifiedOn      DATETIME      NULL;
GO
IF COL_LENGTH('dbo.tblInvoice','ModifiedBy')      IS NULL ALTER TABLE dbo.tblInvoice ADD ModifiedBy      INT           NULL;
GO
-- rowversion powers delta polling in the POS grid (fetch only what changed)
IF COL_LENGTH('dbo.tblInvoice','RowVer')          IS NULL ALTER TABLE dbo.tblInvoice ADD RowVer          ROWVERSION;
GO

-- Idempotency: a double-tap on "Process Order", or a retried request, must not
-- create a second invoice. Filtered unique index enforces it at the DB level.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tblInvoice_ClientOrderGuid')
    CREATE UNIQUE NONCLUSTERED INDEX UX_tblInvoice_ClientOrderGuid
        ON dbo.tblInvoice (ClientOrderGuid) WHERE ClientOrderGuid IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tblInvoice_TrackingCode')
    CREATE UNIQUE NONCLUSTERED INDEX UX_tblInvoice_TrackingCode
        ON dbo.tblInvoice (TrackingCode) WHERE TrackingCode IS NOT NULL;
GO

/*------------------------------------------------------------------------------
  1.4  Indexes that make the POS grid fast

  The covering index is the single most important object in this script. Without
  it the default grid query (today + branch + open statuses) degrades into a
  clustered index scan as soon as the table grows.
------------------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoice_POSGrid')
    CREATE NONCLUSTERED INDEX IX_tblInvoice_POSGrid
        ON dbo.tblInvoice (BranchID, InvoiceDate, OrderStatusID)
        INCLUDE (InvoiceNo, TrackingCode, CustomerName, MobileText, BillAmount,
                 Discount, DeliveryCharges, PaymentType, OrderType, CustomerId,
                 AddressID, BrandID, Deleted)
        WHERE Deleted = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoice_Mobile')
    CREATE NONCLUSTERED INDEX IX_tblInvoice_Mobile ON dbo.tblInvoice (MobileText) INCLUDE (InvoiceDate, BillAmount);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoice_Customer')
    CREATE NONCLUSTERED INDEX IX_tblInvoice_Customer ON dbo.tblInvoice (CustomerId, InvoiceDate DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblOrder_InvoiceNo')
    CREATE NONCLUSTERED INDEX IX_tblOrder_InvoiceNo
        ON dbo.tblOrder (InvoiceNo) INCLUDE (ItemID, Quantity, Price, Comments, Extra, Deleted);
GO

/*------------------------------------------------------------------------------
  1.5  tblOrder - POS additions
------------------------------------------------------------------------------*/
IF COL_LENGTH('dbo.tblOrder','ParentOrderID')   IS NULL ALTER TABLE dbo.tblOrder ADD ParentOrderID   BIGINT NULL;   -- links choice/extra lines to their parent item line
GO
IF COL_LENGTH('dbo.tblOrder','CartItemUniqID')  IS NULL ALTER TABLE dbo.tblOrder ADD CartItemUniqID  INT    NULL;
GO
IF COL_LENGTH('dbo.tblOrder','LineType')        IS NULL ALTER TABLE dbo.tblOrder ADD LineType        TINYINT NOT NULL CONSTRAINT DF_tblOrder_LineType DEFAULT (1); -- 1=Item 2=Choice 3=Extra
GO
IF COL_LENGTH('dbo.tblOrder','ItemNameSnapshot')IS NULL ALTER TABLE dbo.tblOrder ADD ItemNameSnapshot NVARCHAR(200) NULL;  -- price/name at time of sale, so reprints never change
GO


/*==============================================================================
  SECTION 2 - MASTER / LOOKUP TABLES

  None of these existed. tblInvoice.OrderStatusID, .PaymentType and .InvoiceType
  are currently bare integers with no lookup table, which is why the call-centre
  payload had to hard-code "InvoiceTypeID = 10" in Web.config.
==============================================================================*/

/*---- 2.1 Order status ------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_OrderStatus_Master') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_OrderStatus_Master
    (
          StatusID          INT           NOT NULL
        , StatusName        NVARCHAR(50)  NOT NULL
        , StatusNameAra     NVARCHAR(50)  NULL
        , SortOrder         INT           NOT NULL
        , ColorHex          VARCHAR(7)    NULL
        , IsTerminal        BIT           NOT NULL DEFAULT (0)   -- no further transitions
        , AppliesToPickup   BIT           NOT NULL DEFAULT (1)
        , AppliesToDelivery BIT           NOT NULL DEFAULT (1)
        , IsActive          BIT           NOT NULL DEFAULT (1)
        , CONSTRAINT PK_tblPOS_OrderStatus_Master PRIMARY KEY CLUSTERED (StatusID)
    );

    INSERT INTO dbo.tblPOS_OrderStatus_Master
        (StatusID, StatusName, StatusNameAra, SortOrder, ColorHex, IsTerminal, AppliesToPickup, AppliesToDelivery)
    VALUES
          (0, N'New',              N'جديد',        0, '#6c757d', 0, 1, 1)
        , (1, N'Received',         N'مستلم',       1, '#0d6efd', 0, 1, 1)
        , (2, N'Preparing',        N'قيد التحضير', 2, '#fd7e14', 0, 1, 1)
        , (3, N'Delivering/Ready', N'جاهز',        3, '#0dcaf0', 0, 1, 1)
        , (4, N'With Driver',      N'مع السائق',   4, '#6f42c1', 0, 0, 1)
        , (5, N'On the Way',       N'في الطريق',   5, '#20c997', 0, 0, 1)
        , (6, N'Delivered',        N'تم التسليم',  6, '#198754', 1, 1, 1)
        , (7, N'Cancelled',        N'ملغي',        7, '#dc3545', 1, 1, 1)
        , (8, N'Refunded',         N'مسترجع',      8, '#b02a37', 1, 1, 1);
    PRINT '2.1  tblPOS_OrderStatus_Master created and seeded';
END
GO

/*---- 2.2 Allowed status transitions ---------------------------------------
  Enforced in the proc, not just in the UI. Without this a stale browser tab
  can drag a delivered order back into Preparing.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_OrderStatusTransition') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_OrderStatusTransition
    (
          FromStatusID   INT NOT NULL
        , ToStatusID     INT NOT NULL
        , RequiresRole   INT NULL          -- NULL = any POS user
        , CONSTRAINT PK_tblPOS_OrderStatusTransition PRIMARY KEY CLUSTERED (FromStatusID, ToStatusID)
    );

    INSERT INTO dbo.tblPOS_OrderStatusTransition (FromStatusID, ToStatusID, RequiresRole) VALUES
          (0,1,NULL),(0,7,NULL)
        , (1,2,NULL),(1,7,NULL)
        , (2,3,NULL),(2,7,NULL)
        , (3,4,NULL),(3,6,NULL),(3,7,NULL)     -- pickup goes Ready -> Delivered
        , (4,5,NULL),(4,3,NULL)
        , (5,6,NULL),(5,4,NULL)
        , (6,8,2)                              -- refund from delivered: supervisor only
        , (7,8,2);
    PRINT '2.2  tblPOS_OrderStatusTransition created and seeded';
END
GO

/*---- 2.3 Payment types -----------------------------------------------------
  Seeded to match the amount columns that already exist on tblInvoice
  (CashAmount, K_NETAmount, VisaAmount, MasterAmount, ...). PaymentType
  defaults to 4 on tblInvoice, so 4 = Cash on Delivery is kept.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_PaymentType_Master') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_PaymentType_Master
    (
          PaymentTypeID     INT           NOT NULL
        , PaymentTypeName   NVARCHAR(50)  NOT NULL
        , PaymentTypeNameAra NVARCHAR(50) NULL
        , IsCash            BIT           NOT NULL DEFAULT (0)
        , IsOnline          BIT           NOT NULL DEFAULT (0)
        , RequiresReference BIT           NOT NULL DEFAULT (0)
        , LegacyColumn      SYSNAME       NULL      -- tblInvoice column kept in sync
        , SortOrder         INT           NOT NULL DEFAULT (0)
        , IsActive          BIT           NOT NULL DEFAULT (1)
        , CONSTRAINT PK_tblPOS_PaymentType_Master PRIMARY KEY CLUSTERED (PaymentTypeID)
    );

    INSERT INTO dbo.tblPOS_PaymentType_Master
        (PaymentTypeID, PaymentTypeName, PaymentTypeNameAra, IsCash, IsOnline, RequiresReference, LegacyColumn, SortOrder)
    VALUES
          (1, N'Cash',             N'نقدي',           1,0,0, 'CashAmount',      1)
        , (2, N'KNET',             N'كي نت',          0,1,1, 'K_NETAmount',     2)
        , (3, N'Visa',             N'فيزا',           0,1,1, 'VisaAmount',      3)
        , (4, N'Cash on Delivery', N'الدفع عند الاستلام',1,0,0,'CashAmount',    0)
        , (5, N'MasterCard',       N'ماستر كارد',     0,1,1, 'MasterAmount',    4)
        , (6, N'Payment Link',     N'رابط دفع',       0,1,1, NULL,              5)
        , (7, N'Wallet / Credit',  N'محفظة',          0,0,0, NULL,              6)
        , (8, N'Split',            N'دفع مقسم',       0,0,0, NULL,              7);
    PRINT '2.3  tblPOS_PaymentType_Master created and seeded';
END
GO

/*---- 2.4 Invoice types -----------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_InvoiceType_Master') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_InvoiceType_Master
    (
          InvoiceTypeID   INT          NOT NULL
        , InvoiceTypeName NVARCHAR(50) NOT NULL
        , IsActive        BIT          NOT NULL DEFAULT (1)
        , CONSTRAINT PK_tblPOS_InvoiceType_Master PRIMARY KEY CLUSTERED (InvoiceTypeID)
    );
    -- 10 preserved: it is the value already configured in Web.config InvoiceTypeID
    INSERT INTO dbo.tblPOS_InvoiceType_Master (InvoiceTypeID, InvoiceTypeName) VALUES
          (1,  N'Dine In'), (2, N'Take Away'), (3, N'Delivery'),
          (10, N'Call Centre'), (11, N'QR Menu Online');
    PRINT '2.4  tblPOS_InvoiceType_Master created and seeded';
END
GO

/*---- 2.5 Cancellation reasons ---------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_CancelReason_Master') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_CancelReason_Master
    (
          CancelReasonID   INT IDENTITY(1,1) NOT NULL
        , ReasonName       NVARCHAR(100) NOT NULL
        , ReasonNameAra    NVARCHAR(100) NULL
        , DefaultDisposition TINYINT     NULL      -- 1=Waste 2=Reuse
        , IsActive         BIT           NOT NULL DEFAULT (1)
        , CONSTRAINT PK_tblPOS_CancelReason_Master PRIMARY KEY CLUSTERED (CancelReasonID)
    );
    INSERT INTO dbo.tblPOS_CancelReason_Master (ReasonName, ReasonNameAra, DefaultDisposition) VALUES
          (N'Customer changed mind',    N'العميل غير رأيه',      2)
        , (N'Customer not reachable',   N'لا يمكن الوصول للعميل', 1)
        , (N'Item out of stock',        N'الصنف غير متوفر',      2)
        , (N'Wrong order entered',      N'طلب خاطئ',            2)
        , (N'Kitchen error',            N'خطأ في المطبخ',        1)
        , (N'Delivery too late',        N'تأخر التوصيل',         1)
        , (N'Duplicate order',          N'طلب مكرر',            2)
        , (N'Payment failed',           N'فشل الدفع',           2);
    PRINT '2.5  tblPOS_CancelReason_Master created and seeded';
END
GO


/*==============================================================================
  SECTION 3 - NEW TRANSACTIONAL TABLES
==============================================================================*/

/*---- 3.1 Customer addresses -----------------------------------------------
  tblInvoice.AddressID exists but NO address table does. The Address model in
  Models/ItemsView.cs is the shape mirrored here.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblCustomerAddress') IS NULL
BEGIN
    CREATE TABLE dbo.tblCustomerAddress
    (
          AddressID      INT IDENTITY(1,1) NOT NULL
        , CustomerID     INT            NULL
        , AreaID         INT            NULL
        , Block          NVARCHAR(50)   NULL
        , Street         NVARCHAR(500)  NULL
        , Lane           NVARCHAR(100)  NULL
        , Building       NVARCHAR(50)   NULL
        , Floor          NVARCHAR(50)   NULL
        , Flat           NVARCHAR(50)   NULL
        , HouseNo        NVARCHAR(50)   NULL
        , PACI           NVARCHAR(50)   NULL
        , AddressRemark  NVARCHAR(500)  NULL
        , Lat            NVARCHAR(50)   NULL
        , Lng            NVARCHAR(50)   NULL
        , Email          NVARCHAR(100)  NULL
        , IsDefault      BIT            NOT NULL DEFAULT (0)
        , IsDeleted      BIT            NOT NULL DEFAULT (0)
        , CreatedOn      DATETIME       NOT NULL DEFAULT (GETDATE())
        , CONSTRAINT PK_tblCustomerAddress PRIMARY KEY CLUSTERED (AddressID)
    );
    CREATE NONCLUSTERED INDEX IX_tblCustomerAddress_Customer
        ON dbo.tblCustomerAddress (CustomerID) WHERE IsDeleted = 0;
    PRINT '3.1  tblCustomerAddress created';
END
GO

/*---- 3.2 Order status history ---------------------------------------------
  Append-only. tblInvoice.OrderStatusID stays as the denormalised "current"
  value so the grid never has to aggregate this table.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_OrderStatusHistory') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_OrderStatusHistory
    (
          HistoryID     BIGINT IDENTITY(1,1) NOT NULL
        , InvoiceNo     BIGINT        NOT NULL
        , FromStatusID  INT           NULL
        , ToStatusID    INT           NOT NULL
        , ChangedBy     INT           NULL       -- tblUser.ID
        , ChangedByName NVARCHAR(100) NULL
        , ChangedOn     DATETIME      NOT NULL DEFAULT (GETDATE())
        , Comments      NVARCHAR(1000) NULL
        , DriverID      INT           NULL
        , CONSTRAINT PK_tblPOS_OrderStatusHistory PRIMARY KEY CLUSTERED (HistoryID)
    );
    CREATE NONCLUSTERED INDEX IX_tblPOS_OrderStatusHistory_Invoice
        ON dbo.tblPOS_OrderStatusHistory (InvoiceNo, ChangedOn);
    PRINT '3.2  tblPOS_OrderStatusHistory created';
END
GO

/*---- 3.3 Invoice payments --------------------------------------------------
  A child table, not a column, because split and partial payments are real:
  half cash + half KNET is common, and refunds are negative rows here.
  The legacy per-method columns on tblInvoice are kept in sync by the procs.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_InvoicePayment') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_InvoicePayment
    (
          PaymentID      BIGINT IDENTITY(1,1) NOT NULL
        , InvoiceNo      BIGINT         NOT NULL
        , PaymentTypeID  INT            NOT NULL
        , Amount         DECIMAL(18,3)  NOT NULL
        , AmountTendered DECIMAL(18,3)  NULL
        , ChangeGiven    DECIMAL(18,3)  NULL
        , ReferenceNo    NVARCHAR(100)  NULL
        , IsRefund       BIT            NOT NULL DEFAULT (0)
        , ReceivedBy     INT            NULL
        , ReceivedOn     DATETIME       NOT NULL DEFAULT (GETDATE())
        , Comments       NVARCHAR(500)  NULL
        , CONSTRAINT PK_tblPOS_InvoicePayment PRIMARY KEY CLUSTERED (PaymentID)
    );
    CREATE NONCLUSTERED INDEX IX_tblPOS_InvoicePayment_Invoice
        ON dbo.tblPOS_InvoicePayment (InvoiceNo) INCLUDE (PaymentTypeID, Amount, IsRefund);
    PRINT '3.3  tblPOS_InvoicePayment created';
END
GO

/*---- 3.4 Branch transfer audit --------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_OrderTransfer') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_OrderTransfer
    (
          TransferID     BIGINT IDENTITY(1,1) NOT NULL
        , InvoiceNo      BIGINT        NOT NULL
        , FromBranchID   INT           NOT NULL
        , ToBranchID     INT           NOT NULL
        , Reason         NVARCHAR(500) NULL
        , TransferredBy  INT           NULL
        , TransferredOn  DATETIME      NOT NULL DEFAULT (GETDATE())
        , CONSTRAINT PK_tblPOS_OrderTransfer PRIMARY KEY CLUSTERED (TransferID)
    );
    CREATE NONCLUSTERED INDEX IX_tblPOS_OrderTransfer_Invoice ON dbo.tblPOS_OrderTransfer (InvoiceNo);
    PRINT '3.4  tblPOS_OrderTransfer created';
END
GO

/*---- 3.5 POS audit log -----------------------------------------------------
  Who cancelled, who refunded, who reprinted. Needed the first time there is a
  dispute; impossible to reconstruct after the fact.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_AuditLog') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_AuditLog
    (
          AuditID     BIGINT IDENTITY(1,1) NOT NULL
        , EntityType  VARCHAR(50)    NOT NULL     -- 'Invoice','Customer',...
        , EntityID    BIGINT         NULL
        , Action      VARCHAR(50)    NOT NULL     -- 'Cancel','Refund','Print','Transfer','StatusChange'
        , UserID      INT            NULL
        , UserName    NVARCHAR(100)  NULL
        , Details     NVARCHAR(MAX)  NULL
        , IPAddress   VARCHAR(45)    NULL
        , CreatedOn   DATETIME       NOT NULL DEFAULT (GETDATE())
        , CONSTRAINT PK_tblPOS_AuditLog PRIMARY KEY CLUSTERED (AuditID)
    );
    CREATE NONCLUSTERED INDEX IX_tblPOS_AuditLog_Entity ON dbo.tblPOS_AuditLog (EntityType, EntityID, CreatedOn);
    PRINT '3.5  tblPOS_AuditLog created';
END
GO

/*---- 3.6 Daily per-branch running number ----------------------------------
  tblInvoice.InvoiceNo is a global bigint IDENTITY, which is correct as a key
  but reads badly on a receipt ("Order #418734"). Branches expect "Order #37"
  resetting daily. This table issues it without a MAX()+1 race.
---------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_DailyCounter') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_DailyCounter
    (
          BranchID    INT   NOT NULL
        , CounterDate DATE  NOT NULL
        , LastNumber  INT   NOT NULL
        , CONSTRAINT PK_tblPOS_DailyCounter PRIMARY KEY CLUSTERED (BranchID, CounterDate)
    );
    PRINT '3.6  tblPOS_DailyCounter created';
END
GO

/*---- 3.7 Branch settings ---------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_BranchSetting') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_BranchSetting
    (
          BranchID           INT NOT NULL
        , ThermalWidthMM     INT NOT NULL DEFAULT (80)     -- 80 or 58
        , AutoPrintOnNew     BIT NOT NULL DEFAULT (1)
        , DefaultPrepMinutes INT NOT NULL DEFAULT (20)
        , MaxOpenOrders      INT NULL                      -- capacity throttle; NULL = unlimited
        , SoundOnNewOrder    BIT NOT NULL DEFAULT (1)
        , CONSTRAINT PK_tblPOS_BranchSetting PRIMARY KEY CLUSTERED (BranchID)
    );
    INSERT INTO dbo.tblPOS_BranchSetting (BranchID) SELECT id FROM dbo.tblbranch;
    PRINT '3.7  tblPOS_BranchSetting created and seeded from tblbranch';
END
GO


/*==============================================================================
  SECTION 4 - TABLE TYPE for the order lines TVP
==============================================================================*/
IF TYPE_ID('dbo.TVP_POS_OrderItem') IS NULL
BEGIN
    CREATE TYPE dbo.TVP_POS_OrderItem AS TABLE
    (
          ItemID          INT            NULL
        , HID             INT            NULL
        , ParentItemID    INT            NULL
        , CartItemUniqID  INT            NULL
        , LineType        TINYINT        NOT NULL DEFAULT (1)
        , Quantity        INT            NOT NULL
        , Price           DECIMAL(18,3)  NULL      -- client-supplied; NOT trusted, see proc
        , Comments        NVARCHAR(MAX)  NULL
        , Extra           NVARCHAR(MAX)  NULL
    );
    PRINT '4.0  TVP_POS_OrderItem created';
END
GO

PRINT '';
PRINT '################ POS_01_Schema.sql COMPLETE ################';
GO
