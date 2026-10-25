/* =====================================================================
   77_No_Physical_Delete.sql  -  HRMS: "Delete" only ever flags a record
   ---------------------------------------------------------------------
   Run after 76. Safe to re-run. Builds on db/28 (the standing rule: a
   record is never removed - Deleted = 1, DeletedBy, DeletedDate).

     1. Core.fn_PhysicalDeletes(@definition): finds a DELETE on a real
        table in a procedure / trigger / function text (table variables
        @t and temp tables #t are fine - they are not records).
     2. Documents.usp_DocumentType_Manage: its old fallback that could
        still DELETE (when the Deleted column was missing) now refuses.
     3. Cascading foreign keys (ON DELETE / ON UPDATE CASCADE or SET NULL)
        become NO ACTION - SQL Server cannot put the INSTEAD OF DELETE
        guard on such a table, and nothing is deleted in this system.
        Core.usp_SoftDelete_Apply then runs again, so every table has its
        Deleted columns and its guard trigger (a stray DELETE from SSMS
        or a report tool is turned into Deleted = 1).
     4. Database trigger TR_HRMS_NoPhysicalDelete: CREATE / ALTER of a
        procedure, trigger or function that DELETEs from a table is
        refused, with the soft-delete statement to use instead. This also
        stops an old script (e.g. 09, 14, 24) from bringing back a
        procedure version that still deleted rows.
     5. A report: modules that still contain a DELETE (there should be
        none), and tables without a guard (no primary key).
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---- 1. detector ------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Core].[fn_PhysicalDeletes] (@Definition NVARCHAR(MAX))
RETURNS @Hits TABLE (Position INT NOT NULL, TargetName NVARCHAR(260) NOT NULL, Snippet NVARCHAR(200) NULL)
AS
BEGIN
    IF @Definition IS NULL RETURN;

    DECLARE @u NVARCHAR(MAX) = UPPER(@Definition);
    DECLARE @p INT = CHARINDEX(N'DELETE', @u);
    DECLARE @prevChar NCHAR(1), @nextChar NCHAR(1), @before NVARCHAR(40), @lineStart INT, @back INT,
            @rest NVARCHAR(400), @tok NVARCHAR(260), @target NVARCHAR(260), @cut INT;

    WHILE @p > 0
    BEGIN
        SET @prevChar = CASE WHEN @p > 1 THEN SUBSTRING(@u, @p - 1, 1) ELSE N' ' END;
        SET @nextChar = SUBSTRING(@u + N' ', @p + 6, 1);

        -- the whole word DELETE, not "IsDeleted" / "DeletedBy" / "@Deleted"
        IF @prevChar NOT LIKE N'[A-Z0-9_@#.$]' AND @nextChar NOT LIKE N'[A-Z0-9_]'
        BEGIN
            -- not inside a "--" comment on the same line
            SET @back = CHARINDEX(NCHAR(10), REVERSE(LEFT(@u, @p - 1)));
            SET @lineStart = CASE WHEN @back = 0 THEN 1 ELSE @p - @back + 1 END;

            -- not "INSTEAD OF DELETE", "AFTER/FOR DELETE", "ON DELETE", "INSERT, DELETE"
            SET @before = RTRIM(TRANSLATE(SUBSTRING(@u, CASE WHEN @p > 40 THEN @p - 40 ELSE 1 END, CASE WHEN @p > 40 THEN 40 ELSE @p - 1 END),
                                          NCHAR(9) + NCHAR(10) + NCHAR(13), N'   '));

            IF CHARINDEX(N'--', SUBSTRING(@u, @lineStart, @p - @lineStart)) = 0
               AND NOT (@before LIKE N'%INSTEAD OF' OR @before LIKE N'%[^A-Z_]ON' OR @before LIKE N'%AFTER'
                        OR @before LIKE N'%[^A-Z_]FOR' OR @before LIKE N'%,' OR @before LIKE N'%''')
            BEGIN
                SET @rest = LTRIM(TRANSLATE(SUBSTRING(@Definition, @p + 6, 400), NCHAR(9) + NCHAR(10) + NCHAR(13), N'   '));
                IF UPPER(@rest) LIKE N'TOP%(%'                       -- DELETE TOP (n) ...
                    SET @rest = LTRIM(SUBSTRING(@rest, CHARINDEX(N')', @rest) + 1, 400));
                SET @tok = LEFT(@rest, CHARINDEX(N' ', @rest + N' ') - 1);
                IF UPPER(@tok) = N'FROM'
                BEGIN
                    SET @rest = LTRIM(SUBSTRING(@rest, 5, 400));
                    SET @target = LEFT(@rest, CHARINDEX(N' ', @rest + N' ') - 1);
                END
                ELSE
                BEGIN
                    SET @target = @tok;                              -- DELETE alias FROM table alias
                    SET @rest = LTRIM(SUBSTRING(@rest, LEN(@tok) + 1, 400));
                    IF UPPER(@rest) LIKE N'FROM %'
                    BEGIN
                        SET @rest = LTRIM(SUBSTRING(@rest, 5, 400));
                        SET @target = LEFT(@rest, CHARINDEX(N' ', @rest + N' ') - 1);
                    END;
                END;
                SET @cut = PATINDEX(N'%[;(,)]%', @target);
                IF @cut > 0 SET @target = LEFT(@target, @cut - 1);

                -- a real table: bracketed or schema-qualified, never @table / #temp
                IF LEN(@target) > 0 AND LEFT(@target, 1) NOT IN (N'@', N'#')
                   AND (LEFT(@target, 1) = N'[' OR CHARINDEX(N'.', @target) > 0)
                    INSERT INTO @Hits (Position, TargetName, Snippet)
                    VALUES (@p, @target, LEFT(TRANSLATE(SUBSTRING(@Definition, @p, 200), NCHAR(9) + NCHAR(10) + NCHAR(13), N'   '), 120));
            END;
        END;
        SET @p = CHARINDEX(N'DELETE', @u, @p + 6);
    END;
    RETURN;
END;
GO

/* ---- 2. document types: no DELETE fallback ---------------------------- */
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'[Documents].[usp_DocumentType_Manage]'));
DECLARE @old NVARCHAR(400) = N'ELSE N''DELETE FROM [Documents].[DocumentTypes] WHERE '' + QUOTENAME(@IdCol) + N'' = @Id;'' END;';
DECLARE @new NVARCHAR(400) = N'ELSE N''RAISERROR(N''''Records are never physically deleted - run db/28_Soft_Delete.sql first.'''', 16, 1);'' END;';
IF @def IS NOT NULL AND CHARINDEX(@old, @def) > 0
BEGIN
    SET @def = REPLACE(@def, @old, @new);
    -- the stored text starts with CREATE [OR ALTER]; make it an ALTER-able statement
    IF CHARINDEX(N'CREATE OR ALTER', UPPER(@def)) = 0
        SET @def = STUFF(@def, CHARINDEX(N'CREATE', UPPER(@def)), 6, N'CREATE OR ALTER');
    EXEC (@def);
    PRINT N'Documents.usp_DocumentType_Manage: the DELETE fallback is gone - a delete only flags the type.';
