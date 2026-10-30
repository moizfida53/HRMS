/**********************************************************************************
  POS_05_FixAndSeed.sql
  ------------------------------------------------------------------------------
  1. Fixes the one failure in POS_03 (the tblOrderStatus primary key).
  2. Seeds the configuration tables that came across empty and that the POS
     needs before it can do anything useful.
  3. Verifies the whole reconciliation and prints what the application must use.

  Idempotent - safe to re-run.
**********************************************************************************/

SET NOCOUNT ON;
GO

/*==============================================================================
  SECTION 1 - THE POS_03 FAILURE

  Msg 8111 "Cannot define PRIMARY KEY constraint on nullable column".

  CAUSE: ALTER COLUMN ... NOT NULL and ADD CONSTRAINT ... PRIMARY KEY were in
  the SAME batch. SQL Server compiles the batch against the metadata as it
  stood at parse time, so the constraint was still validated against the old
  nullable definition. Nothing to do with the data - the column was already
  clean. Splitting the two statements across batch boundaries is the fix.
==============================================================================*/

IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
           WHERE t.name = 'tblOrderStatus' AND c.name = 'OrderStatusID' AND c.is_nullable = 1)
BEGIN
    DELETE FROM dbo.tblOrderStatus WHERE OrderStatusID IS NULL;   -- none expected
    ALTER TABLE dbo.tblOrderStatus ALTER COLUMN OrderStatusID INT NOT NULL;
    PRINT '1.1  tblOrderStatus.OrderStatusID set to NOT NULL';
END
ELSE PRINT '1.1  tblOrderStatus.OrderStatusID already NOT NULL';
GO
-- ^ batch boundary is load-bearing: the metadata must be committed before the
--   constraint below is compiled.

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_tblOrderStatus')
BEGIN
    ALTER TABLE dbo.tblOrderStatus ADD CONSTRAINT PK_tblOrderStatus PRIMARY KEY CLUSTERED (OrderStatusID);
    PRINT '1.2  PK_tblOrderStatus created';
END
ELSE PRINT '1.2  PK_tblOrderStatus already exists';
GO


/*==============================================================================
  SECTION 2 - CASH DENOMINATIONS (Kuwaiti Dinar)

  Drives the denomination count on the end-of-shift / end-of-day cash-up
  (tblDenominationDetails) and the quick-tender buttons on the POS Pay popup.
  Without rows here, cash reconciliation has nothing to count.
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM dbo.tblDenomination)
BEGIN
    INSERT INTO dbo.tblDenomination (DenominationType, DenominationValue) VALUES
          (N'Note', 20.000)
        , (N'Note', 10.000)
        , (N'Note',  5.000)
        , (N'Note',  1.000)
        , (N'Note',  0.500)
        , (N'Note',  0.250)
        , (N'Coin',  0.100)
        , (N'Coin',  0.050)
        , (N'Coin',  0.020)
        , (N'Coin',  0.010)
        , (N'Coin',  0.005);
    PRINT '2.1  tblDenomination seeded with KWD notes and coins';
END
ELSE PRINT '2.1  tblDenomination already populated - untouched';
GO


/*==============================================================================
  SECTION 3 - TABLE TYPES / PRINTER ROUTING

  tblTableType.InvoicePrinter and .AssignDriverPrint decide which physical
  printer each document goes to. tblTableType.ID is also what tblOrder.TableType
  refers to, and sp_POS_ProcessOrder currently writes 0 there.
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM dbo.tblTableType)
BEGIN
    INSERT INTO dbo.tblTableType (ID, Description, InvoicePrinter, AssignDriverPrint) VALUES
          (0, N'Online / QR Menu', N'Cashier',  N'Dispatch')
        , (1, N'Dine In',         N'Cashier',  NULL)
        , (2, N'Take Away',       N'Cashier',  NULL)
        , (3, N'Delivery',        N'Cashier',  N'Dispatch');
    PRINT '3.1  tblTableType seeded (ID 0 matches what the order proc writes)';
END
ELSE PRINT '3.1  tblTableType already populated - untouched';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tblPrinter)
BEGIN
    INSERT INTO dbo.tblPrinter (PrinterNo, PrinterName) VALUES
          (1, N'Cashier')
        , (2, N'Kitchen')
        , (3, N'Dispatch');
    PRINT '3.2  tblPrinter seeded with placeholder names - REPLACE with the real branch printer names';
END
ELSE PRINT '3.2  tblPrinter already populated - untouched';
GO


/*==============================================================================
  SECTION 4 - DELIVERY AREA -> BRANCH MAPPING

  TblArea_Mapping is empty, while tblArea has 121 rows each carrying a BranchID
  (defaulting to 1). Until this is populated, the POS cannot answer "which
  branch serves this area", so sp_POS_ProcessOrder skips the check entirely and
  transfers cannot be validated.

  This seeds the mapping from tblArea.BranchID as a starting point. It is almost
  certainly incomplete: with 7 branches and every area defaulting to branch 1,
  the result is "branch 1 delivers everywhere". Treat it as a placeholder and
  correct it per branch before go-live.
==============================================================================*/

