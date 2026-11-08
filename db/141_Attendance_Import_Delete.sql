/* =====================================================================
   141_Attendance_Import_Delete.sql  -  Deleting an imported file, days outside the payroll
   ---------------------------------------------------------------------
   Run after db/137. Safe to re-run.

   Import Attendance > Files imported:
   - Delete is refused while a payroll is created for the payroll month of
     its days - a draft too (Create Payroll) - naming the payroll(s) to
     discard / cancel first; and while those days are posted.
   - It removes the days of the companies in scope and says when days of
     other companies stay; the file entry goes with its last day.
   - The list only shows a file while one of its days (in scope) is left,
     and counts those days.
   Attendance Sheet: a day of a From / To outside the payroll month is
   greyed (labels).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[ufn_MonthOf]', N'FN') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/137 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttImport_Manage]
    @Action         VARCHAR(20),
    @Id             BIGINT         = NULL,
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FileName       NVARCHAR(260)  = NULL,
    @FileFormat     VARCHAR(10)    = NULL,
    @MappingText    NVARCHAR(1000) = NULL,
    @FileRowCount   INT            = NULL,
    @SkippedCount   INT            = NULL,
    @Json           NVARCHAR(MAX)  = NULL,
    @PageNumber     INT            = 1,
    @PageSize       INT            = 20,
    @UserId         BIGINT         = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action = 'SAVE'
    BEGIN
        DECLARE @In TABLE (EmployeeId BIGINT, CompanyId INT, WorkDate DATE, ClockIn DATETIME2(0), ClockOut DATETIME2(0), Punches SMALLINT,
                           PRIMARY KEY (EmployeeId, WorkDate));
        INSERT INTO @In (EmployeeId, CompanyId, WorkDate, ClockIn, ClockOut, Punches)
        SELECT  j.EmployeeId, e.CompanyId, j.WorkDate, MIN(j.ClockIn), MAX(j.ClockOut), MAX(ISNULL(j.Punches, 0))
        FROM    OPENJSON(ISNULL(@Json, N'[]'))
                WITH (EmployeeId BIGINT '$.employeeId', WorkDate DATE '$.workDate', ClockIn DATETIME2(0) '$.clockIn',
                      ClockOut DATETIME2(0) '$.clockOut', Punches SMALLINT '$.punches') AS j
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = j.EmployeeId AND e.Deleted = 0
        WHERE   j.WorkDate IS NOT NULL AND [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1
        GROUP BY j.EmployeeId, e.CompanyId, j.WorkDate;

        IF NOT EXISTS (SELECT 1 FROM @In)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Nothing to import - no row matched an employee of your companies.';
            RETURN;
        END;
        /* a month already posted to the payroll is not changed by an import */
        IF EXISTS (SELECT 1 FROM @In i JOIN [Attendance].[Postings] p ON p.EmployeeId = i.EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate))
        BEGIN
            DECLARE @Posted NVARCHAR(200) = (SELECT STRING_AGG(m, N', ') FROM (SELECT DISTINCT FORMAT(p.RunMonth, 'MMM yyyy', 'en-US') AS m
                FROM @In i JOIN [Attendance].[Postings] p ON p.EmployeeId = i.EmployeeId AND p.Deleted = 0
                AND p.RunMonth = [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate)) AS x);
            SELECT @ResultCode = 'POSTED', @ResultMessage = CONCAT(N'Already posted to the payroll: ', @Posted,
                N'. Undo the posting (Monthly Summary) before importing these days again.');
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Attendance].[Imports] (FileName, FileFormat, MappingText, FromDate, ToDate, FileRowCount, RecordCount, EmployeeCount, SkippedCount, CreatedBy)
            SELECT LEFT(ISNULL(@FileName, N'attendance'), 260), CASE WHEN @FileFormat = 'PUNCH' THEN 'PUNCH' ELSE 'PAIRED' END, LEFT(@MappingText, 1000),
                   MIN(WorkDate), MAX(WorkDate), ISNULL(@FileRowCount, 0), COUNT(1), COUNT(DISTINCT EmployeeId), ISNULL(@SkippedCount, 0), @UserId
            FROM   @In;
            SET @NewId = SCOPE_IDENTITY();

            /* the new file replaces those days (the old values are kept, deleted) */
            UPDATE r SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Attendance].[Records] AS r
            JOIN   @In AS i ON i.EmployeeId = r.EmployeeId AND i.WorkDate = r.WorkDate
            WHERE  r.Deleted = 0;

            INSERT INTO [Attendance].[Records] (ImportId, CompanyId, EmployeeId, WorkDate, ClockIn, ClockOut, PunchCount, Source, CreatedBy)
            SELECT @NewId, i.CompanyId, i.EmployeeId, i.WorkDate, i.ClockIn, i.ClockOut, i.Punches, 'IMPORT', @UserId
            FROM   @In AS i;
            SET @TotalCount = @@ROWCOUNT;
        COMMIT TRANSACTION;

        SELECT DISTINCT i.CompanyId, [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate) AS RunMonth FROM @In AS i;
        SET @ResultMessage = CONCAT(N'Imported ', @TotalCount, N' days.');
        RETURN;
    END;

    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) NOT BETWEEN 1 AND 200 THEN 20 ELSE @PageSize END;
        ;WITH x AS (
            SELECT  i.ImportId, i.FileName, i.FileFormat, i.MappingText, i.FromDate, i.ToDate, i.FileRowCount, i.RecordCount, i.EmployeeCount,
                    i.SkippedCount, i.CreatedDate,
                    COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ce.FirstName, N' ', ce.LastName))), N''), cu.Username) AS CreatedByName,
                    (SELECT COUNT(1) FROM [Attendance].[Records] r WHERE r.ImportId = i.ImportId AND r.Deleted = 0
                     AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS LiveCount
            FROM    [Attendance].[Imports] AS i
            LEFT JOIN [Security].[Users] AS cu ON cu.UserId = i.CreatedBy
            LEFT JOIN [Employee].[Employees] AS ce ON ce.EmployeeId = cu.EmployeeId
            WHERE   i.Deleted = 0
              AND   EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.ImportId = i.ImportId AND r.Deleted = 0
                            AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1)
        )
        SELECT x.*, COUNT(1) OVER () AS Total FROM x
        ORDER BY x.CreatedDate DESC, x.ImportId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        /* db/141: the payroll months of the file's days (the companies in scope) */
        DECLARE @Months TABLE (CompanyId INT, RunMonth DATE);
        INSERT INTO @Months SELECT DISTINCT r.CompanyId, [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)
        FROM [Attendance].[Records] r WHERE r.ImportId = @Id AND r.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;

        IF NOT EXISTS (SELECT 1 FROM @Months)
        BEGIN
            /* nothing of it left in scope: the file entry goes when no day of it is left at all */
            IF NOT EXISTS (SELECT 1 FROM [Attendance].[Records] WHERE ImportId = @Id AND Deleted = 0)
            BEGIN
                UPDATE [Attendance].[Imports] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE ImportId = @Id AND Deleted = 0;
                SET @ResultMessage = N'The file was removed.';
                RETURN;
            END;
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The days left in this file belong to companies you do not work with - choose All companies (or those companies) to remove them too.';
            RETURN;
        END;

        /* a payroll created for one of those months - a draft too - keeps the file: its attendance is in it */
        DECLARE @Runs NVARCHAR(400) = (
            SELECT STRING_AGG(CONCAT(ISNULL(pr.RunCode, N'Draft'), N' (', FORMAT(pr.RunMonth, 'MMM yyyy', 'en-US'),
                                     CASE WHEN pr.Stage = 'DRAFT' THEN N', draft' ELSE N'' END, N')'), N', ')
            FROM   [Payroll].[PayrollRuns] AS pr
            JOIN   @Months AS m ON m.CompanyId = pr.CompanyId AND m.RunMonth = pr.RunMonth
            WHERE  pr.Deleted = 0 AND pr.RunType = 'REGULAR' AND pr.Stage <> 'CANCELLED');
        IF @Runs IS NOT NULL
        BEGIN
            SELECT @ResultCode = 'PAYROLL', @ResultMessage = CONCAT(N'A payroll is created for these days: ', @Runs,
                N'. Discard the draft (Create Payroll) or cancel the payroll first, then remove the file.');
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Attendance].[Records] r JOIN [Attendance].[Postings] p ON p.EmployeeId = r.EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)
                   WHERE r.ImportId = @Id AND r.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1)
        BEGIN
            SELECT @ResultCode = 'POSTED', @ResultMessage = N'Days of this file are already posted to the payroll - undo the posting (Monthly Summary) first.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE [Attendance].[Records] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            WHERE  ImportId = @Id AND Deleted = 0 AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1;
            SET @TotalCount = @@ROWCOUNT;
            IF NOT EXISTS (SELECT 1 FROM [Attendance].[Records] WHERE ImportId = @Id AND Deleted = 0)
                UPDATE [Attendance].[Imports] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE ImportId = @Id;
        COMMIT TRANSACTION;
        SELECT CompanyId, RunMonth FROM @Months;
        DECLARE @Left INT = (SELECT COUNT(1) FROM [Attendance].[Records] WHERE ImportId = @Id AND Deleted = 0);
        SET @ResultMessage = CASE WHEN @Left = 0 THEN CONCAT(N'The file was removed (', @TotalCount, N' days).')
                                  ELSE CONCAT(@TotalCount, N' days of your companies were removed - ', @Left,
                                              N' days of other companies stay (choose All companies to remove them too).') END;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('att.outside_0_1_2', 'att', N'Not in the {0} payroll ({1} - {2})', N'خارج رواتب {0} ({1} - {2})', NULL),
        ('att.lg_outside', 'att', N'Another payroll month', N'شهر رواتب آخر', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
