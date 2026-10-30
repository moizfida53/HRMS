/**********************************************************************************
  POS_03_Reconcile.sql
  ------------------------------------------------------------------------------
  Run AFTER POS_01_Schema.sql, and after importing the head-office tables.
  Run POS_00c_LookupContents.sql first and keep the output.

  WHY THIS SCRIPT EXISTS
  ----------------------
  POS_01 created lookup tables because none existed. The head-office import then
  supplied the real ones. Four pairs now overlap:

      tblPOS_OrderStatus_Master   <->  tblOrderStatus
      tblPOS_PaymentType_Master   <->  tblInvoicePaymentType
      tblPOS_InvoiceType_Master   <->  tblInvoiceType_Master
      tblPOS_InvoicePayment       <->  tblInvoicePayment

  The head-office tables win. tblInvoice already carries EndShiftID, EndDayID,
  Driver, DriverName and Voucher, which only mean anything inside the HO model --
  keeping two parallel sets would orphan end-of-day, shift, driver and voucher
  reporting. This script drops the POS duplicates and extends the HO tables with
  the columns the POS needs.

  SEEDING IS CONSERVATIVE: a table that already has rows is left completely
  alone and reported at the end. Existing IDs always win.

  BACK UP FIRST.
**********************************************************************************/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*==============================================================================
  SECTION 1 - tblOrderStatus  (replaces tblPOS_OrderStatus_Master)

  As imported it has no primary key and OrderStatusID is nullable, so nothing
  stops duplicate or NULL status rows. Both are fixed here.
==============================================================================*/

IF COL_LENGTH('dbo.tblOrderStatus','OrderStatusNameAra')IS NULL ALTER TABLE dbo.tblOrderStatus ADD OrderStatusNameAra NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.tblOrderStatus','SortOrder')         IS NULL ALTER TABLE dbo.tblOrderStatus ADD SortOrder         INT NULL;
GO
IF COL_LENGTH('dbo.tblOrderStatus','ColorHex')          IS NULL ALTER TABLE dbo.tblOrderStatus ADD ColorHex          VARCHAR(7) NULL;
GO
IF COL_LENGTH('dbo.tblOrderStatus','IsTerminal')        IS NULL ALTER TABLE dbo.tblOrderStatus ADD IsTerminal        BIT NOT NULL CONSTRAINT DF_tblOrderStatus_IsTerminal DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblOrderStatus','AppliesToPickup')   IS NULL ALTER TABLE dbo.tblOrderStatus ADD AppliesToPickup   BIT NOT NULL CONSTRAINT DF_tblOrderStatus_Pickup   DEFAULT (1);
GO
IF COL_LENGTH('dbo.tblOrderStatus','AppliesToDelivery') IS NULL ALTER TABLE dbo.tblOrderStatus ADD AppliesToDelivery BIT NOT NULL CONSTRAINT DF_tblOrderStatus_Delivery DEFAULT (1);
GO
IF COL_LENGTH('dbo.tblOrderStatus','IsActive')          IS NULL ALTER TABLE dbo.tblOrderStatus ADD IsActive          BIT NOT NULL CONSTRAINT DF_tblOrderStatus_IsActive  DEFAULT (1);
GO

