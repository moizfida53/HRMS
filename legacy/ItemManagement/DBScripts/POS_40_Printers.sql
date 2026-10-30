/*********************************************************************************
  POS_40_Printers.sql  -  Printer Settings + silent LAN printing

  Tables
    tblPOS_Printer          one row per network printer of a branch
    tblPOS_PrinterCategory  the categories a printer's ORDER tickets are limited to
                            (only read when AllCategories = 0)
  Procedures
    sp_POS_Printer_List     printers + their categories + the category list
    sp_POS_Printer_Save     add / update
    sp_POS_Printer_Delete   soft delete
    sp_POS_Print_Ticket     header + lines of one invoice, each line with its category
    sp_POS_Print_MarkSent   flags order lines as sent to the kitchen printers

  Also: tblOrder.SentToPrinter already exists - an ORDER print sends only the lines
  where it is 0, then sets it to 1, so adding items to a table prints just the new
  items. Safe to re-run.
**********************************************************************************/
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.tblPOS_Printer') IS NULL
CREATE TABLE dbo.tblPOS_Printer
(
      PrinterID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tblPOS_Printer PRIMARY KEY
    , BranchID      INT           NOT NULL
    , PrinterName   NVARCHAR(100) NOT NULL
    , IPAddress     VARCHAR(45)   NOT NULL
    , Port          INT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Port DEFAULT (9100)
    , PaperWidthMM  INT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Paper DEFAULT (80)
    , PrintInvoice  BIT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Inv DEFAULT (0)
    , PrintOrder    BIT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Ord DEFAULT (0)
    , AllCategories BIT           NOT NULL CONSTRAINT DF_tblPOS_Printer_All DEFAULT (1)
    , IsActive      BIT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Act DEFAULT (1)
    , IsDeleted     BIT           NOT NULL CONSTRAINT DF_tblPOS_Printer_Del DEFAULT (0)
    , CreatedOn     DATETIME      NOT NULL CONSTRAINT DF_tblPOS_Printer_Cr  DEFAULT (GETDATE())
    , CreatedBy     INT           NULL
    , ModifiedOn    DATETIME      NULL
    , ModifiedBy    INT           NULL
);
GO
IF OBJECT_ID('dbo.tblPOS_PrinterCategory') IS NULL
CREATE TABLE dbo.tblPOS_PrinterCategory
(
      PrinterID INT NOT NULL
    , CAT_NUM   INT NOT NULL
    , CONSTRAINT PK_tblPOS_PrinterCategory PRIMARY KEY (PrinterID, CAT_NUM)
);
GO

