/**********************************************************************************
  POS_00_DumpSchema.sql
  ------------------------------------------------------------------------------
  PURPOSE : Dump the schema of tblInvoice, tblOrder and every related lookup
            table so the POS insert stored procedures can be written against the
            REAL columns instead of guesses.

  HOW TO RUN (pick one)
  ---------------------------------------------------------------------------
  OPTION A - SSMS (easiest)
      1. Open SSMS, connect to  .\TMM  , select database  Pistachio_v4
      2. Open this file, press  Ctrl+T   (Results To Text)
      3. Press  F5
      4. Ctrl+A in the results pane, Ctrl+C
      5. Save as:
         D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project\DBScripts\SchemaDump.txt

  OPTION B - sqlcmd (one line, no copy/paste)
      Open cmd.exe and run:

      sqlcmd -S .\TMM -d Pistachio_v4 -U sa -P "f$97227330" -i "D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project\DBScripts\POS_00_DumpSchema.sql" -o "D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project\DBScripts\SchemaDump.txt" -W -s"|" -y0 -Y0

  Either way the output file lands in DBScripts\ which is already shared with
  this session, so it can be read directly - nothing to paste into chat.
**********************************************************************************/

SET NOCOUNT ON;

/*---------------------------------------------------------------------------
  1. Which of the tables we care about actually exist?
---------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
CREATE TABLE #T (TableName SYSNAME PRIMARY KEY);

INSERT INTO #T (TableName)
SELECT name
FROM   sys.tables
WHERE  name IN
       (
            'tblInvoice','tblOrder','tblInvoiceDetails','tblOrderDetails',
            'tblInvoiceType_Master','tblInvoicePaymentType','tblPaymentType',
            'tblInvoiceStatus','tblOrderStatus','tblOrderStatus_Master',
            'tblCustomer','tblCustomers','tblCustomerAddress','tblAddress',
            'tblArea','tblGovernorate','tblCity','tblBlock',
            'tblBranch','tblBranchMaster','tblBrand','tblBrandMaster',
            'tblItem','tblItems','tblItemMaster','tblExtra','tblChoice',
            'tblDriver','tblDeliveryService','tblUser','tblUsers','tblUserRole',
            'tblWaiter','tblDiscount','tblDiscountType','tblCoupon',
            'tblInvoicePayment','tblPayment','tblTax','tblCurrency'
       )
   -- catch-all: anything that looks invoice / order related
   OR name LIKE 'tblInvoice%'
   OR name LIKE 'tblOrder%';

/*---------------------------------------------------------------------------
  2. Column definitions
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 1 : COLUMNS ################';
PRINT '';

SELECT
      t.name                                                AS TableName
    , c.column_id                                           AS Ord
    , c.name                                                AS ColumnName
    , ty.name                                               AS DataType
    , CASE
        WHEN ty.name IN ('nvarchar','nchar')
             THEN CASE WHEN c.max_length = -1 THEN 'max'
                       ELSE CAST(c.max_length/2 AS VARCHAR(10)) END
        WHEN ty.name IN ('varchar','char','varbinary','binary')
             THEN CASE WHEN c.max_length = -1 THEN 'max'
                       ELSE CAST(c.max_length AS VARCHAR(10)) END
        WHEN ty.name IN ('decimal','numeric')
             THEN CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10))
        ELSE ''
      END                                                   AS Len
    , CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END AS Nullable
    , CASE WHEN c.is_identity = 1 THEN 'IDENTITY' ELSE '' END     AS Ident
    , CASE WHEN c.is_computed = 1 THEN 'COMPUTED' ELSE '' END     AS Computed
    , ISNULL(dc.definition,'')                              AS DefaultValue
FROM        sys.tables         t
JOIN        #T                 f  ON f.TableName = t.name
JOIN        sys.columns        c  ON c.object_id = t.object_id
JOIN        sys.types          ty ON ty.user_type_id = c.user_type_id
LEFT JOIN   sys.default_constraints dc ON dc.object_id = c.default_object_id
ORDER BY    t.name, c.column_id;

/*---------------------------------------------------------------------------
  3. Primary keys / unique constraints
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 2 : KEYS ################';
PRINT '';

SELECT
      t.name          AS TableName
    , i.name          AS IndexName
    , CASE WHEN i.is_primary_key = 1 THEN 'PK'
           WHEN i.is_unique_constraint = 1 THEN 'UQ'
           WHEN i.is_unique = 1 THEN 'UQ-IDX' ELSE 'IDX' END AS KeyType
    , STUFF((SELECT ', ' + c2.name
             FROM   sys.index_columns ic2
             JOIN   sys.columns c2 ON c2.object_id = ic2.object_id
                                  AND c2.column_id = ic2.column_id
             WHERE  ic2.object_id = i.object_id
               AND  ic2.index_id  = i.index_id
               AND  ic2.is_included_column = 0
             ORDER BY ic2.key_ordinal
             FOR XML PATH('')),1,2,'')                       AS KeyColumns
FROM      sys.indexes i
JOIN      sys.tables  t ON t.object_id = i.object_id
JOIN      #T          f ON f.TableName = t.name
WHERE     i.type > 0
ORDER BY  t.name, KeyType, i.name;

/*---------------------------------------------------------------------------
  4. Foreign keys (both directions)
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 3 : FOREIGN KEYS ################';
PRINT '';

SELECT
      fk.name                    AS FKName
    , pt.name                    AS ParentTable
    , pc.name                    AS ParentColumn
    , rt.name                    AS RefTable
    , rc.name                    AS RefColumn
FROM      sys.foreign_keys fk
JOIN      sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN      sys.tables  pt ON pt.object_id = fk.parent_object_id
JOIN      sys.columns pc ON pc.object_id = fkc.parent_object_id
                        AND pc.column_id = fkc.parent_column_id
JOIN      sys.tables  rt ON rt.object_id = fk.referenced_object_id
JOIN      sys.columns rc ON rc.object_id = fkc.referenced_object_id
                        AND rc.column_id = fkc.referenced_column_id
WHERE     pt.name IN (SELECT TableName FROM #T)
       OR rt.name IN (SELECT TableName FROM #T)
ORDER BY  pt.name, fk.name;

/*---------------------------------------------------------------------------
  5. Row counts (tells us what is actually in use)
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 4 : ROW COUNTS ################';
PRINT '';

SELECT   t.name AS TableName, SUM(p.rows) AS ApproxRows
FROM     sys.tables t
JOIN     #T f ON f.TableName = t.name
JOIN     sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name
ORDER BY t.name;

/*---------------------------------------------------------------------------
  6. Lookup table CONTENTS - status / payment / invoice type codes.
     These drive the POS status buttons, so the real IDs are needed.
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 5 : LOOKUP CONTENTS ################';
PRINT '';

DECLARE @tbl SYSNAME, @sql NVARCHAR(MAX);
DECLARE lk CURSOR LOCAL FAST_FORWARD FOR
    SELECT TableName FROM #T
    WHERE  TableName LIKE '%Type%'
        OR TableName LIKE '%Status%'
        OR TableName LIKE '%Master%';
OPEN lk;
FETCH NEXT FROM lk INTO @tbl;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '----- ' + @tbl + ' -----';
    SET @sql = N'SELECT TOP 100 * FROM dbo.' + QUOTENAME(@tbl) + N';';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH PRINT '  (could not read: ' + ERROR_MESSAGE() + ')'; END CATCH
    FETCH NEXT FROM lk INTO @tbl;
END
CLOSE lk; DEALLOCATE lk;

/*---------------------------------------------------------------------------
  7. Existing stored procedures that already touch tblInvoice / tblOrder.
     If the call-centre app shares this DB there may already be an insert SP
     worth reusing instead of writing a new one.
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 6 : EXISTING PROCS TOUCHING INVOICE/ORDER ################';
PRINT '';

SELECT   o.name AS ProcName, o.type_desc, o.create_date, o.modify_date
FROM     sys.sql_modules m
JOIN     sys.objects o ON o.object_id = m.object_id
WHERE    (m.definition LIKE '%tblInvoice%' OR m.definition LIKE '%tblOrder%')
  AND    o.type IN ('P','FN','TF','IF','V')
ORDER BY o.name;

/*---------------------------------------------------------------------------
  8. Sample rows - shows how the call centre populated the columns.
     >>> Review before sharing: contains real customer names / phone numbers. <<<
---------------------------------------------------------------------------*/
PRINT '';
PRINT '################ SECTION 7 : SAMPLE ROWS (review for PII before sharing) ################';
PRINT '';

IF OBJECT_ID('dbo.tblInvoice') IS NOT NULL
BEGIN
    PRINT '----- tblInvoice TOP 3 -----';
    SELECT TOP 3 * FROM dbo.tblInvoice ORDER BY 1 DESC;
END

IF OBJECT_ID('dbo.tblOrder') IS NOT NULL
BEGIN
    PRINT '----- tblOrder TOP 10 -----';
    SELECT TOP 10 * FROM dbo.tblOrder ORDER BY 1 DESC;
END

DROP TABLE #T;
PRINT '';
PRINT '################ END OF DUMP ################';
