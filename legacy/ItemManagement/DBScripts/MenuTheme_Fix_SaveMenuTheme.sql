/* ============================================================================
   MenuTheme_Fix_SaveMenuTheme.sql
   ----------------------------------------------------------------------------
   Restores dbo.sp_SaveMenuTheme to its correct logic. The live copy of this
   proc had been hand-edited (create_date 2026-07-17) with the UPDATE's WHERE
   clause and the whole INSERT block commented out:

     - INSERT disabled  -> a field that has never had a row for a brand
                           (e.g. every "Item Popup (Design 1)" popup_* field,
                           which is brand new) can never be created. Its
                           UPDATE then matches 0 rows, so the value is
                           silently dropped on every save - no error, nothing
                           saved.
     - UPDATE's WHERE commented out -> for fields that DO already have a row,
                           saving updates that Name for EVERY brand that has
                           one, not just the brand being edited (cross-brand
                           overwrite).

   This restores the original, correct upsert (update-if-exists /
   insert-if-missing, scoped to @BrandId/@BranchId) plus the branch-shadow
   cleanup step, matching DBScripts/MenuTheme_SPs.sql. Only this one
   procedure is touched - the table, the MenuThemeTVP type, and the other
   4 procs are left exactly as they are.

   Safe to re-run.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE dbo.sp_SaveMenuTheme
    @BrandId  INT,
    @BranchId INT = 0,
    @Items    dbo.MenuThemeTVP READONLY
AS
BEGIN
    SET NOCOUNT ON;

    -- update the fields that already have a row for THIS brand/branch
    UPDATE  t
    SET     t.Color = s.Color
    FROM    dbo.tblMenuTheme t
    INNER JOIN @Items s
        ON  t.Name = s.Name
    WHERE   t.BrandID = @BrandId
      AND   t.BranchID = @BranchId;

    -- insert the fields that don't have a row yet for THIS brand/branch
    -- (first time this field is ever saved - e.g. the new popup_* fields)
    INSERT INTO dbo.tblMenuTheme (Name, Color, BrandID, BranchID)
    SELECT  s.Name, s.Color, @BrandId, @BranchId
    FROM    @Items s
    WHERE   NOT EXISTS (
                SELECT 1 FROM dbo.tblMenuTheme t
                WHERE  t.BrandID = @BrandId
                  AND  t.BranchID = @BranchId
                  AND  t.Name = s.Name
            );

    -- The theme editor only ever writes brand-level rows (@BranchId = 0), but
    -- sp_GetMenuTheme PREFERS branch-specific rows. A leftover BranchID <> 0
    -- row would shadow a brand-level edit, so once a field is saved at brand
    -- level, drop any branch-specific copies of it for this brand.
    IF @BranchId = 0
        DELETE  t
        FROM    dbo.tblMenuTheme t
        INNER JOIN @Items s
            ON  t.Name = s.Name
        WHERE   t.BrandID = @BrandId
          AND   t.BranchID <> 0;

    -- bump the single version row (its Color holds the number)
    UPDATE  dbo.tblMenuTheme
    SET     Color = CAST(ISNULL(TRY_CONVERT(INT, Color), 0) + 1 AS NVARCHAR(50))
    WHERE   Name = 'Version';
END
GO