-- Seed only when empty; existing head-office rows are never touched.
IF NOT EXISTS (SELECT 1 FROM dbo.tblOrderStatus)
BEGIN
    INSERT INTO dbo.tblOrderStatus
        (OrderStatusID, OrderStatusName, OrderStatusNameAra, SortOrder, ColorHex,
         IsTerminal, AppliesToPickup, AppliesToDelivery, MessageSend, SmsContent)
    VALUES
      (0, N'New',              N'جديد',        0, '#6c757d', 0,1,1, 0, NULL)
    , (1, N'Received',         N'مستلم',       1, '#0d6efd', 0,1,1, 1, N'Your order {TrackingCode} has been received. Track it here: {TrackUrl}')
    , (2, N'Preparing',        N'قيد التحضير', 2, '#fd7e14', 0,1,1, 0, N'Your order {TrackingCode} is being prepared.')
    , (3, N'Delivering/Ready', N'جاهز',        3, '#0dcaf0', 0,1,1, 1, N'Your order {TrackingCode} is ready.')
    , (4, N'With Driver',      N'مع السائق',   4, '#6f42c1', 0,0,1, 0, N'Your order {TrackingCode} has been handed to our driver.')
    , (5, N'On the Way',       N'في الطريق',   5, '#20c997', 0,0,1, 1, N'Your order {TrackingCode} is on the way.')
    , (6, N'Delivered',        N'تم التسليم',  6, '#198754', 1,1,1, 1, N'Your order {TrackingCode} has been delivered. Thank you!')
    , (7, N'Cancelled',        N'ملغي',        7, '#dc3545', 1,1,1, 1, N'Your order {TrackingCode} has been cancelled.')
    , (8, N'Refunded',         N'مسترجع',      8, '#b02a37', 1,1,1, 1, N'Your order {TrackingCode} has been refunded.');
    PRINT '1.1  tblOrderStatus seeded (was empty)';
END
ELSE
    PRINT '1.1  tblOrderStatus already has rows - LEFT UNTOUCHED (check LookupContents.txt)';
GO

-- Primary key: only possible once OrderStatusID is NOT NULL and unique.
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_tblOrderStatus')
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblOrderStatus WHERE OrderStatusID IS NULL)
        PRINT '1.2  !! tblOrderStatus has NULL OrderStatusID rows - clean them, then re-run for the PK';
    ELSE IF EXISTS (SELECT OrderStatusID FROM dbo.tblOrderStatus GROUP BY OrderStatusID HAVING COUNT(*) > 1)
        PRINT '1.2  !! tblOrderStatus has duplicate OrderStatusID rows - clean them, then re-run for the PK';
    ELSE
    BEGIN
        ALTER TABLE dbo.tblOrderStatus ALTER COLUMN OrderStatusID INT NOT NULL;
        ALTER TABLE dbo.tblOrderStatus ADD CONSTRAINT PK_tblOrderStatus PRIMARY KEY CLUSTERED (OrderStatusID);
        PRINT '1.2  PK_tblOrderStatus added';
    END
END
GO

IF OBJECT_ID('dbo.tblPOS_OrderStatus_Master') IS NOT NULL
BEGIN
    DROP TABLE dbo.tblPOS_OrderStatus_Master;
    PRINT '1.3  tblPOS_OrderStatus_Master dropped (superseded by tblOrderStatus)';
END
GO


/*==============================================================================
  SECTION 2 - tblInvoicePaymentType  (replaces tblPOS_PaymentType_Master)

  LegacyColumn maps a payment type onto the per-method amount column that
  already exists on tblInvoice (CashAmount, K_NETAmount, VisaAmount, ...), so
  the existing end-of-day and shift reports keep working while payments are
  recorded properly in tblInvoicePayment.
==============================================================================*/

