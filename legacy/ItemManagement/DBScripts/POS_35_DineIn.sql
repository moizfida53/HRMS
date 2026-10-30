/**********************************************************************************
  POS_35_DineIn.sql
  ------------------------------------------------------------------------------
  Dine-In module: floor plan, table locking, ordering against a table, adding
  items, transfer, split, layout save.

  Orders are NOT stored anywhere new. Every Dine-In bill is an ordinary
  tblInvoice / tblOrder row created by sp_POS_ProcessOrder with
      OrderType   = 3 (Dine In)
      InvoiceType = the 'Dine In' row of tblInvoiceType_Master
  so every existing report, the Order List, Print, Take Payment, Delete Line
  and Cancel keep working on them unchanged.

  What this script adds
  ---------------------
  SECTION 1  tblInvoice.TableID / TableSessionID (only if missing)
             tblPOS_TableArea      - display name + order of each TableType
             tblPOS_TableSession   - one row per seating. A UNIQUE filtered
                                     index (one open session per table) is the
                                     lock: two tablets tapping the same table at
                                     the same instant cannot both win.
             TVP_POS_DineInSplitLine, TVP_POS_TablePosition
  SECTION 2  fn_POS_DineIn_Tables   - the floor rows, one shape for every proc
  SECTION 3  procedures:
                sp_POS_DineIn_GetFloor       areas + tables
                sp_POS_DineIn_GetTable       one table + its bills + lines
                sp_POS_DineIn_Context        invoice-type ids, walk-in customer
                sp_POS_DineIn_LockTable      Status = 1 (occupied)
                sp_POS_DineIn_SetGuest       name / mobile / persons
                sp_POS_DineIn_ReleaseTable   Status = 0 (vacant)
                sp_POS_DineIn_AttachInvoice  link a new invoice to the table
                sp_POS_DineIn_AddItems       append lines to an open bill
                sp_POS_DineIn_TransferTable  move guests + bills to another table
                sp_POS_DineIn_SplitInvoice   move lines to a new bill
                sp_POS_DineIn_CloseIfSettled free the table once all bills are
                                             paid or cancelled
                sp_POS_DineIn_SaveLayout     admin drag-and-drop X / Y
                sp_POS_DineIn_GetMenu        categories + items for the order popup

  Run after POS_34_UserBranchAccess.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 0 - what is there now (read the output once, then ignore it)
==============================================================================*/
PRINT '===== SECTION 0 : current shape =====';
SELECT  TableName = OBJECT_NAME(c.object_id), ColumnName = c.name, DataType = TYPE_NAME(c.user_type_id)
FROM    sys.columns c
WHERE   c.object_id IN (OBJECT_ID('dbo.tblTable'), OBJECT_ID('dbo.tblTableType'))
   OR  (c.object_id = OBJECT_ID('dbo.tblInvoice') AND (c.name LIKE '%Table%' OR c.name = 'Person'))
ORDER BY TableName, c.column_id;
GO

/*==============================================================================
  SECTION 1 - schema
==============================================================================*/
IF COL_LENGTH('dbo.tblInvoice', 'TableID') IS NULL
BEGIN
    ALTER TABLE dbo.tblInvoice ADD TableID INT NULL;
    PRINT '1.1  tblInvoice.TableID added';
END
ELSE PRINT '1.1  tblInvoice.TableID already exists - reused';
GO

IF COL_LENGTH('dbo.tblInvoice', 'TableSessionID') IS NULL
BEGIN
    ALTER TABLE dbo.tblInvoice ADD TableSessionID INT NULL;
    PRINT '1.2  tblInvoice.TableSessionID added';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoice_TableSessionID' AND object_id = OBJECT_ID('dbo.tblInvoice'))
    CREATE NONCLUSTERED INDEX IX_tblInvoice_TableSessionID ON dbo.tblInvoice (TableSessionID)
    INCLUDE (BillAmount, Discount, Deleted, OrderStatusID);
-- Deliberately NOT a filtered index: a filtered index on tblInvoice would make
-- every older procedure created with QUOTED_IDENTIFIER OFF fail when it writes
-- an invoice (error 1934). A plain index has no such requirement.
GO