END
ELSE
    PRINT N'Documents.usp_DocumentType_Manage: nothing to change.';
GO

/* ---- 3. no cascading foreign keys, then the guards on every table ------ */
DECLARE @fk TABLE (Id INT IDENTITY(1, 1), DropSql NVARCHAR(MAX), AddSql NVARCHAR(MAX), Name NVARCHAR(400));
INSERT INTO @fk (DropSql, AddSql, Name)
SELECT  N'ALTER TABLE ' + QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name) + N' DROP CONSTRAINT ' + QUOTENAME(f.name) + N';',
        N'ALTER TABLE ' + QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name)
          + CASE WHEN f.is_not_trusted = 1 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END
          + N' ADD CONSTRAINT ' + QUOTENAME(f.name) + N' FOREIGN KEY ('
          + STUFF((SELECT N', ' + QUOTENAME(c.name) FROM sys.foreign_key_columns fc
                   JOIN sys.columns c ON c.object_id = fc.parent_object_id AND c.column_id = fc.parent_column_id
                   WHERE fc.constraint_object_id = f.object_id ORDER BY fc.constraint_column_id FOR XML PATH(''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N'')
          + N') REFERENCES ' + QUOTENAME(rs.name) + N'.' + QUOTENAME(rt.name) + N' ('
          + STUFF((SELECT N', ' + QUOTENAME(c.name) FROM sys.foreign_key_columns fc
                   JOIN sys.columns c ON c.object_id = fc.referenced_object_id AND c.column_id = fc.referenced_column_id
                   WHERE fc.constraint_object_id = f.object_id ORDER BY fc.constraint_column_id FOR XML PATH(''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N'')
          + N') ON DELETE NO ACTION ON UPDATE NO ACTION;'
          + CASE WHEN f.is_disabled = 1 THEN N' ALTER TABLE ' + QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name) + N' NOCHECK CONSTRAINT ' + QUOTENAME(f.name) + N';' ELSE N'' END,
        QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name) + N'.' + QUOTENAME(f.name)
FROM    sys.foreign_keys AS f
JOIN    sys.tables  AS pt ON pt.object_id = f.parent_object_id
JOIN    sys.schemas AS ps ON ps.schema_id = pt.schema_id
JOIN    sys.tables  AS rt ON rt.object_id = f.referenced_object_id
JOIN    sys.schemas AS rs ON rs.schema_id = rt.schema_id
WHERE   ps.name NOT IN (N'dbo', N'sys')
  AND  (f.delete_referential_action <> 0 OR f.update_referential_action <> 0);

DECLARE @i INT = 1, @n INT = (SELECT COUNT(1) FROM @fk), @d NVARCHAR(MAX), @a NVARCHAR(MAX), @nm NVARCHAR(400);
WHILE @i <= @n
BEGIN
    SELECT @d = DropSql, @a = AddSql, @nm = Name FROM @fk WHERE Id = @i;
    BEGIN TRY
        BEGIN TRANSACTION;
            EXEC (@d);
            EXEC (@a);
        COMMIT;
        PRINT N'Foreign key ' + @nm + N' no longer cascades.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        PRINT N'WARNING: foreign key ' + @nm + N' was left as it is: ' + ERROR_MESSAGE();
    END CATCH;
    SET @i += 1;
END;
PRINT CONCAT(N'Cascading foreign keys changed to NO ACTION: ', @n);
GO

IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    PRINT N'Re-applying the soft-delete columns and delete guards to every table...';
    EXEC [Core].[usp_SoftDelete_Apply];
END
ELSE
    PRINT N'WARNING: Core.usp_SoftDelete_Apply is missing - run db/28_Soft_Delete.sql, then this script again.';
GO

/* ---- 4. refuse new code that deletes ---------------------------------- */
CREATE OR ALTER TRIGGER [TR_HRMS_NoPhysicalDelete]
ON DATABASE
FOR CREATE_PROCEDURE, ALTER_PROCEDURE, CREATE_TRIGGER, ALTER_TRIGGER, CREATE_FUNCTION, ALTER_FUNCTION
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @x XML = EVENTDATA();
    DECLARE @schema SYSNAME = @x.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname');
    DECLARE @object SYSNAME = @x.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname');
    DECLARE @text NVARCHAR(MAX) = @x.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)');

    -- the guard triggers db/28 writes, and the detector itself
    IF @object LIKE N'TR[_]SoftDelete[_]%' OR @object = N'fn_PhysicalDeletes' OR ISNULL(@schema, N'dbo') IN (N'dbo', N'sys')
        RETURN;
    IF OBJECT_ID(N'[Core].[fn_PhysicalDeletes]', N'TF') IS NULL
        RETURN;

    DECLARE @target NVARCHAR(260), @snippet NVARCHAR(200);
    SELECT TOP (1) @target = TargetName, @snippet = Snippet FROM [Core].[fn_PhysicalDeletes](@text) ORDER BY Position;
    IF @target IS NOT NULL
    BEGIN
        ROLLBACK;
        DECLARE @msg NVARCHAR(2000) = CONCAT(
            N'HRMS rule: records are never physically deleted. ', QUOTENAME(@schema), N'.', QUOTENAME(@object),
            N' was NOT saved - it deletes from ', @target, N' ("', @snippet, N'"). ',
            N'Flag the row instead: UPDATE ', @target, N' SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE ... AND Deleted = 0;');
        THROW 50077, @msg, 1;
    END;
END;
GO

/* ---- 5. report --------------------------------------------------------- */
PRINT N'';
PRINT N'Modules that still DELETE from a table (should be none):';
DECLARE @left INT = 0, @line NVARCHAR(600);
DECLARE r CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(N'   ', QUOTENAME(s.name), N'.', QUOTENAME(o.name), N'  ->  ', h.TargetName, N'   "', h.Snippet, N'"')
    FROM   sys.sql_modules AS m
    JOIN   sys.objects     AS o ON o.object_id = m.object_id
    JOIN   sys.schemas     AS s ON s.schema_id = o.schema_id
    CROSS APPLY [Core].[fn_PhysicalDeletes](m.definition) AS h
    WHERE  o.is_ms_shipped = 0 AND s.name NOT IN (N'dbo', N'sys')
      AND  o.name NOT LIKE N'TR[_]SoftDelete[_]%' AND o.name <> N'fn_PhysicalDeletes'
    ORDER BY s.name, o.name, h.Position;
OPEN r; FETCH NEXT FROM r INTO @line;
WHILE @@FETCH_STATUS = 0 BEGIN PRINT @line; SET @left += 1; FETCH NEXT FROM r INTO @line; END;
CLOSE r; DEALLOCATE r;
IF @left = 0 PRINT N'   none';
ELSE PRINT N'   (a DELETE above is still turned into Deleted = 1 by the table''s guard trigger)';

PRINT N'';
PRINT N'Tables without a delete guard (add a primary key, then EXEC Core.usp_SoftDelete_Apply):';
DECLARE @unguarded INT = 0;
DECLARE g CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(N'   ', QUOTENAME(sc.name), N'.', QUOTENAME(tb.name))
    FROM   sys.tables  AS tb
    JOIN   sys.schemas AS sc ON sc.schema_id = tb.schema_id
    WHERE  tb.is_ms_shipped = 0 AND sc.name NOT IN (N'dbo', N'sys', N'INFORMATION_SCHEMA') AND tb.temporal_type <> 1
      AND  NOT EXISTS (SELECT 1 FROM sys.triggers AS t WHERE t.parent_id = tb.object_id AND t.is_instead_of_trigger = 1
                         AND OBJECTPROPERTY(t.object_id, N'ExecIsDeleteTrigger') = 1)
    ORDER BY sc.name, tb.name;
OPEN g; FETCH NEXT FROM g INTO @line;
WHILE @@FETCH_STATUS = 0 BEGIN PRINT @line; SET @unguarded += 1; FETCH NEXT FROM g INTO @line; END;
CLOSE g; DEALLOCATE g;
IF @unguarded = 0 PRINT N'   none - every table turns a DELETE into Deleted = 1';
GO
