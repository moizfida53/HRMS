/*********************************************************************************
  POS_39_PaymentLegacyColumnFix.sql

  Fixes:  Invalid column name 'Deliveroo Pay'.

  Cause:  sp_POS_TakePaymentSplit (and sp_POS_AddPayment) keep the old per-method
          columns on tblInvoice in step by running
              UPDATE i SET [<LegacyColumn>] = ...
          for every LegacyColumn value in tblInvoicePaymentType. 'Deliveroo Pay'
          (and any other type added since) has a LegacyColumn that is not a real
          column of tblInvoice, so the UPDATE fails and the payment is rolled back.

  Fix:    1. the loop now skips any LegacyColumn that is not a column of tblInvoice
          2. the LegacyColumn of such rows is cleared (nothing reads a column that
             does not exist)
  Safe to re-run.
**********************************************************************************/
SET NOCOUNT ON;
GO

-- 2. data: clear LegacyColumn values that point at nothing
UPDATE dbo.tblInvoicePaymentType
   SET LegacyColumn = NULL
 WHERE LegacyColumn IS NOT NULL
   AND COL_LENGTH('dbo.tblInvoice', LegacyColumn) IS NULL;
PRINT 'LegacyColumn cleared on ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' payment type(s) with no matching tblInvoice column.';
GO

-- 1. procs: guard the cursor
DECLARE @old NVARCHAR(MAX) = N'FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL;'
      , @new NVARCHAR(MAX) = N'FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL AND COL_LENGTH(''dbo.tblInvoice'', LegacyColumn) IS NOT NULL;'
      , @name SYSNAME, @def NVARCHAR(MAX);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT n FROM (VALUES ('sp_POS_TakePaymentSplit'), ('sp_POS_AddPayment')) v(n);
OPEN c; FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID('dbo.' + @name));
    IF @def IS NULL PRINT @name + ' not found - skipped.';
    ELSE IF CHARINDEX(@new, @def) > 0 PRINT @name + ' already patched.';
    ELSE IF CHARINDEX(@old, @def) = 0 PRINT @name + ': expected text not found - not changed.';
    ELSE
    BEGIN
        SET @def = REPLACE(@def, @old, @new);
        SET @def = STUFF(@def, CHARINDEX('CREATE', @def), 6, 'ALTER');   -- first CREATE keyword only
        EXEC sys.sp_executesql @def;
        PRINT @name + ' patched.';
    END
    FETCH NEXT FROM c INTO @name;
END
CLOSE c; DEALLOCATE c;
GO