/*---- 1.3 Areas / floors ------------------------------------------------------
  tblTable.TableType is the floor or area a table belongs to. This table only
  gives each value a name and an order for the tabs. Rename freely:
      UPDATE dbo.tblPOS_TableArea SET AreaName = N'Outer Area' WHERE TableType = 2;
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_TableArea') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_TableArea
    (
          TableType  INT           NOT NULL CONSTRAINT PK_tblPOS_TableArea PRIMARY KEY CLUSTERED
        , AreaName   NVARCHAR(100) NOT NULL
        , SortOrder  INT           NOT NULL CONSTRAINT DF_tblPOS_TableArea_Sort   DEFAULT (0)
        , IsActive   BIT           NOT NULL CONSTRAINT DF_tblPOS_TableArea_Active DEFAULT (1)
    );
    PRINT '1.3  tblPOS_TableArea created';
END
GO

-- One row per TableType in use. A tblTableType description is used when it
-- reads like an area; the channel names some installs seeded there are not.
INSERT INTO dbo.tblPOS_TableArea (TableType, AreaName, SortOrder)
SELECT  t.TableType
      , CASE WHEN tt.Description IS NULL
               OR LTRIM(RTRIM(tt.Description)) IN (N'', N'Dine In', N'Take Away', N'Delivery', N'Online / QR Menu')
             THEN CASE WHEN t.TableType <= 0 THEN N'Main Area' ELSE N'Floor ' + CAST(t.TableType AS NVARCHAR(10)) END
             ELSE LTRIM(RTRIM(tt.Description)) END
      , t.TableType
FROM   (SELECT DISTINCT TableType = ISNULL(TableType, 0) FROM dbo.tblTable) t
LEFT JOIN dbo.tblTableType tt ON tt.ID = t.TableType
WHERE  NOT EXISTS (SELECT 1 FROM dbo.tblPOS_TableArea a WHERE a.TableType = t.TableType);
PRINT CONCAT('1.3  tblPOS_TableArea rows added: ', @@ROWCOUNT);
GO

/*---- 1.4 Seatings ------------------------------------------------------------*/
IF OBJECT_ID('dbo.tblPOS_TableSession') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_TableSession
    (
          SessionID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tblPOS_TableSession PRIMARY KEY CLUSTERED
        , TableID       INT            NOT NULL
        , BranchID      INT            NULL
        , CustomerName  NVARCHAR(200)  NULL
        , Mobile        NVARCHAR(30)   NULL
        , Persons       INT            NOT NULL CONSTRAINT DF_tblPOS_TableSession_Persons DEFAULT (1)
        , OpenedOn      DATETIME       NOT NULL CONSTRAINT DF_tblPOS_TableSession_Opened  DEFAULT (GETDATE())
        , OpenedBy      INT            NULL
        , OpenedByName  NVARCHAR(100)  NULL
        , ClosedOn      DATETIME       NULL
        , ClosedBy      INT            NULL
        , ClosedByName  NVARCHAR(100)  NULL
        , CloseReason   NVARCHAR(50)   NULL
    );
    PRINT '1.4  tblPOS_TableSession created';
END
GO

-- THE LOCK. At most one open seating per table, enforced by SQL Server itself.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tblPOS_TableSession_Open' AND object_id = OBJECT_ID('dbo.tblPOS_TableSession'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_tblPOS_TableSession_Open
        ON dbo.tblPOS_TableSession (TableID) WHERE ClosedOn IS NULL;
GO

/*---- 1.5 Table types ---------------------------------------------------------*/
IF TYPE_ID('dbo.TVP_POS_DineInSplitLine') IS NULL
    CREATE TYPE dbo.TVP_POS_DineInSplitLine AS TABLE
    (
          OrderID   BIGINT NOT NULL PRIMARY KEY
        , Quantity  INT    NOT NULL
    );
GO
IF TYPE_ID('dbo.TVP_POS_TablePosition') IS NULL
    CREATE TYPE dbo.TVP_POS_TablePosition AS TABLE
    (
          TableID  INT           NOT NULL PRIMARY KEY
        , Xaxis    DECIMAL(18,2) NOT NULL
        , Yaxis    DECIMAL(18,2) NOT NULL
    );
GO

/*==============================================================================
  SECTION 2 - one shape for a floor row
  "Occupied" = an open seating, OR a legacy Status = 1 left behind by the old
  system (shown red so nobody seats over it; the popup offers Free table).
==============================================================================*/
IF OBJECT_ID('dbo.fn_POS_DineIn_Tables') IS NOT NULL DROP FUNCTION dbo.fn_POS_DineIn_Tables;
GO
CREATE FUNCTION dbo.fn_POS_DineIn_Tables ()
RETURNS TABLE
AS
RETURN
(
    SELECT  t.TableID
          , Table_No      = LTRIM(RTRIM(CAST(t.Table_No AS NVARCHAR(30))))
          , Capacity      = ISNULL(TRY_CAST(t.Capacity AS INT), 4)
          , TableType     = ISNULL(t.TableType, 0)
          , Xaxis         = CAST(ISNULL(TRY_CAST(t.Xaxis AS DECIMAL(18,2)), 0) AS DECIMAL(18,2))
          , Yaxis         = CAST(ISNULL(TRY_CAST(t.Yaxis AS DECIMAL(18,2)), 0) AS DECIMAL(18,2))
          , Status        = CAST(CASE WHEN s.SessionID IS NOT NULL OR ISNULL(TRY_CAST(t.Status AS INT), 0) = 1
                                      THEN 1 ELSE 0 END AS INT)
          , IsLegacyLock  = CAST(CASE WHEN s.SessionID IS NULL AND ISNULL(TRY_CAST(t.Status AS INT), 0) = 1
                                      THEN 1 ELSE 0 END AS BIT)
          , s.SessionID
          , s.CustomerName
          , s.Mobile
          , Persons       = ISNULL(s.Persons, 0)
          , s.OpenedOn
          , s.OpenedByName
          , MinutesSeated = CASE WHEN s.OpenedOn IS NULL THEN 0 ELSE DATEDIFF(MINUTE, s.OpenedOn, GETDATE()) END
          , BillAmount    = CAST(ISNULL(b.Bill, 0) AS DECIMAL(18,3))
          , AmountPaid    = CAST(ISNULL(b.Paid, 0) AS DECIMAL(18,3))
          , InvoiceCount  = ISNULL(b.Cnt, 0)
    FROM      dbo.tblTable t
    LEFT JOIN dbo.tblPOS_TableSession s
           ON s.TableID = t.TableID AND s.ClosedOn IS NULL
    OUTER APPLY
    (
        SELECT  Bill = SUM(i.FinalAmount + ISNULL(i.DeliveryCharges, 0))
              , Paid = SUM(ISNULL(pp.Paid, 0))
              , Cnt  = COUNT(*)
        FROM    dbo.tblInvoice i
        OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                     FROM   dbo.tblInvoicePayment p
                     WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
        WHERE   s.SessionID IS NOT NULL
          AND   i.TableSessionID = s.SessionID
          AND   ISNULL(i.Deleted, 0) = 0
          AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
    ) b
);
GO