IF NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping)
BEGIN
    INSERT INTO dbo.TblArea_Mapping (AreaID, BranchID)
    SELECT a.AreaID, ISNULL(a.BranchID, 1)
    FROM   dbo.tblArea a
    WHERE  a.AreaID IS NOT NULL;

    PRINT '4.1  TblArea_Mapping seeded from tblArea.BranchID - ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rows';
    PRINT '     !! PLACEHOLDER: verify which branches really serve which areas.';
END
ELSE PRINT '4.1  TblArea_Mapping already populated - untouched';
GO

-- How lopsided is it? A single branch covering everything means it is unconfigured.
SELECT   b.id AS BranchID, b.branchName, COUNT(m.AreaID) AS AreasServed
FROM     dbo.tblbranch b
LEFT JOIN dbo.TblArea_Mapping m ON m.BranchID = b.id
GROUP BY b.id, b.branchName
ORDER BY b.id;
GO


/*==============================================================================
  SECTION 5 - POS USER ROLES

  tblUser has two rows (Admin RoleID 1, Ora Blu RoleID 4) and no role table, so
  RoleID is currently a bare number. The POS needs named roles because
  cancellation, refund and transfer must be restricted.
==============================================================================*/

IF OBJECT_ID('dbo.tblPOS_Role_Master') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_Role_Master
    (
          RoleID           INT           NOT NULL
        , RoleName         NVARCHAR(50)  NOT NULL
        , CanChangeStatus  BIT           NOT NULL DEFAULT (1)
        , CanCancel        BIT           NOT NULL DEFAULT (0)
        , CanRefund        BIT           NOT NULL DEFAULT (0)
        , CanTransfer      BIT           NOT NULL DEFAULT (0)
        , CanTakePayment   BIT           NOT NULL DEFAULT (1)
        , CanViewReports   BIT           NOT NULL DEFAULT (0)
        , CanEndDay        BIT           NOT NULL DEFAULT (0)
        , CanManageMasters BIT           NOT NULL DEFAULT (0)
        , CONSTRAINT PK_tblPOS_Role_Master PRIMARY KEY CLUSTERED (RoleID)
    );

    INSERT INTO dbo.tblPOS_Role_Master
        (RoleID, RoleName, CanChangeStatus, CanCancel, CanRefund, CanTransfer, CanTakePayment, CanViewReports, CanEndDay, CanManageMasters)
    VALUES
          (1, N'Administrator', 1,1,1,1,1,1,1,1)
        , (2, N'Manager',       1,1,1,1,1,1,1,0)
        , (3, N'Supervisor',    1,1,0,1,1,1,0,0)
        , (4, N'Cashier',       1,0,0,0,1,0,0,0)
        , (5, N'Kitchen',       1,0,0,0,0,0,0,0)
        , (6, N'Driver',        1,0,0,0,1,0,0,0);
    PRINT '5.1  tblPOS_Role_Master created and seeded';
    PRINT '     Existing tblUser rows: Admin=RoleID 1 (Administrator), Ora Blu=RoleID 4 (Cashier)';