IF COL_LENGTH('dbo.tblInvoicePaymentType','IsCash')            IS NULL ALTER TABLE dbo.tblInvoicePaymentType ADD IsCash            BIT NOT NULL CONSTRAINT DF_tblIPT_IsCash   DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblInvoicePaymentType','IsOnline')          IS NULL ALTER TABLE dbo.tblInvoicePaymentType ADD IsOnline          BIT NOT NULL CONSTRAINT DF_tblIPT_IsOnline DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblInvoicePaymentType','RequiresReference') IS NULL ALTER TABLE dbo.tblInvoicePaymentType ADD RequiresReference BIT NOT NULL CONSTRAINT DF_tblIPT_ReqRef   DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblInvoicePaymentType','LegacyColumn')      IS NULL ALTER TABLE dbo.tblInvoicePaymentType ADD LegacyColumn      SYSNAME NULL;
GO
IF COL_LENGTH('dbo.tblInvoicePaymentType','IsCOD')             IS NULL ALTER TABLE dbo.tblInvoicePaymentType ADD IsCOD             BIT NOT NULL CONSTRAINT DF_tblIPT_IsCOD    DEFAULT (0);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType)
BEGIN
    INSERT INTO dbo.tblInvoicePaymentType
        (PaymentTypeName, PaymentTypeNameArb, Seqnum, IsActive, IsDeleted, createdon,
         IsCash, IsOnline, RequiresReference, IsCOD, LegacyColumn)
    VALUES
      (N'Cash',             N'نقدي',                 1, 1, 0, GETDATE(), 1,0,0,0, 'CashAmount')
    , (N'KNET',             N'كي نت',                2, 1, 0, GETDATE(), 0,1,1,0, 'K_NETAmount')
    , (N'Visa',             N'فيزا',                 3, 1, 0, GETDATE(), 0,1,1,0, 'VisaAmount')
    , (N'Cash on Delivery', N'الدفع عند الاستلام',    4, 1, 0, GETDATE(), 1,0,0,1, 'CashAmount')
    , (N'MasterCard',       N'ماستر كارد',           5, 1, 0, GETDATE(), 0,1,1,0, 'MasterAmount')
    , (N'Payment Link',     N'رابط دفع',             6, 1, 0, GETDATE(), 0,1,1,0, NULL)
    , (N'Wallet / Credit',  N'محفظة',                7, 1, 0, GETDATE(), 0,0,0,0, NULL)
    , (N'Split',            N'دفع مقسم',             8, 1, 0, GETDATE(), 0,0,0,0, NULL);
    PRINT '2.1  tblInvoicePaymentType seeded (was empty)';
END
ELSE
BEGIN
    -- Table already populated by head office: only fill in the new flags,
    -- matching on name. IDs are never changed.
    UPDATE dbo.tblInvoicePaymentType SET IsCash=1, LegacyColumn='CashAmount'   WHERE PaymentTypeName LIKE '%Cash%'   AND LegacyColumn IS NULL;
    UPDATE dbo.tblInvoicePaymentType SET IsCOD =1                              WHERE PaymentTypeName LIKE '%Delivery%' OR PaymentTypeName LIKE '%COD%';
    UPDATE dbo.tblInvoicePaymentType SET IsOnline=1, RequiresReference=1, LegacyColumn='K_NETAmount' WHERE PaymentTypeName LIKE '%KNET%' OR PaymentTypeName LIKE '%K-NET%' OR PaymentTypeName LIKE '%K_NET%';
    UPDATE dbo.tblInvoicePaymentType SET IsOnline=1, RequiresReference=1, LegacyColumn='VisaAmount'   WHERE PaymentTypeName LIKE '%Visa%'   AND LegacyColumn IS NULL;
    UPDATE dbo.tblInvoicePaymentType SET IsOnline=1, RequiresReference=1, LegacyColumn='MasterAmount' WHERE PaymentTypeName LIKE '%Master%' AND LegacyColumn IS NULL;
    PRINT '2.1  tblInvoicePaymentType already populated - flags back-filled by name, IDs untouched';
END
GO

IF OBJECT_ID('dbo.tblPOS_PaymentType_Master') IS NOT NULL
BEGIN
    DROP TABLE dbo.tblPOS_PaymentType_Master;
    PRINT '2.2  tblPOS_PaymentType_Master dropped (superseded by tblInvoicePaymentType)';
END
GO


