/**********************************************************************************
  POS_25_SortDiagnostic.sql
  ------------------------------------------------------------------------------
  "DataTables warning: table id=posOrders - Query failed."

  That warning is the text OrdersController.List returns from its catch block.
  It is the SAME text for every possible cause - a bad ORDER BY, a missing
  procedure, a permission error - so it says nothing about what actually went
  wrong. This script calls sp_POS_GetOrders once for every column the grid can
  sort by, catches each failure, and prints the real SQL Server message.

  Run it in SSMS against Pistachio_v4 with results-to-text and read SECTION 3.
  Nothing here changes any object; it only reads and reports.

  SECTION 1 answers the first question: is POS_24 actually applied? If it is
  not, sorting by Invoice No fails with Msg 169 and everything else works. If it
  is applied and columns still fail, SECTION 3 names them and says why.
**********************************************************************************/

SET NOCOUNT ON;
GO

/*==============================================================================
  SECTION 1 - which version of the procedure is installed
==============================================================================*/
PRINT '===== SECTION 1 : installed procedure =====';

IF OBJECT_ID('dbo.sp_POS_GetOrders') IS NULL
    PRINT '  sp_POS_GetOrders : MISSING - nothing can sort. Run POS_12 then POS_24.';
ELSE
BEGIN
    DECLARE @body NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_POS_GetOrders'));

    PRINT '  sp_POS_GetOrders : present';

    IF @body LIKE '%@SortExpr%'
        PRINT '  POS_24  : APPLIED   (tiebreaker is conditional)';
    ELSE
        PRINT '  POS_24  : NOT APPLIED  <-- sorting by Invoice No will fail with Msg 169';

    -- The exact fault POS_24 removes: the tiebreaker appended unconditionally.
    IF @body LIKE '%+ '', i.InvoiceNo DESC''%' AND @body NOT LIKE '%@SortExpr%'
        PRINT '  Found the unconditional '', i.InvoiceNo DESC'' tiebreaker.';

    SELECT ModifiedOn = modify_date, CreatedOn = create_date
    FROM   sys.objects WHERE object_id = OBJECT_ID('dbo.sp_POS_GetOrders');
END
GO


/*==============================================================================
  SECTION 2 - the columns the grid sends

  These are the DataTables column keys from Areas/POS/Scripts/pos.orders.js, in
  screen order. The browser sends the key, not the underlying column name.
==============================================================================*/
IF OBJECT_ID('tempdb..#cols') IS NOT NULL DROP TABLE #cols;
CREATE TABLE #cols (Seq INT IDENTITY(1,1), SortCol VARCHAR(30));

INSERT INTO #cols (SortCol) VALUES
      ('InvoiceNo')        -- column 0, the one first reported
    , ('InvoiceTypeName')
    , ('CustomerName')
    , ('Mobile')
    , ('AreaName')
    , ('DeliveryDate')     -- column 5, the grid's default sort
    , ('Amount')
    , ('DriverName')
    , ('BrandName')
    , ('BranchName')
    , ('OrderStatusName');
GO


/*==============================================================================
  SECTION 3 - call the procedure once per column, both directions

  Each call is wrapped in TRY/CATCH, so one failure does not stop the sweep and
  every column gets a verdict. @Take = 1 keeps it fast; a sort that is going to
  fail fails while building the statement, before it reads any rows.
==============================================================================*/
PRINT '';
PRINT '===== SECTION 3 : sort sweep =====';

IF OBJECT_ID('tempdb..#result') IS NOT NULL DROP TABLE #result;
CREATE TABLE #result
(
      SortCol   VARCHAR(30)
    , SortDir   VARCHAR(4)
    , Verdict   VARCHAR(10)
    , ErrNumber INT           NULL
    , ErrMsg    NVARCHAR(2000) NULL
);

DECLARE @c VARCHAR(30), @i INT = 1, @n INT = (SELECT MAX(Seq) FROM #cols);

WHILE @i <= @n
BEGIN
    SELECT @c = SortCol FROM #cols WHERE Seq = @i;

    -- Ascending. A sort that is going to fail fails while the statement is
    -- being built, before it reads a single row, so @Take = 1 is enough.
    BEGIN TRY
        EXEC dbo.sp_POS_GetOrders @DateMode = 'All', @Take = 1,
                                  @SortCol = @c, @SortDir = 'asc';
        INSERT INTO #result (SortCol, SortDir, Verdict) VALUES (@c, 'asc', 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO #result (SortCol, SortDir, Verdict, ErrNumber, ErrMsg)
        VALUES (@c, 'asc', 'FAILED', ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH

    -- Descending. Both directions are tried because the tiebreaker is appended
    -- with a fixed DESC, so a duplicate-column error can appear in one
    -- direction and not the other.
    BEGIN TRY
        EXEC dbo.sp_POS_GetOrders @DateMode = 'All', @Take = 1,
                                  @SortCol = @c, @SortDir = 'desc';
        INSERT INTO #result (SortCol, SortDir, Verdict) VALUES (@c, 'desc', 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO #result (SortCol, SortDir, Verdict, ErrNumber, ErrMsg)
        VALUES (@c, 'desc', 'FAILED', ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH

    SET @i = @i + 1;
END
GO

PRINT '';
PRINT '--- failures only (this is the answer) ---';
SELECT SortCol, SortDir, ErrNumber, ErrMsg
FROM   #result WHERE Verdict = 'FAILED'
ORDER BY SortCol, SortDir;

PRINT '';
PRINT '--- every column ---';
SELECT SortCol, SortDir, Verdict, ErrNumber, ErrMsg FROM #result ORDER BY SortCol, SortDir;

PRINT '';
SELECT Failures = COUNT(*) FROM #result WHERE Verdict = 'FAILED';
GO

/*==============================================================================
  READING THE RESULT

  No failures
      The procedure is fine and the fault is above it - in the controller or in
      what the browser sends. The grid now appends the real message to the
      DataTables warning when custom errors are off (Web.config), so reload the
      Order List and read the text after "Query failed."

  Only InvoiceNo fails, Msg 169
      POS_24 has not been run. Run it.

  Everything fails
      Read the message. An "Invalid column name" points at a column the
      procedure references that this database does not have; "Invalid object
      name" at a missing table or type (TVP_POS_IntList lives in POS_01).
==============================================================================*/