/*==============================================================================
  SECTION 3 - procedures
==============================================================================*/

/*---- 3.1 floor ---------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_GetFloor') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_GetFloor;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_GetFloor
AS
BEGIN
    SET NOCOUNT ON;

    -- A TableType added to tblTable after POS_35 ran gets its area row now,
    -- so new tables never go missing for want of a tab. Rename it later in
    -- tblPOS_TableArea.
    INSERT INTO dbo.tblPOS_TableArea (TableType, AreaName, SortOrder)
    SELECT  x.TableType
          , CASE WHEN x.TableType <= 0 THEN N'Main Area' ELSE N'Floor ' + CAST(x.TableType AS NVARCHAR(10)) END
          , x.TableType
    FROM   (SELECT DISTINCT TableType = ISNULL(TableType, 0) FROM dbo.tblTable) x
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.tblPOS_TableArea a WHERE a.TableType = x.TableType);

    -- 0: areas that actually have tables
    SELECT   a.TableType, a.AreaName, a.SortOrder
    FROM     dbo.tblPOS_TableArea a
    WHERE    a.IsActive = 1
      AND    EXISTS (SELECT 1 FROM dbo.tblTable t WHERE ISNULL(t.TableType, 0) = a.TableType)
    ORDER BY a.SortOrder, a.TableType;

    -- 1: tables
    SELECT   f.*
    FROM     dbo.fn_POS_DineIn_Tables() f
    ORDER BY f.TableType, TRY_CAST(f.Table_No AS INT), f.Table_No;
END
GO

/*---- 3.2 one table: header, bills, lines -------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_GetTable') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_GetTable;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_GetTable
    @TableID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);

    -- 0: the table
    SELECT f.*, AreaName = a.AreaName
    FROM   dbo.fn_POS_DineIn_Tables() f
    LEFT JOIN dbo.tblPOS_TableArea a ON a.TableType = f.TableType
    WHERE  f.TableID = @TableID;

    -- 1: live bills of this seating, oldest first
    SELECT  i.InvoiceNo
          , InvoiceNumShow = CAST(i.InvoiceNumShow AS NVARCHAR(30))
          , i.RunningOrder
          , i.InvoiceDate
          , i.BillAmount
          , Discount    = ISNULL(i.Discount, 0)
          , NetPayable  = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
          , AmountPaid  = ISNULL(pp.Paid, 0)
          , i.OrderStatusID
          , i.PrintCount
    FROM    dbo.tblInvoice i
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
    ORDER BY i.InvoiceNo;

    -- 2: lines of those bills
    SELECT  o.InvoiceNo
          , o.OrderID
          , o.ItemID
          , o.ParentOrderID
          , LineType  = ISNULL(o.LineType, 1)
          , ItemName  = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , o.Quantity
          , o.Price
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , o.Comments
          , IsTakeAway = CAST(CASE WHEN LEFT(LTRIM(ISNULL(o.Comments, N'')), 9) = N'TAKE AWAY' THEN 1 ELSE 0 END AS BIT)
          , o.OrderDate
    FROM    dbo.tblOrder o
    JOIN    dbo.tblInvoice i ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
      AND   ISNULL(o.Deleted, 0) = 0
    ORDER BY o.InvoiceNo, o.OrderID;
END
GO

/*---- 3.3 ids the C# side needs before calling sp_POS_ProcessOrder ------------
  Resolved by NAME, never hard-coded: tblInvoiceType_Master uses IDENTITY keys.
  The walk-in customer stops sp_POS_ProcessOrder creating a blank tblCustomer
  row for every table that orders without a name or a mobile.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_Context') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_Context;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_Context
      @BrandID  INT = NULL
    , @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DineIn INT, @TakeAway INT, @WalkIn INT, @DineInTT INT, @Cash INT, @BranchBrand INT;

    -- the brand a branch belongs to, when the user record carries none
    IF @BranchID IS NOT NULL AND COL_LENGTH('dbo.tblbranch', 'BrandID') IS NOT NULL
        EXEC sp_executesql N'SELECT TOP 1 @bb = BrandID FROM dbo.tblbranch WHERE id = @b;',
             N'@b INT, @bb INT OUTPUT', @b = @BranchID, @bb = @BranchBrand OUTPUT;
    IF ISNULL(@BrandID, 0) = 0 SET @BrandID = @BranchBrand;

    -- bills start against plain Cash; the real tender is recorded by Pay
    SELECT TOP 1 @Cash = ID FROM dbo.tblInvoicePaymentType
    WHERE  IsCash = 1 AND ISNULL(IsCOD, 0) = 0 AND ISNULL(IsDeleted, 0) = 0 ORDER BY Seqnum, ID;

    SELECT TOP 1 @DineIn = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') = N'DineIn' ORDER BY ID;

    SELECT TOP 1 @TakeAway = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') IN (N'TakeAway', N'Takeaway') ORDER BY ID;

    SELECT TOP 1 @DineInTT = ID FROM dbo.tblTableType
    WHERE  REPLACE(REPLACE(Description, N'-', N''), N' ', N'') = N'DineIn' ORDER BY ID;

    SELECT TOP 1 @WalkIn = id FROM dbo.tblCustomer
    WHERE  firstName = N'Walk-in Customer' AND mobile IS NULL AND ISNULL(IsDeleted, 0) = 0
    ORDER BY id;

    IF @WalkIn IS NULL
    BEGIN
        INSERT INTO dbo.tblCustomer (firstName, BrandID) VALUES (N'Walk-in Customer', @BrandID);
        SET @WalkIn = CAST(SCOPE_IDENTITY() AS INT);
    END

    SELECT DineInTypeID      = @DineIn
         , TakeAwayTypeID    = @TakeAway
         , WalkInCustomerID  = @WalkIn
         , DineInTableTypeID = ISNULL(@DineInTT, 0)
         , CashPaymentTypeID = @Cash
         , BrandID           = ISNULL(@BrandID, 0);
END
GO

/*---- 3.4 lock: vacant -> occupied --------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_LockTable') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_LockTable;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_LockTable
      @TableID   INT
    , @BranchID  INT           = NULL
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Err NVARCHAR(300), @Code VARCHAR(20) = 'Error', @SessionID INT, @By NVARCHAR(100);

    IF NOT EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @TableID)
        SET @Err = N'Table not found.';
    ELSE
    BEGIN
        SELECT @SessionID = SessionID, @By = OpenedByName
        FROM   dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL;

        IF @SessionID IS NOT NULL
            SELECT @Err = N'This table was just taken' + ISNULL(N' by ' + @By, N'') + N'.', @Code = 'Occupied';
        ELSE IF EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @TableID AND ISNULL(TRY_CAST(Status AS INT), 0) = 1)
            SELECT @Err = N'This table is marked occupied. Free it first.', @Code = 'Occupied';
    END

    IF @Err IS NULL
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            INSERT INTO dbo.tblPOS_TableSession (TableID, BranchID, OpenedBy, OpenedByName)
            VALUES (@TableID, @BranchID, @UserID, @UserName);
            SET @SessionID = CAST(SCOPE_IDENTITY() AS INT);

            UPDATE dbo.tblTable SET Status = 1 WHERE TableID = @TableID;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            -- 2601 / 2627: another device won the race on UX_tblPOS_TableSession_Open
            IF ERROR_NUMBER() IN (2601, 2627)
                SELECT @Err = N'This table was just taken on another device.', @Code = 'Occupied';
            ELSE
                SET @Err = ERROR_MESSAGE();
        END CATCH
    END

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', Code = @Code, ErrorMessage = @Err, SessionID = CAST(NULL AS INT);
        RETURN;
    END

    SELECT Message = 'Success', Code = 'OK', ErrorMessage = CAST(NULL AS NVARCHAR(300)), SessionID = @SessionID;
END
GO

/*---- 3.5 guest details -------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_SetGuest') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_SetGuest;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_SetGuest
      @TableID       INT
    , @CustomerName  NVARCHAR(200) = NULL
    , @Mobile        NVARCHAR(30)  = NULL
    , @Persons       INT           = 1
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblPOS_TableSession
       SET CustomerName = NULLIF(LTRIM(RTRIM(@CustomerName)), N'')
         , Mobile       = NULLIF(LTRIM(RTRIM(@Mobile)), N'')
         , Persons      = CASE WHEN @Persons < 1 THEN 1 WHEN @Persons > 999 THEN 999 ELSE @Persons END
     WHERE TableID = @TableID AND ClosedOn IS NULL;

    IF @@ROWCOUNT = 0
        SELECT Message = 'Fail', ErrorMessage = N'This table is no longer open.';
    ELSE
        SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END
GO

/*---- 3.6 release: occupied -> vacant -----------------------------------------
  Refused while a bill on the table is still unpaid - freeing it then would
  hide money owed. @Force is for a manager clearing a stuck table.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_ReleaseTable') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_ReleaseTable;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_ReleaseTable
      @TableID   INT
    , @Reason    NVARCHAR(50)  = N'Released'
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
    , @Force     BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);

    IF @Force = 0 AND @SessionID IS NOT NULL AND EXISTS
    (
        SELECT 1
        FROM   dbo.tblInvoice i
        WHERE  i.TableSessionID = @SessionID
          AND  ISNULL(i.Deleted, 0) = 0
          AND  ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
          AND  i.FinalAmount + ISNULL(i.DeliveryCharges, 0) >
               ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                       FROM dbo.tblInvoicePayment p
                       WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0), 0) + 0.001
    )
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This table still has an unpaid bill. Pay or delete it first.';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @SessionID IS NOT NULL
            UPDATE dbo.tblPOS_TableSession
               SET ClosedOn = GETDATE(), ClosedBy = @UserID, ClosedByName = @UserName, CloseReason = @Reason
             WHERE SessionID = @SessionID;

        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @TableID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END
GO

/*---- 3.7 frees the table once nothing on it is owed --------------------------
  Called after Pay and after Delete Invoice. Leaves the table occupied while at
  least one live bill is unpaid; frees it otherwise. A table with no bills at
  all (guests seated, nothing ordered) is left alone - closing it is a person's
  decision, not a side effect.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_CloseIfSettled') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_CloseIfSettled;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_CloseIfSettled
      @TableID   INT
    , @Reason    NVARCHAR(50)  = N'Settled'
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);
    DECLARE @Live INT = 0, @Unpaid INT = 0, @Ever INT = 0;

    IF @SessionID IS NOT NULL
    BEGIN
        SELECT @Ever = COUNT(*) FROM dbo.tblInvoice WHERE TableSessionID = @SessionID;

        SELECT @Live   = COUNT(*)
             , @Unpaid = SUM(CASE WHEN i.FinalAmount + ISNULL(i.DeliveryCharges, 0) >
                                       ISNULL(pp.Paid, 0) + 0.001 THEN 1 ELSE 0 END)
        FROM   dbo.tblInvoice i
        OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                     FROM dbo.tblInvoicePayment p
                     WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
        WHERE  i.TableSessionID = @SessionID
          AND  ISNULL(i.Deleted, 0) = 0
          AND  ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8);
    END

    IF @SessionID IS NOT NULL AND @Ever > 0 AND ISNULL(@Unpaid, 0) = 0
    BEGIN
        UPDATE dbo.tblPOS_TableSession
           SET ClosedOn = GETDATE(), ClosedBy = @UserID, ClosedByName = @UserName, CloseReason = @Reason
         WHERE SessionID = @SessionID;
        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @TableID;

        SELECT Message = 'Success', Freed = CAST(1 AS BIT);
        RETURN;
    END

    SELECT Message = 'Success', Freed = CAST(0 AS BIT);
END
GO

/*---- 3.8 link a freshly created invoice to the table -------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_AttachInvoice') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_AttachInvoice;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_AttachInvoice
      @InvoiceNo          BIGINT
    , @TableID            INT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Persons INT, @TableNo NVARCHAR(30);

    SELECT @SessionID = s.SessionID, @Persons = s.Persons
    FROM   dbo.tblPOS_TableSession s WHERE s.TableID = @TableID AND s.ClosedOn IS NULL;

    SELECT @TableNo = LTRIM(RTRIM(CAST(Table_No AS NVARCHAR(30)))) FROM dbo.tblTable WHERE TableID = @TableID;

    IF @SessionID IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'The table was freed before the order was saved.';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET TableID = @TableID, TableSessionID = @SessionID, Person = ISNULL(@Persons, 1)
             , WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblOrder SET TableType = @DineInTableTypeID, WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblPOS_OrderStatusHistory
           SET Comments = N'Dine-In order, table ' + ISNULL(@TableNo, N'?')
             , ChangedBy = @UserID, ChangedByName = ISNULL(@UserName, ChangedByName)
         WHERE InvoiceNo = @InvoiceNo AND FromStatusID IS NULL;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInAttach', @UserID, @UserName,
                CONCAT(N'TableID=', @TableID, N'; Table=', @TableNo, N'; Session=', @SessionID));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END
GO

/*---- 3.9 append items to an open bill ----------------------------------------
  Same pricing rule as sp_POS_ProcessOrder: the price comes from tblItems, never
  from the browser. BillAmount is rebuilt from the lines (FinalAmount is the
  computed BillAmount - Discount).
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_AddItems') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_AddItems;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_AddItems
      @InvoiceNo          BIGINT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
    , @dtOrderItems       dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Status INT, @BranchID INT, @WaiterID INT
          , @DiscountTypeID INT, @Discount DECIMAL(18,3), @Bill DECIMAL(18,3), @Added INT;

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @WaiterID = WaiterID
         , @DiscountTypeID = DiscountTypeID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    IF @Status IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Bill not found.'; RETURN;
    END
    IF @Status IN (6, 7, 8)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This bill is cancelled or refunded.'; RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Add at least one item.'; RETURN;
    END

    -- @DineInTableTypeID = -1 means a Take Away bill: new lines carry whatever
    -- the bill's first line already carries instead of the Dine-In type.
    DECLARE @LineTableType INT = @DineInTableTypeID;
    IF @DineInTableTypeID < 0
    BEGIN
        SET @LineTableType = NULL;
        SELECT TOP 1 @LineTableType = o.TableType FROM dbo.tblOrder o WHERE o.InvoiceNo = @InvoiceNo ORDER BY o.OrderID;
        SET @LineTableType = ISNULL(@LineTableType, 0);
    END

    DECLARE @lines TABLE
    (
          Seq INT IDENTITY(1,1) PRIMARY KEY, ResolvedItemID INT NULL, ItemName NVARCHAR(200) NULL
        , Quantity INT NOT NULL, UnitPrice DECIMAL(18,3) NOT NULL, LineType TINYINT NOT NULL
        , CartItemUniqID INT NULL, Comments NVARCHAR(MAX) NULL, Extra NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, LineType, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, 0) AS DECIMAL(18,3))
          , ISNULL(d.LineType, 1), d.CartItemUniqID, d.Comments, d.Extra
    FROM    @dtOrderItems d
    CROSS APPLY (SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE FROM dbo.tblItems t
                 WHERE t.ID = d.ItemID OR (d.HID IS NOT NULL AND t.HID = d.HID)
                 ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END) it;

    IF NOT EXISTS (SELECT 1 FROM @lines)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'None of those items could be found.'; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , ISNULL(@UserID, @WaiterID), 0, 0, 0, 0, 0
             , @Now, @LineTableType, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;
        SET @Added = @@ROWCOUNT;

        SELECT @Bill = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @Bill, ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInAddItems', @UserID, @UserName,
                CONCAT(N'Lines=', @Added, N'; NewBill=', @Bill));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300))
         , InvoiceNo = @InvoiceNo, LinesAdded = @Added, BillAmount = @Bill
         , NetPayable = @Bill - @Discount;
END
GO

/*---- 3.10 transfer guests and bills to another table -------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_TransferTable') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_TransferTable;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_TransferTable
      @FromTableID  INT
    , @ToTableID    INT
    , @UserID       INT           = NULL
    , @UserName     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Err NVARCHAR(300);

    SELECT @SessionID = SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @FromTableID AND ClosedOn IS NULL;

    IF @FromTableID = @ToTableID
        SET @Err = N'Pick a different table.';
    ELSE IF @SessionID IS NULL
        SET @Err = N'There is nobody seated at this table.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @ToTableID)
        SET @Err = N'Target table not found.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.fn_POS_DineIn_Tables() WHERE TableID = @ToTableID AND Status = 1)
        SET @Err = N'That table is occupied. Pick a vacant one.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblPOS_TableSession SET TableID = @ToTableID WHERE SessionID = @SessionID;
        UPDATE dbo.tblInvoice SET TableID = @ToTableID WHERE TableSessionID = @SessionID;
        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @FromTableID;
        UPDATE dbo.tblTable SET Status = 1 WHERE TableID = @ToTableID;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('TableSession', @SessionID, 'DineInTransfer', @UserID, @UserName,
                CONCAT(N'FromTableID=', @FromTableID, N'; ToTableID=', @ToTableID));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail',
               ErrorMessage = CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                                   THEN N'That table was just taken on another device.'
                                   ELSE ERROR_MESSAGE() END;
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END
GO

/*---- 3.11 split: move chosen quantities to a NEW bill on the same table -------
  A whole line moves with its extras/choices (ParentOrderID). A part quantity
  is split off into a copied line; that is only allowed on a line without
  children, because an extra's quantity cannot be divided sensibly.
  Refused once money has been taken on the bill - re-allocating a payment is a
  refund conversation, not a split.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_SplitInvoice') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_SplitInvoice;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_SplitInvoice
      @InvoiceNo  BIGINT
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Lines      dbo.TVP_POS_DineInSplitLine READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Today DATE = CAST(GETDATE() AS DATE)
          , @Err NVARCHAR(300), @Status INT, @BranchID INT, @NewNo BIGINT, @Running INT
          , @Paid DECIMAL(18,3), @Remaining INT, @Discount DECIMAL(18,3)
          , @BillOld DECIMAL(18,3), @BillNew DECIMAL(18,3);

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted, 0) = 0;

    -- what is asked for, against what is there (parent item lines only)
    DECLARE @req TABLE (OrderID BIGINT PRIMARY KEY, MoveQty INT, LineQty INT, HasKids BIT);
    INSERT INTO @req (OrderID, MoveQty, LineQty, HasKids)
    SELECT o.OrderID, l.Quantity, o.Quantity,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.tblOrder k WHERE k.ParentOrderID = o.OrderID AND ISNULL(k.Deleted, 0) = 0)
                THEN 1 ELSE 0 END
    FROM   @Lines l
    JOIN   dbo.tblOrder o ON o.OrderID = l.OrderID AND o.InvoiceNo = @InvoiceNo
                         AND ISNULL(o.Deleted, 0) = 0 AND ISNULL(o.LineType, 1) = 1
    WHERE  l.Quantity > 0;

    UPDATE @req SET MoveQty = LineQty WHERE MoveQty > LineQty;

    SELECT @Remaining = ISNULL(SUM(o.Quantity), 0)
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0 AND ISNULL(o.LineType, 1) = 1;
    SET @Remaining = @Remaining - ISNULL((SELECT SUM(MoveQty) FROM @req), 0);

    IF @Status IS NULL                      SET @Err = N'Bill not found.';
    ELSE IF @Status IN (6, 7, 8)            SET @Err = N'This bill is cancelled or refunded.';
    ELSE IF @Paid > 0                       SET @Err = N'This bill already has a payment on it and cannot be split.';
    ELSE IF NOT EXISTS (SELECT 1 FROM @req) SET @Err = N'Choose at least one item to move.';
    ELSE IF @Remaining <= 0                 SET @Err = N'Leave at least one item on the original bill.';
    ELSE IF EXISTS (SELECT 1 FROM @req WHERE HasKids = 1 AND MoveQty < LineQty)
        SET @Err = N'An item with extras can only be moved whole.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err, NewInvoiceNo = CAST(NULL AS BIGINT); RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        /* new running number for the day, same counter sp_POS_ProcessOrder uses */
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @Running = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;
        IF @Running IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @Running = 1;
        END

        /* header copied from the original */
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate, TableID, TableSessionID
        )
        SELECT  ISNULL(@UserID, i.WaiterID), 0, 0, N'Split from bill ' + CAST(i.InvoiceNo AS NVARCHAR(20)), 1, i.Status
              , @Now, @Now, i.PaymentType, 0, i.Mobile, i.MobileText
              , i.CustomerName, i.OrderStatus, i.CustomerId, i.OrderStatusID, 0
              , i.BranchID, i.AddressID, i.BrandID, i.DeliveryDate, i.InvoiceType
              , 0, 0, i.OrderType, NULL
              , NULL, NULL, i.SourceID, @Running
              , i.PromisedTime, 0, NULL, i.TableID, i.TableSessionID
        FROM    dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

        SET @NewNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        DECLARE @seed BIGINT = @NewNo * 2654435761 % 456976;
        UPDATE dbo.tblInvoice
           SET TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                            + CHAR(65 + (@seed/26)%26)    + CHAR(65 + @seed%26)
                            + '-' + RIGHT('0000' + CAST(@NewNo % 10000 AS VARCHAR(4)), 4)
         WHERE InvoiceNo = @NewNo;

        /* whole lines (and their children) move */
        UPDATE o SET o.InvoiceNo = @NewNo
        FROM   dbo.tblOrder o
        JOIN   @req r ON r.MoveQty = r.LineQty AND (o.OrderID = r.OrderID OR o.ParentOrderID = r.OrderID)
        WHERE  ISNULL(o.Deleted, 0) = 0;

        /* part quantities: copy the line with the moved quantity, reduce the original */
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @NewNo, o.ItemID, r.MoveQty, o.Price, o.SentToPrinter, o.Comments, o.Extra
             , o.WaiterID, o.Prepared, o.Combined, o.Delivered, o.Dispatcher, 0
             , o.OrderDate, o.TableType, 0, o.DiscountTypeID, 0, o.BranchID
             , o.CartItemUniqID, o.LineType, o.ItemNameSnapshot
        FROM   dbo.tblOrder o
        JOIN   @req r ON r.OrderID = o.OrderID AND r.MoveQty < r.LineQty;

        UPDATE o SET o.Quantity = o.Quantity - r.MoveQty
        FROM   dbo.tblOrder o
        JOIN   @req r ON r.OrderID = o.OrderID AND r.MoveQty < r.LineQty;

        /* re-total both */
        SELECT @BillOld = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;
        SELECT @BillNew = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @NewNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @BillOld
             , Discount   = CASE WHEN @Discount > @BillOld THEN @BillOld ELSE @Discount END
             , ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;
        UPDATE dbo.tblInvoice SET BillAmount = @BillNew WHERE InvoiceNo = @NewNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        SELECT @NewNo, NULL, OrderStatusID, @UserID, @UserName, N'Split from bill ' + CAST(@InvoiceNo AS NVARCHAR(20))
        FROM   dbo.tblInvoice WHERE InvoiceNo = @NewNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInSplit', @UserID, @UserName,
                CONCAT(N'NewInvoice=', @NewNo, N'; OldBill=', @BillOld, N'; NewBill=', @BillNew));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(), NewInvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300)), NewInvoiceNo = @NewNo
         , OldBill = @BillOld, NewBill = @BillNew;
