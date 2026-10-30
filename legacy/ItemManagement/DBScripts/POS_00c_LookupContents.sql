/**********************************************************************************
  POS_00c_LookupContents.sql   -- run BEFORE POS_03

  The head-office tables you imported may already carry seeded rows with their
  own IDs. POS_03 only seeds tables it finds EMPTY, so the existing IDs win --
  but the C# payment-type mapping has to match whatever is actually in there.
  Save the output as DBScripts\LookupContents.txt

      sqlcmd -S .\TMM -d Pistachio_v4 -U sa -P "f$97227330" ^
        -i "...\DBScripts\POS_00c_LookupContents.sql" ^
        -o "...\DBScripts\LookupContents.txt" -W -s"|" -y0 -Y0
**********************************************************************************/
SET NOCOUNT ON;

PRINT '===== tblOrderStatus =====';
SELECT * FROM dbo.tblOrderStatus;

PRINT '===== tblInvoicePaymentType =====';
SELECT * FROM dbo.tblInvoicePaymentType ORDER BY ID;

PRINT '===== tblInvoiceType_Master =====';
SELECT * FROM dbo.tblInvoiceType_Master ORDER BY ID;

PRINT '===== tblInvoiceType_Master_Details =====';
SELECT * FROM dbo.tblInvoiceType_Master_Details ORDER BY ID;

PRINT '===== tblDiscount_Type =====';
SELECT * FROM dbo.tblDiscount_Type ORDER BY Id;

PRINT '===== tblDiscountCode =====';
SELECT * FROM dbo.tblDiscountCode ORDER BY id;

PRINT '===== TblArea_Mapping (row count + sample) =====';
SELECT COUNT(*) AS MappingRows FROM dbo.TblArea_Mapping;
SELECT TOP 30 m.ID, m.AreaID, a.AreaName, m.BranchID, b.branchName
FROM   dbo.TblArea_Mapping m
LEFT JOIN dbo.tblArea   a ON a.AreaID = m.AreaID
LEFT JOIN dbo.tblbranch b ON b.id     = m.BranchID
ORDER BY m.BranchID, m.AreaID;

PRINT '===== tblDriver =====';
SELECT DriverID, BranchID, DriverName, DriverCode, DriverTel, CompanyName FROM dbo.tblDriver;

PRINT '===== tblTableType / tblPrinter (printer routing) =====';
SELECT * FROM dbo.tblTableType;
SELECT * FROM dbo.tblPrinter;

PRINT '===== tblDenomination =====';
SELECT * FROM dbo.tblDenomination ORDER BY DenominationValue DESC;

PRINT '===== tblUser (roles - passwords masked) =====';
SELECT ID, NAME, USERNAME, BrandID, RoleID FROM dbo.tblUser;

PRINT '===== Row counts of every imported HO table =====';
SELECT t.name AS TableName, SUM(p.rows) AS ApproxRows
FROM   sys.tables t
JOIN   sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE  t.name IN ('TblArea_Mapping','tblAreaMapData','tblDenomination','tblDenominationDetails',
                  'tblDiscount_Type','tblDiscountCode','tblDriver','tblDriverTracking',
                  'tblEndDay','tblEndDayDiscount','tblEndDayPayment','tblEndDayPaymentTypeDetails',
                  'tblEndshiftPaymentTypeDetails','tblInvoicePayment','tblInvoicePaymentType',
                  'tblInvoiceType_Master','tblInvoiceType_Master_Details','tblOrderStatus',
                  'tblPaymentVoucher','tblPaymentVoucherDetails','tblPaymentVoucherType',
                  'tblPrinter','tblTable','tblTableType')
GROUP BY t.name ORDER BY t.name;