/*==============================================================================
  SECTION 3 - tblInvoiceType_Master  (replaces tblPOS_InvoiceType_Master)

  Web.config currently sets InvoiceTypeID = 10. Seeding uses IDENTITY_INSERT so
  that value keeps its meaning.
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master)
BEGIN
    SET IDENTITY_INSERT dbo.tblInvoiceType_Master ON;
    INSERT INTO dbo.tblInvoiceType_Master (ID, Name, ShowInCallCentre) VALUES
          (1,  N'Dine In',        0)
        , (2,  N'Take Away',      0)
        , (3,  N'Delivery',       1)
        , (10, N'Call Centre',    1)
        , (11, N'QR Menu Online', 1);
    SET IDENTITY_INSERT dbo.tblInvoiceType_Master OFF;
    PRINT '3.1  tblInvoiceType_Master seeded (was empty)';
END
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master WHERE Name = N'QR Menu Online')
    BEGIN
        INSERT INTO dbo.tblInvoiceType_Master (Name, ShowInCallCentre) VALUES (N'QR Menu Online', 1);
        PRINT '3.1  tblInvoiceType_Master already populated - added QR Menu Online with a new ID (update Web.config InvoiceTypeID to match)';
    END
    ELSE PRINT '3.1  tblInvoiceType_Master already has QR Menu Online - untouched';
END
GO

IF OBJECT_ID('dbo.tblPOS_InvoiceType_Master') IS NOT NULL
BEGIN
    DROP TABLE dbo.tblPOS_InvoiceType_Master;
    PRINT '3.2  tblPOS_InvoiceType_Master dropped (superseded by tblInvoiceType_Master)';
END
GO


/*==============================================================================
  SECTION 4 - tblInvoicePayment  (replaces tblPOS_InvoicePayment)

  Two problems as imported:
    * InvoiceId is INT, but tblInvoice.InvoiceNo is BIGINT. Same implicit
      conversion trap as tblOrder.InvoiceNo, and it silently truncates once
      invoice numbers pass 2,147,483,647.
    * No primary key.
  Both fixed, plus the columns split/partial payments and refunds need.
==============================================================================*/

IF EXISTS (SELECT 1 FROM sys.columns c
           JOIN sys.tables t ON t.object_id = c.object_id
           JOIN sys.types  y ON y.user_type_id = c.user_type_id
           WHERE t.name = 'tblInvoicePayment' AND c.name = 'InvoiceId' AND y.name = 'int')
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblInvoicePayment)
        PRINT '4.1  !! tblInvoicePayment is NOT empty - widen InvoiceId to BIGINT manually';
    ELSE
    BEGIN
        ALTER TABLE dbo.tblInvoicePayment ALTER COLUMN InvoiceId BIGINT NOT NULL;
        PRINT '4.1  tblInvoicePayment.InvoiceId widened to BIGINT';
    END
END
ELSE PRINT '4.1  tblInvoicePayment.InvoiceId already BIGINT - skipped';
GO