END
GO

/*---- 3.12 admin layout save --------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_SaveLayout') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_SaveLayout;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_SaveLayout
      @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Positions  dbo.TVP_POS_TablePosition READONLY
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE t
       SET t.Xaxis = CASE WHEN p.Xaxis < 0 THEN 0 ELSE p.Xaxis END
         , t.Yaxis = CASE WHEN p.Yaxis < 0 THEN 0 ELSE p.Yaxis END
    FROM   dbo.tblTable t
    JOIN   @Positions p ON p.TableID = t.TableID;

    DECLARE @n INT = @@ROWCOUNT;

    INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
    VALUES ('Table', NULL, 'DineInLayout', @UserID, @UserName, CONCAT(N'TablesMoved=', @n));

    SELECT Message = 'Success', Updated = @n;
END
GO

/*---- 3.13 menu for the order popup -------------------------------------------
  Built dynamically so it runs against any install: the optional columns
  (Deleted, IsActive, BrandID, sequence) are only used where they exist.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_GetMenu') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_GetMenu;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_GetMenu
    @BrandID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @catWhere NVARCHAR(MAX) = N'1 = 1', @itemWhere NVARCHAR(MAX) = N'ISNULL(i.PRICE, 0) > 0'
          , @catOrder NVARCHAR(200) = N'c.CAT_NAME', @itemOrder NVARCHAR(200) = N'i.ITEM_NAME'
          , @catAr NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))'
          , @itemAr NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))'
          , @sql NVARCHAR(MAX);

    IF COL_LENGTH('dbo.tblCategory', 'Deleted')  IS NOT NULL SET @catWhere += N' AND ISNULL(c.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblCategory', 'IsActive') IS NOT NULL SET @catWhere += N' AND ISNULL(c.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblCategory', 'SEQ_NUM')  IS NOT NULL SET @catOrder  = N'ISNULL(c.SEQ_NUM, 9999), c.CAT_NAME';
    IF COL_LENGTH('dbo.tblCategory', 'CAT_NAME_ARABIC') IS NOT NULL SET @catAr = N'c.CAT_NAME_ARABIC';

    IF @BrandID > 0 AND COL_LENGTH('dbo.tblCategory', 'BrandID') IS NOT NULL
    BEGIN
        DECLARE @hasBrand BIT = 0;
        EXEC sp_executesql N'IF EXISTS (SELECT 1 FROM dbo.tblCategory WHERE BrandID = @b) SET @h = 1;',
             N'@b INT, @h BIT OUTPUT', @b = @BrandID, @h = @hasBrand OUTPUT;
        IF @hasBrand = 1 SET @catWhere += N' AND c.BrandID = @BrandID';
    END

    IF COL_LENGTH('dbo.tblItems', 'Deleted')  IS NOT NULL SET @itemWhere += N' AND ISNULL(i.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblItems', 'IsActive') IS NOT NULL SET @itemWhere += N' AND ISNULL(i.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblItems', 'ITEM_NAME_ARABIC') IS NOT NULL SET @itemAr = N'i.ITEM_NAME_ARABIC';
    IF COL_LENGTH('dbo.tblItems', 'Seq_No') IS NOT NULL       SET @itemOrder = N'ISNULL(i.Seq_No, 9999), i.ITEM_NAME';
    ELSE IF COL_LENGTH('dbo.tblItems', 'SEQ_NUM') IS NOT NULL SET @itemOrder = N'ISNULL(i.SEQ_NUM, 9999), i.ITEM_NAME';

    SET @sql = N'
        SELECT  c.CAT_NUM, c.CAT_NAME, CAT_NAME_ARABIC = ' + @catAr + N'
              , CatSeq = ROW_NUMBER() OVER (ORDER BY ' + @catOrder + N')
        INTO    #cats
        FROM    dbo.tblCategory c
        WHERE   ' + @catWhere + N';

        SELECT  ItemID = i.ID, i.CAT_NUM, i.ITEM_NAME, ITEM_NAME_ARABIC = ' + @itemAr + N'
              , PRICE = CAST(i.PRICE AS DECIMAL(18,3)), RowSeq = ROW_NUMBER() OVER (ORDER BY ' + @itemOrder + N')
        INTO    #items
        FROM    dbo.tblItems i
        WHERE   ' + @itemWhere + N' AND i.CAT_NUM IN (SELECT CAT_NUM FROM #cats);

        SELECT  c.CAT_NUM, c.CAT_NAME, c.CAT_NAME_ARABIC, ItemCount = COUNT(*)
        FROM    #cats c JOIN #items i ON i.CAT_NUM = c.CAT_NUM
        GROUP BY c.CAT_NUM, c.CAT_NAME, c.CAT_NAME_ARABIC
        ORDER BY MIN(c.CatSeq);

        SELECT ItemID, CAT_NUM, ITEM_NAME, ITEM_NAME_ARABIC, PRICE FROM #items ORDER BY RowSeq;';

    EXEC sp_executesql @sql, N'@BrandID INT', @BrandID = @BrandID;
END
GO

PRINT 'POS_35_DineIn.sql complete.';
GO
