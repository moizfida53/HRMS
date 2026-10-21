/* =====================================================================
   62_Employee_Audit_Sorting.sql  -  HRMS: sortable Audit Report
   ---------------------------------------------------------------------
   Run after 60. Re-issues Employee.usp_EmployeeAudit_Manage (db/60) with:
     - LIST @SortColumn (Date / Employee / Type / Field / ChangedBy) and
       @SortDirection (ASC / DESC) - the report's column headers sort the
       whole result, not just the page shown
     - search also matches the field name, the transaction type and who
       made the change (the employee's audit popup has a search bar only)
     - the labels of the employee's audit popup (English + Arabic)
   Safe to re-run. No table change.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Employee].[EmployeeAuditLog]', N'U') IS NULL
    RAISERROR(N'Run db/60_Employee_PayrollCalendar_Audit.sql first.', 16, 1);
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeAudit_Manage]
    @Action           VARCHAR(20),
    @Id               BIGINT          = NULL,     -- ADD: the employee
    @EmployeeId       BIGINT          = NULL,     -- LIST: one employee
    @CompanyId        INT             = NULL,     -- a user pinned to a company
    @CompanyIds       NVARCHAR(2000)  = NULL,     -- top-bar company filter (CSV)
    @TransactionType  VARCHAR(400)    = NULL,     -- ADD: the type; LIST: CSV of types (NULL = all)
    @FieldName        NVARCHAR(100)   = NULL,
    @OldValue         NVARCHAR(500)   = NULL,
    @NewValue         NVARCHAR(500)   = NULL,
    @Reference        NVARCHAR(100)   = NULL,
    @Remarks          NVARCHAR(1000)  = NULL,
    @DateFrom         DATETIME2(0)    = NULL,     -- LIST: UTC instant, inclusive (the app converts the user's local day)
    @DateTo           DATETIME2(0)    = NULL,     -- LIST: UTC instant, exclusive
    @Search           NVARCHAR(200)   = NULL,
    @SortColumn       VARCHAR(30)     = NULL,     -- LIST: Date (default) / Employee / Type / Field / ChangedBy
    @SortDirection    VARCHAR(4)      = NULL,     -- ASC / DESC (default DESC for Date, ASC otherwise)
    @PageNumber       INT             = 1,
    @PageSize         INT             = 50,
    @UserId           BIGINT          = NULL,

    @TotalCount       INT             = NULL OUTPUT,
    @NewId            BIGINT          = NULL OUTPUT,
    @ResultCode       VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage    NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 50 WHEN @PageSize > 20000 THEN 20000 ELSE @PageSize END;
    SET @SortColumn = CASE WHEN @SortColumn IN ('Employee', 'Type', 'Field', 'ChangedBy') THEN @SortColumn ELSE 'Date' END;
    SET @SortDirection = CASE WHEN UPPER(@SortDirection) IN ('ASC', 'DESC') THEN UPPER(@SortDirection)
                              WHEN @SortColumn = 'Date' THEN 'DESC' ELSE 'ASC' END;

    IF @Action NOT IN ('ADD', 'LIST')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= ADD ================================= */
    IF @Action = 'ADD'
    BEGIN
        DECLARE @aCo INT;
        SELECT @aCo = CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @Id;
        IF @aCo IS NULL OR NULLIF(LTRIM(RTRIM(@TransactionType)), '') IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
            RETURN;
        END;

        INSERT INTO [Employee].[EmployeeAuditLog] (EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Reference, Remarks, ActionBy)
        VALUES (@Id, @aCo, UPPER(LTRIM(RTRIM(@TransactionType))), NULLIF(@FieldName, N''), @OldValue, @NewValue,
                NULLIF(@Reference, N''), NULLIF(@Remarks, N''), @UserId);
        SET @NewId = SCOPE_IDENTITY();
        RETURN;
    END;

    /* ======================= LIST ================================ */
    DECLARE @Types TABLE (TransactionType VARCHAR(40) PRIMARY KEY);
    INSERT INTO @Types (TransactionType)
    SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(@TransactionType, ''), ',') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @AllTypes BIT = CASE WHEN EXISTS (SELECT 1 FROM @Types) THEN 0 ELSE 1 END;

    ;WITH x AS (
        SELECT  a.AuditLogId, a.EmployeeId, a.CompanyId, a.TransactionType, a.FieldName, a.OldValue, a.NewValue,
                a.Reference, a.Remarks, a.ActionBy, a.ActionDate,
                ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName,
                e.ArabicName, co.CompanyName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Employee].[EmployeeAuditLog] AS a
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = a.CompanyId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = a.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   (@CompanyId  IS NULL OR a.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(a.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND   (@EmployeeId IS NULL OR a.EmployeeId = @EmployeeId)
          AND   (@AllTypes = 1 OR a.TransactionType IN (SELECT TransactionType FROM @Types))
          AND   (@DateFrom IS NULL OR a.ActionDate >= @DateFrom)
          AND   (@DateTo IS NULL OR a.ActionDate < @DateTo)
          AND   (@Search IS NULL
                 OR e.EmployeeCode LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%'
                 OR CONCAT(e.FirstName, N' ', e.LastName) LIKE N'%' + @Search + N'%' OR e.ArabicName LIKE N'%' + @Search + N'%'
                 OR a.OldValue LIKE N'%' + @Search + N'%' OR a.NewValue LIKE N'%' + @Search + N'%'
                 OR a.Reference LIKE N'%' + @Search + N'%' OR a.Remarks LIKE N'%' + @Search + N'%'
                 OR a.FieldName LIKE N'%' + @Search + N'%' OR a.TransactionType LIKE N'%' + REPLACE(@Search, N' ', N'_') + N'%'
                 OR CONCAT(ue.FirstName, N' ', ue.LastName) LIKE N'%' + @Search + N'%' OR u.Username LIKE N'%' + @Search + N'%')
    ),
    sorted AS (
        SELECT  x.*,
                ROW_NUMBER() OVER (ORDER BY
                    CASE WHEN @SortColumn = 'Employee'  AND @SortDirection = 'ASC'  THEN x.EmployeeName END ASC,
                    CASE WHEN @SortColumn = 'Employee'  AND @SortDirection = 'DESC' THEN x.EmployeeName END DESC,
                    CASE WHEN @SortColumn = 'Type'      AND @SortDirection = 'ASC'  THEN x.TransactionType END ASC,
                    CASE WHEN @SortColumn = 'Type'      AND @SortDirection = 'DESC' THEN x.TransactionType END DESC,
                    CASE WHEN @SortColumn = 'Field'     AND @SortDirection = 'ASC'  THEN x.FieldName END ASC,
                    CASE WHEN @SortColumn = 'Field'     AND @SortDirection = 'DESC' THEN x.FieldName END DESC,
                    CASE WHEN @SortColumn = 'ChangedBy' AND @SortDirection = 'ASC'  THEN x.ActionByName END ASC,
                    CASE WHEN @SortColumn = 'ChangedBy' AND @SortDirection = 'DESC' THEN x.ActionByName END DESC,
                    CASE WHEN @SortColumn = 'Date'      AND @SortDirection = 'ASC'  THEN x.ActionDate END ASC,
                    x.ActionDate DESC, x.AuditLogId DESC) AS RowNo,
                COUNT(1) OVER () AS TotalRows
        FROM    x
    )
    SELECT  *
    INTO    #Page
    FROM    sorted
    WHERE   RowNo >  (@PageNumber - 1) * @PageSize
      AND   RowNo <= @PageNumber * @PageSize;

    SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
    IF @TotalCount = 0 AND @PageNumber > 1
        SELECT @TotalCount = COUNT(1)
        FROM   [Employee].[EmployeeAuditLog] AS a
        WHERE  (@CompanyId  IS NULL OR a.CompanyId = @CompanyId)
          AND  (@EmployeeId IS NULL OR a.EmployeeId = @EmployeeId);

    SELECT AuditLogId, EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Reference, Remarks,
           ActionBy, ActionDate, EmployeeNo, EmployeeName, ArabicName, CompanyName, ActionByName
    FROM   #Page
    ORDER BY RowNo;
END;
GO

/* ------------------------------------------------------------------
   Labels of the employee's audit popup (insert new keys only)
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('aud.panel_search_placeholder', 'aud', N'Search change, value, reference or user', N'ابحث في التغيير أو القيمة أو المرجع أو المستخدم', NULL),
        ('aud.all_time', 'aud', N'All time', N'كل الفترات', NULL),
        ('aud.open_full_report', 'aud', N'Open full report', N'فتح التقرير الكامل', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Audit popup labels inserted: ', @LabelsInserted);
GO