END
ELSE PRINT '5.1  tblPOS_Role_Master already exists';
GO


/*==============================================================================
  SECTION 6 - VERIFICATION
==============================================================================*/
PRINT '';
PRINT '################ VERIFICATION ################';
PRINT '';

PRINT '--- POS duplicates removed (all four should say GONE) ---';
SELECT 'tblPOS_OrderStatus_Master' AS Obj, CASE WHEN OBJECT_ID('dbo.tblPOS_OrderStatus_Master') IS NULL THEN 'GONE' ELSE 'STILL PRESENT' END AS State
UNION ALL SELECT 'tblPOS_PaymentType_Master', CASE WHEN OBJECT_ID('dbo.tblPOS_PaymentType_Master') IS NULL THEN 'GONE' ELSE 'STILL PRESENT' END
UNION ALL SELECT 'tblPOS_InvoiceType_Master', CASE WHEN OBJECT_ID('dbo.tblPOS_InvoiceType_Master') IS NULL THEN 'GONE' ELSE 'STILL PRESENT' END
UNION ALL SELECT 'tblPOS_InvoicePayment',     CASE WHEN OBJECT_ID('dbo.tblPOS_InvoicePayment')     IS NULL THEN 'GONE' ELSE 'STILL PRESENT' END;

PRINT '';
PRINT '--- Every InvoiceNo reference must now be BIGINT ---';
SELECT t.name AS TableName, c.name AS ColumnName, y.name AS DataType,
       CASE WHEN y.name = 'bigint' THEN 'OK' ELSE '>>> STILL WRONG' END AS Verdict
FROM   sys.columns c
JOIN   sys.tables  t ON t.object_id = c.object_id
JOIN   sys.types   y ON y.user_type_id = c.user_type_id
WHERE  c.name IN ('InvoiceNo','InvoiceId')
  AND  t.name LIKE 'tbl%'
ORDER BY t.name;

PRINT '';
PRINT '--- Order statuses ---';
SELECT OrderStatusID, OrderStatusName, SortOrder, ColorHex, IsTerminal, AppliesToPickup, AppliesToDelivery, MessageSend
FROM   dbo.tblOrderStatus ORDER BY SortOrder;

PRINT '';
PRINT '--- Payment types: these IDs are what the application will use ---';
SELECT ID, PaymentTypeName, IsCash, IsOnline, IsCOD, RequiresReference, LegacyColumn
FROM   dbo.tblInvoicePaymentType WHERE ISNULL(IsDeleted,0) = 0 ORDER BY Seqnum, ID;

PRINT '';
PRINT '--- Invoice types: set Web.config InvoiceTypeID to the QR Menu Online ID ---';
SELECT ID, Name, ShowInCallCentre FROM dbo.tblInvoiceType_Master ORDER BY ID;

PRINT '';
PRINT '--- Objects the POS depends on ---';
SELECT 'sp_POS_ProcessOrder' AS Obj, CASE WHEN OBJECT_ID('dbo.sp_POS_ProcessOrder') IS NOT NULL THEN 'OK' ELSE '>>> MISSING' END AS State
UNION ALL SELECT 'TVP_POS_OrderItem',    CASE WHEN TYPE_ID('dbo.TVP_POS_OrderItem')     IS NOT NULL THEN 'OK' ELSE '>>> MISSING' END
UNION ALL SELECT 'tblCustomerAddress',   CASE WHEN OBJECT_ID('dbo.tblCustomerAddress')  IS NOT NULL THEN 'OK' ELSE '>>> MISSING' END
UNION ALL SELECT 'IX_tblInvoice_POSGrid',CASE WHEN EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_tblInvoice_POSGrid') THEN 'OK' ELSE '>>> MISSING' END;

PRINT '';
PRINT '################ POS_05 COMPLETE ################';
GO
