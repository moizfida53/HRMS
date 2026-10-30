/* ============================================================================
   MenuTheme_Diagnostic.sql  -  READ-ONLY. Does not change any data.
   ----------------------------------------------------------------------------
   Run this in SSMS against your database and send back everything it prints -
   this tells us whether the objects the app expects (tblMenuTheme,
   dbo.MenuThemeTVP, sp_GetMenuTheme, sp_SaveMenuTheme) actually exist and
   match what the code expects, and whether Save is really reaching the DB.
   ============================================================================ */

SET NOCOUNT ON;

PRINT '--- 1) Does dbo.tblMenuTheme exist, and what are its columns? ---';
SELECT
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'dbo' AND c.TABLE_NAME = 'tblMenuTheme'
ORDER BY c.ORDINAL_POSITION;

PRINT '--- 2) Does the dbo.MenuThemeTVP table type exist? (should return 1 row: Name, Color) ---';
SELECT
    tt.name AS TypeName,
    c.name  AS ColumnName,
    ty.name AS ColumnType,
    c.max_length
FROM sys.table_types tt
JOIN sys.columns c ON c.object_id = tt.type_table_object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE tt.name = 'MenuThemeTVP';

PRINT '--- 3) Do the procs exist, and when were they last modified? ---';
SELECT name, create_date, modify_date
FROM sys.objects
WHERE type = 'P'
  AND name IN ('sp_GetMenuTheme', 'sp_SaveMenuTheme', 'sp_UpdateBrandLayout', 'sp_GetBrandImages', 'sp_UpdateBrandImage');

PRINT '--- Full definition of sp_SaveMenuTheme (paste this back in full) ---';
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_SaveMenuTheme')) AS sp_SaveMenuTheme_Definition;

PRINT '--- Full definition of sp_GetMenuTheme (paste this back in full) ---';
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_GetMenuTheme')) AS sp_GetMenuTheme_Definition;

PRINT '--- 4) Your brands, so we know which BrandID to filter by below ---';
SELECT BrandID, BrandName, Layout
FROM dbo.tblbrand;

PRINT '--- 5) Current tblMenuTheme rows for the Item Popup (Design 1) fields, ALL brands ---';
PRINT '    (empty result = nothing has ever been saved for these fields, for anyone)';
SELECT *
FROM dbo.tblMenuTheme
WHERE Name LIKE 'popup[_]%'
ORDER BY BrandID, BranchID, Name;

PRINT '--- 6) The Version row (bumped by +1 every time sp_SaveMenuTheme runs, for ANY field) ---';
PRINT '    Note this number, click Save on the Item Popup colours in the app, then run';
PRINT '    ONLY this last query again:';
PRINT '      SELECT * FROM dbo.tblMenuTheme WHERE Name = ''Version'';';
PRINT '    - number unchanged  -> the Save request never reached/completed in the DB at all';
PRINT '    - number went up    -> the save DID run; the popup fields are landing under the';
PRINT '                           wrong row/Name or being read back incorrectly instead';
SELECT * FROM dbo.tblMenuTheme WHERE Name = 'Version';