/*---- list -------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_Printer_List') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Printer_List;
GO
CREATE PROCEDURE dbo.sp_POS_Printer_List
      @BranchID INT
    , @BrandID  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.PrinterID, p.BranchID, p.PrinterName, p.IPAddress, p.Port, p.PaperWidthMM
         , p.PrintInvoice, p.PrintOrder, p.AllCategories, p.IsActive
    FROM   dbo.tblPOS_Printer p
    WHERE  p.IsDeleted = 0 AND p.BranchID = @BranchID
    ORDER BY p.PrinterName, p.PrinterID;

    SELECT pc.PrinterID, pc.CAT_NUM
    FROM   dbo.tblPOS_PrinterCategory pc
    JOIN   dbo.tblPOS_Printer p ON p.PrinterID = pc.PrinterID
    WHERE  p.IsDeleted = 0 AND p.BranchID = @BranchID;

    DECLARE @where NVARCHAR(MAX) = N'1 = 1', @ar NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))', @sql NVARCHAR(MAX);
    IF COL_LENGTH('dbo.tblCategory', 'Deleted')  IS NOT NULL SET @where += N' AND ISNULL(c.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblCategory', 'IsActive') IS NOT NULL SET @where += N' AND ISNULL(c.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblCategory', 'CAT_NAME_ARABIC') IS NOT NULL SET @ar = N'c.CAT_NAME_ARABIC';
    IF @BrandID > 0 AND COL_LENGTH('dbo.tblCategory', 'BrandID') IS NOT NULL
        SET @where += N' AND (c.BrandID = @BrandID OR NOT EXISTS (SELECT 1 FROM dbo.tblCategory x WHERE x.BrandID = @BrandID))';
    SET @sql = N'SELECT CAT_NUM = TRY_CAST(c.CAT_NUM AS INT), c.CAT_NAME, CAT_NAME_ARABIC = ' + @ar +
               N' FROM dbo.tblCategory c WHERE ' + @where + N' AND TRY_CAST(c.CAT_NUM AS INT) IS NOT NULL ORDER BY c.CAT_NAME;';
    EXEC sp_executesql @sql, N'@BrandID INT', @BrandID = @BrandID;
END
GO

/*---- save -------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_Printer_Save') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Printer_Save;
GO
CREATE PROCEDURE dbo.sp_POS_Printer_Save
      @PrinterID     INT           = 0
    , @BranchID      INT
    , @PrinterName   NVARCHAR(100)
    , @IPAddress     VARCHAR(45)
    , @Port          INT           = 9100
    , @PaperWidthMM  INT           = 80
    , @PrintInvoice  BIT
    , @PrintOrder    BIT
    , @AllCategories BIT           = 1
    , @CategoryIDs   VARCHAR(MAX)  = NULL      -- '3,5,9'
    , @IsActive      BIT           = 1
    , @UserID        INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Err NVARCHAR(300);

    SET @PrinterName = LTRIM(RTRIM(ISNULL(@PrinterName, N'')));
    SET @IPAddress   = LTRIM(RTRIM(ISNULL(@IPAddress, '')));
    IF @PrinterName = N'' SET @Err = N'Enter the printer name.';
    ELSE IF @IPAddress = '' SET @Err = N'Enter the printer IP address.';
    ELSE IF @Port NOT BETWEEN 1 AND 65535 SET @Err = N'The port must be between 1 and 65535.';
    ELSE IF ISNULL(@PrintInvoice, 0) = 0 AND ISNULL(@PrintOrder, 0) = 0 SET @Err = N'Tick Print Invoice, Print Order, or both.';
    ELSE IF @PrinterID > 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Printer WHERE PrinterID = @PrinterID AND IsDeleted = 0 AND BranchID = @BranchID)
        SET @Err = N'That printer no longer exists.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblPOS_Printer WHERE IsDeleted = 0 AND BranchID = @BranchID
                    AND PrinterName = @PrinterName AND PrinterID <> ISNULL(@PrinterID, 0))
        SET @Err = N'A printer with that name already exists in this branch.';

    IF @Err IS NOT NULL BEGIN SELECT Message = 'Fail', ErrorMessage = @Err; RETURN; END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF ISNULL(@PrinterID, 0) = 0
        BEGIN
            INSERT dbo.tblPOS_Printer (BranchID, PrinterName, IPAddress, Port, PaperWidthMM, PrintInvoice, PrintOrder, AllCategories, IsActive, CreatedBy)
            VALUES (@BranchID, @PrinterName, @IPAddress, @Port, @PaperWidthMM, @PrintInvoice, @PrintOrder, @AllCategories, @IsActive, @UserID);
            SET @PrinterID = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE dbo.tblPOS_Printer
               SET PrinterName = @PrinterName, IPAddress = @IPAddress, Port = @Port, PaperWidthMM = @PaperWidthMM
                 , PrintInvoice = @PrintInvoice, PrintOrder = @PrintOrder, AllCategories = @AllCategories
                 , IsActive = @IsActive, ModifiedOn = GETDATE(), ModifiedBy = @UserID
             WHERE PrinterID = @PrinterID;

        DELETE dbo.tblPOS_PrinterCategory WHERE PrinterID = @PrinterID;
        IF @PrintOrder = 1 AND @AllCategories = 0 AND NULLIF(@CategoryIDs, '') IS NOT NULL
            INSERT dbo.tblPOS_PrinterCategory (PrinterID, CAT_NUM)
            SELECT DISTINCT @PrinterID, TRY_CAST(LTRIM(RTRIM(value)) AS INT)
            FROM   STRING_SPLIT(@CategoryIDs, ',')
            WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

        -- "Select categories" with nothing selected would print nothing: treat as All.
        IF @PrintOrder = 1 AND @AllCategories = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_PrinterCategory WHERE PrinterID = @PrinterID)
            UPDATE dbo.tblPOS_Printer SET AllCategories = 1 WHERE PrinterID = @PrinterID;

        COMMIT TRANSACTION;
        SELECT Message = 'Success', PrinterID = @PrinterID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
    END CATCH
END
GO

/*---- delete -----------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_Printer_Delete') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Printer_Delete;
GO
CREATE PROCEDURE dbo.sp_POS_Printer_Delete
      @PrinterID INT, @BranchID INT, @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.tblPOS_Printer SET IsDeleted = 1, ModifiedOn = GETDATE(), ModifiedBy = @UserID
     WHERE PrinterID = @PrinterID AND BranchID = @BranchID AND IsDeleted = 0;
    SELECT Message = CASE WHEN @@ROWCOUNT > 0 THEN 'Success' ELSE 'Fail' END;
END
GO

/*---- the data one ticket is drawn from -------------------------------------
  Result sets
    0  header (one row)
    1  lines  (OrderID, ParentOrderID, CAT_NUM, names, qty, price, total, note,
              SentToPrinter)  - deleted and split-away lines are never returned
    2  payments
  @OnlyUnsent = 1 limits the lines to SentToPrinter = 0 (kitchen tickets).
  @OrderIDs (CSV) limits them to those rows and their extras.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_Print_Ticket') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Print_Ticket;
GO
CREATE PROCEDURE dbo.sp_POS_Print_Ticket
      @InvoiceNo  BIGINT
    , @OnlyUnsent BIT = 0
    , @OrderIDs   VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ar NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))', @sql NVARCHAR(MAX);
    DECLARE @Split NVARCHAR(100) = CASE WHEN COL_LENGTH('dbo.tblOrder', 'IsSplit') IS NOT NULL THEN N' AND ISNULL(o.IsSplit, 0) = 0' ELSE N'' END;
    IF COL_LENGTH('dbo.tblItems', 'ITEM_NAME_ARABIC') IS NOT NULL SET @ar = N'it.ITEM_NAME_ARABIC';

    -- 0 header
    SELECT  i.InvoiceNo
          , InvoiceNumShow = ISNULL(NULLIF(CAST(i.InvoiceNumShow AS NVARCHAR(50)), N''), CAST(i.InvoiceNo AS NVARCHAR(50)))
          , i.RunningOrder
          , i.InvoiceDate
          , i.CustomerName
          , i.Mobile
          , BillAmount = CAST(i.BillAmount AS DECIMAL(18,3))
          , Discount   = CAST(ISNULL(i.Discount, 0) AS DECIMAL(18,3))
          , NetPayable = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges, 0) AS DECIMAL(18,3))
          , TableNo    = LTRIM(RTRIM(CAST(t.Table_No AS NVARCHAR(30))))
          , BranchName = b.branchName
          , BranchID   = ISNULL((SELECT TOP 1 o.BranchID FROM dbo.tblOrder o WHERE o.InvoiceNo = i.InvoiceNo), 0)
    FROM    dbo.tblInvoice i
    LEFT JOIN dbo.tblTable t ON t.TableID = i.TableID
    LEFT JOIN dbo.tblbranch b ON b.id = (SELECT TOP 1 o.BranchID FROM dbo.tblOrder o WHERE o.InvoiceNo = i.InvoiceNo)
    WHERE   i.InvoiceNo = @InvoiceNo;

    -- 1 lines
    SET @sql = N'
    SELECT  o.OrderID, o.ParentOrderID
          , CAT_NUM = TRY_CAST(it.CAT_NUM AS INT)
          , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , ItemNameAra = ' + @ar + N'
          , o.Quantity
          , Price     = CAST(o.Price AS DECIMAL(18,3))
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , Note      = o.Comments
          , SentToPrinter = CAST(ISNULL(o.SentToPrinter, 0) AS BIT)
    FROM    dbo.tblOrder o
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0' + @Split + N'
      AND   (@OnlyUnsent = 0 OR ISNULL(o.SentToPrinter, 0) = 0)
      AND   (@OrderIDs IS NULL OR o.OrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, '','')
                                              )
                              OR o.ParentOrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, '','')))
    ORDER BY ISNULL(o.ParentOrderID, o.OrderID), CASE WHEN o.ParentOrderID IS NULL THEN 0 ELSE 1 END, o.OrderID;';
    EXEC sp_executesql @sql, N'@InvoiceNo BIGINT, @OnlyUnsent BIT, @OrderIDs VARCHAR(MAX)'
                      , @InvoiceNo = @InvoiceNo, @OnlyUnsent = @OnlyUnsent, @OrderIDs = @OrderIDs;

    -- 2 payments
    SELECT  PaymentType = p.PaymentType
          , Amount      = CAST(p.AmountTendered AS DECIMAL(18,3))
          , Applied     = CAST(p.Amount AS DECIMAL(18,3))
          , ChangeGiven = CAST(ISNULL(p.ChangeGiven, 0) AS DECIMAL(18,3))
    FROM    dbo.tblInvoicePayment p
    WHERE   p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted, 0) = 0 AND ISNULL(p.IsRefund, 0) = 0
    ORDER BY p.ReceivedOn;
END
GO

/*---- sent-to-kitchen flag ---------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_Print_MarkSent') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Print_MarkSent;
GO
CREATE PROCEDURE dbo.sp_POS_Print_MarkSent
      @InvoiceNo BIGINT, @OrderIDs VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE o SET SentToPrinter = 1
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo
      AND (o.OrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, ','))
        OR o.ParentOrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, ',')));
    SELECT Message = 'Success', Marked = @@ROWCOUNT;
END
GO

PRINT 'POS_40_Printers.sql complete.';
GO