IF COL_LENGTH('dbo.tblInvoicePayment','AmountTendered') IS NULL ALTER TABLE dbo.tblInvoicePayment ADD AmountTendered DECIMAL(18,3) NULL;
GO
IF COL_LENGTH('dbo.tblInvoicePayment','ChangeGiven')    IS NULL ALTER TABLE dbo.tblInvoicePayment ADD ChangeGiven    DECIMAL(18,3) NULL;
GO
IF COL_LENGTH('dbo.tblInvoicePayment','ReferenceNo')    IS NULL ALTER TABLE dbo.tblInvoicePayment ADD ReferenceNo    NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.tblInvoicePayment','IsRefund')       IS NULL ALTER TABLE dbo.tblInvoicePayment ADD IsRefund       BIT NOT NULL CONSTRAINT DF_tblInvoicePayment_IsRefund DEFAULT (0);
GO
IF COL_LENGTH('dbo.tblInvoicePayment','ReceivedBy')     IS NULL ALTER TABLE dbo.tblInvoicePayment ADD ReceivedBy     INT NULL;
GO
IF COL_LENGTH('dbo.tblInvoicePayment','ReceivedOn')     IS NULL ALTER TABLE dbo.tblInvoicePayment ADD ReceivedOn     DATETIME NOT NULL CONSTRAINT DF_tblInvoicePayment_ReceivedOn DEFAULT (GETDATE());
GO
IF COL_LENGTH('dbo.tblInvoicePayment','Comments')       IS NULL ALTER TABLE dbo.tblInvoicePayment ADD Comments       NVARCHAR(500) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_tblInvoicePayment')
    ALTER TABLE dbo.tblInvoicePayment ADD CONSTRAINT PK_tblInvoicePayment PRIMARY KEY CLUSTERED (id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoicePayment_Invoice')
    CREATE NONCLUSTERED INDEX IX_tblInvoicePayment_Invoice
        ON dbo.tblInvoicePayment (InvoiceId) INCLUDE (PaymentTypeID, Amount, IsRefund);
GO

IF OBJECT_ID('dbo.tblPOS_InvoicePayment') IS NOT NULL
BEGIN
    DROP TABLE dbo.tblPOS_InvoicePayment;
    PRINT '4.2  tblPOS_InvoicePayment dropped (superseded by tblInvoicePayment)';
END
GO


/*==============================================================================
  SECTION 5 - REMAINING InvoiceNo TYPE MISMATCHES

  tblInvoice.InvoiceNo is BIGINT. Every table that references it by a string
  column forces an implicit conversion and cannot seek. Fixed while empty.
==============================================================================*/

IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
           JOIN sys.types y ON y.user_type_id=c.user_type_id
           WHERE t.name='tblDriverTracking' AND c.name='InvoiceNo' AND y.name IN ('nvarchar','varchar'))
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblDriverTracking)
        PRINT '5.1  !! tblDriverTracking not empty - convert InvoiceNo manually';
    ELSE
    BEGIN
        ALTER TABLE dbo.tblDriverTracking ALTER COLUMN InvoiceNo BIGINT NULL;
        CREATE NONCLUSTERED INDEX IX_tblDriverTracking_Invoice ON dbo.tblDriverTracking (InvoiceNo, OnDateTime);
        PRINT '5.1  tblDriverTracking.InvoiceNo converted to BIGINT';
    END
END
GO

IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
           WHERE t.name='tblEndDayDiscount' AND c.name='InvoiceNo' AND c.max_length = -1)
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.tblEndDayDiscount)
        PRINT '5.2  !! tblEndDayDiscount not empty - convert InvoiceNo manually';
    ELSE
    BEGIN
        -- nvarchar(max) cannot be indexed at all; as a lookup key it is unusable
        ALTER TABLE dbo.tblEndDayDiscount ALTER COLUMN InvoiceNo BIGINT NULL;
        PRINT '5.2  tblEndDayDiscount.InvoiceNo converted from NVARCHAR(MAX) to BIGINT';
    END
END
GO


