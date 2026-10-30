/**********************************************************************************
  POS_36_DineIn_FloorFix.sql
  Tables added to tblTable with a TableType that had no tblPOS_TableArea row
  were not shown (no floor tab to put them on). sp_POS_DineIn_GetFloor now
  adds the missing area rows itself. Safe to re-run.

  The SELECT at the end shows your tables exactly as the page reads them.
**********************************************************************************/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

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

-- check: every table with the floor it is drawn on
EXEC dbo.sp_POS_DineIn_GetFloor;
GO