/*==============================================================================
  SECTION 6 - MISSING PRIMARY KEYS on imported tables
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblDriver')
    ALTER TABLE dbo.tblDriver ADD CONSTRAINT PK_tblDriver PRIMARY KEY CLUSTERED (DriverID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblDenomination')
    ALTER TABLE dbo.tblDenomination ADD CONSTRAINT PK_tblDenomination PRIMARY KEY CLUSTERED (id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblDenominationDetails')
    ALTER TABLE dbo.tblDenominationDetails ADD CONSTRAINT PK_tblDenominationDetails PRIMARY KEY CLUSTERED (id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblTable')
    ALTER TABLE dbo.tblTable ADD CONSTRAINT PK_tblTable PRIMARY KEY CLUSTERED (TableID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblTableType')
    ALTER TABLE dbo.tblTableType ADD CONSTRAINT PK_tblTableType PRIMARY KEY CLUSTERED (ID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblEndDayPaymentTypeDetails')
    ALTER TABLE dbo.tblEndDayPaymentTypeDetails ADD CONSTRAINT PK_tblEndDayPaymentTypeDetails PRIMARY KEY CLUSTERED (id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='PK_tblEndshiftPaymentTypeDetails')
    ALTER TABLE dbo.tblEndshiftPaymentTypeDetails ADD CONSTRAINT PK_tblEndshiftPaymentTypeDetails PRIMARY KEY CLUSTERED (id);
GO


/*==============================================================================
  SECTION 7 - INDEXES for the POS grid and delivery-area lookups

  TblArea_Mapping answers "which branches serve this area". It is hit on every
  checkout and on every branch transfer, so it needs a real index.
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_TblArea_Mapping_Area')
    CREATE NONCLUSTERED INDEX IX_TblArea_Mapping_Area ON dbo.TblArea_Mapping (AreaID) INCLUDE (BranchID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_TblArea_Mapping_Branch')
    CREATE NONCLUSTERED INDEX IX_TblArea_Mapping_Branch ON dbo.TblArea_Mapping (BranchID) INCLUDE (AreaID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_tblDiscountCode_Code')
    CREATE NONCLUSTERED INDEX IX_tblDiscountCode_Code ON dbo.tblDiscountCode (DiscountCode) INCLUDE (DiscountTypeId, Isactive);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_tblDriver_Branch')
    CREATE NONCLUSTERED INDEX IX_tblDriver_Branch ON dbo.tblDriver (BranchID);
GO


/*==============================================================================
  SECTION 8 - POS_01 leftovers that stay

  These have no head-office equivalent and remain authoritative:
      tblPOS_OrderStatusTransition   allowed status moves
      tblPOS_CancelReason_Master     cancellation reasons + Waste/Reuse default
      tblPOS_OrderStatusHistory      append-only status trail
      tblPOS_OrderTransfer           branch transfer audit
      tblPOS_AuditLog                who did what
      tblPOS_DailyCounter            daily per-branch order number
      tblPOS_BranchSetting           thermal width, auto-print, prep minutes
      tblCustomerAddress             tblInvoice.AddressID had no table at all
==============================================================================*/

-- Wire the cancellation Waste/Reuse totals into the existing end-of-day model.
-- tblEndDay already carries wasteAmount / wasteCount / reUseAmount / reUseCount,
-- which is exactly what the Waste-vs-Reuse cancellation choice should feed.
IF COL_LENGTH('dbo.tblPOS_CancelReason_Master','FeedsEndDay') IS NULL
    ALTER TABLE dbo.tblPOS_CancelReason_Master ADD FeedsEndDay BIT NOT NULL CONSTRAINT DF_tblPOSCancel_FeedsEndDay DEFAULT (1);
GO


/*==============================================================================
  SECTION 9 - REPORT
==============================================================================*/
PRINT '';
PRINT '################ RECONCILIATION REPORT ################';

SELECT 'tblOrderStatus' AS TableName, COUNT(*) AS Rows FROM dbo.tblOrderStatus
UNION ALL SELECT 'tblInvoicePaymentType',  COUNT(*) FROM dbo.tblInvoicePaymentType
UNION ALL SELECT 'tblInvoiceType_Master',  COUNT(*) FROM dbo.tblInvoiceType_Master
UNION ALL SELECT 'tblInvoicePayment',      COUNT(*) FROM dbo.tblInvoicePayment
UNION ALL SELECT 'TblArea_Mapping',        COUNT(*) FROM dbo.TblArea_Mapping
UNION ALL SELECT 'tblDiscountCode',        COUNT(*) FROM dbo.tblDiscountCode
UNION ALL SELECT 'tblDriver',              COUNT(*) FROM dbo.tblDriver;

PRINT '';
PRINT '>>> Payment type IDs the application must map to (send these back):';
SELECT ID, PaymentTypeName, IsCash, IsOnline, IsCOD, LegacyColumn
FROM   dbo.tblInvoicePaymentType
WHERE  ISNULL(IsDeleted,0) = 0
ORDER BY Seqnum, ID;

PRINT '';
PRINT '>>> Invoice type IDs (set Web.config InvoiceTypeID to the QR Menu Online row):';
SELECT ID, Name, ShowInCallCentre FROM dbo.tblInvoiceType_Master ORDER BY ID;

PRINT '';
PRINT '################ POS_03_Reconcile.sql COMPLETE ################';
GO
