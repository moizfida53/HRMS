/* =====================================================================
   98_Leave_Balance_Elimination.sql  -  HRMS Leave: large annual balances
   ---------------------------------------------------------------------
   Run after 86 (and 97). Safe to re-run. It replaces Leave.tvf_Balances
   and Leave.usp_LeaveBalance_Manage of db/86 - do not run db/86 again
   after this script.

     1. Leave.LeaveLedger takes a new entry type ELIMINATE: days forced off
        an annual leave balance, with the remarks. The balance counts it
        like an adjustment.
     2. Leave.usp_LeaveBalance_Manage
          ANNUAL     each employee's annual leave balance (left to take:
                     approved and waiting requests off); @MinDays = only
                     those over it. Dashboard: "Leave balance over 30 days";
                     Employees list: the balance and its filter.
          ELIMINATE  only a balance over 60 days; at least 30 days always
                     stay (a balance of 70 -> up to 40 days eliminated).
          LEDGER     the transactions now also say how a leave's salary was
                     paid (cash / payroll) - eliminations show as such.
     3. Right LEAVE_ELIMINATE (Security > Create Roles > Leave requests):
        first run - System Administrator and the roles that manage leave.
     4. Labels (English + Arabic).

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH(N'Leave.LeaveRequests', N'SettlementMode') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/86 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the ELIMINATE entry type ------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveLedger_Type'
             AND parent_object_id = OBJECT_ID(N'[Leave].[LeaveLedger]') AND definition NOT LIKE N'%ELIMINATE%')
    ALTER TABLE [Leave].[LeaveLedger] DROP CONSTRAINT CK_LeaveLedger_Type;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveLedger_Type' AND parent_object_id = OBJECT_ID(N'[Leave].[LeaveLedger]'))
    ALTER TABLE [Leave].[LeaveLedger] WITH CHECK
        ADD CONSTRAINT CK_LeaveLedger_Type CHECK (EntryType IN ('OPENING', 'ADJUST', 'ELIMINATE'));

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveLedger_Days'
             AND parent_object_id = OBJECT_ID(N'[Leave].[LeaveLedger]') AND definition NOT LIKE N'%ELIMINATE%')
    ALTER TABLE [Leave].[LeaveLedger] DROP CONSTRAINT CK_LeaveLedger_Days;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveLedger_Days' AND parent_object_id = OBJECT_ID(N'[Leave].[LeaveLedger]'))
    ALTER TABLE [Leave].[LeaveLedger] WITH CHECK
        ADD CONSTRAINT CK_LeaveLedger_Days CHECK (Days BETWEEN -999 AND 999
            AND (EntryType = 'ADJUST' OR (EntryType = 'OPENING' AND Days >= 0) OR (EntryType = 'ELIMINATE' AND Days < 0)));
GO

/* ---- 2. the balance counts eliminations ------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[tvf_Balances]
(
    @AsOf        DATE,
    @EmployeeId  BIGINT        -- NULL = every employee
)
RETURNS TABLE
AS
RETURN
/* db/98: eliminated days (ELIMINATE) count with the adjustments.
   db/86: Taken / Pending count the paid days only - the days over the balance
   that the employee took unpaid (UnpaidDays) do not reduce it */
WITH et AS (
    SELECT  e.EmployeeId, e.CompanyId, e.HireDate,
            t.LeaveTypeId, t.BalanceMode,
            /* db/82: the employee's own annual leave (Employment Terms) replaces the
               type's days per year for annual leave; blank = the type's */
            CASE WHEN t.Category = 'ANNUAL' AND e.AnnualLeaveDays IS NOT NULL THEN e.AnnualLeaveDays
                 ELSE t.DaysPerYear END AS DaysPerYear,
            t.AccrualMethod,
            op.OpeningDate, ISNULL(op.OpeningDays, 0) AS OpeningDays,
            CASE t.BalanceMode
                 WHEN 'ACCRUE' THEN COALESCE(op.OpeningDate, e.HireDate, DATEFROMPARTS(YEAR(@AsOf), 1, 1))
                 WHEN 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 1, 1)
                 ELSE CAST('19000101' AS DATE) END AS WinStart,
            CASE WHEN t.BalanceMode = 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 12, 31)
                 ELSE CAST('99991231' AS DATE) END AS WinEnd
    FROM    [Employee].[Employees] AS e
    JOIN    [Leave].[LeaveTypes] AS t
            ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
           AND (t.Gender IS NULL OR t.Gender = e.Gender)
    OUTER APPLY (SELECT TOP (1) l.EntryDate AS OpeningDate, l.Days AS OpeningDays
                 FROM   [Leave].[LeaveLedger] AS l
                 WHERE  l.EmployeeId = e.EmployeeId AND l.LeaveTypeId = t.LeaveTypeId AND l.EntryType = 'OPENING'
                   AND  l.Deleted = 0 AND l.EntryDate <= @AsOf
                 ORDER BY l.EntryDate DESC, l.EntryId DESC) AS op
    WHERE   e.Deleted = 0 AND (@EmployeeId IS NULL OR e.EmployeeId = @EmployeeId)
),
calc AS (
    SELECT  et.*,
            CAST(CASE et.BalanceMode
                 WHEN 'ACCRUE' THEN
                      CASE WHEN et.WinStart > @AsOf THEN 0
                           WHEN et.AccrualMethod = 'UPFRONT'
                                THEN ISNULL(et.DaysPerYear, 0) * ((YEAR(@AsOf) - YEAR(et.WinStart)) + (13 - MONTH(et.WinStart)) / 12.0)
                           ELSE ISNULL(et.DaysPerYear, 0) / 12.0
                                * (DATEDIFF(MONTH, et.WinStart, @AsOf) - CASE WHEN DAY(@AsOf) < DAY(et.WinStart) THEN 1 ELSE 0 END)
                      END
                 WHEN 'UNLIMITED' THEN 0
                 ELSE ISNULL(et.DaysPerYear, 0) END AS DECIMAL(9, 2)) AS Earned,
            ISNULL((SELECT SUM(a.Days) FROM [Leave].[LeaveLedger] AS a
                    WHERE a.EmployeeId = et.EmployeeId AND a.LeaveTypeId = et.LeaveTypeId AND a.EntryType IN ('ADJUST', 'ELIMINATE')   -- db/98: an elimination takes days off
                      AND a.Deleted = 0 AND a.EntryDate BETWEEN et.WinStart AND et.WinEnd AND a.EntryDate <= @AsOf), 0) AS Adjusted,
            ISNULL((SELECT SUM(r.Days - r.UnpaidDays) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'APPROVED' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Taken,
            ISNULL((SELECT SUM(r.Days - r.UnpaidDays) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'PENDING' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Pending
    FROM    et
)
SELECT  EmployeeId, CompanyId, LeaveTypeId, BalanceMode, WinStart, WinEnd, OpeningDate,
        CAST(OpeningDays AS DECIMAL(9, 2)) AS OpeningDays, Earned, CAST(Adjusted AS DECIMAL(9, 2)) AS Adjusted,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted END AS DECIMAL(9, 2)) AS Entitled,
        CAST(Taken AS DECIMAL(9, 2)) AS Taken,
        CAST(Pending AS DECIMAL(9, 2)) AS Pending,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted - Taken END AS DECIMAL(9, 2)) AS Available
FROM    calc;
GO

/* ---- 3. balances: ANNUAL, ELIMINATE, ledger with the settlement ---------- */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveBalance_Manage]
    @Action        VARCHAR(20),
    @Id            BIGINT          = NULL,
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL,
    @AsOf          DATE            = NULL,
    @EmployeeId    BIGINT          = NULL,
    @LeaveTypeId   INT             = NULL,
    @Category      VARCHAR(12)     = NULL,
    @Search        NVARCHAR(200)   = NULL,
    @SelfOnly      BIT             = 0,
    @EntryType     VARCHAR(10)     = NULL,
    @EntryDate     DATE            = NULL,
    @Days          DECIMAL(7, 2)   = NULL,
    @Comment       NVARCHAR(500)   = NULL,
    @MinDays       DECIMAL(7, 2)   = NULL,      -- db/98 ANNUAL: only balances over this
    @PageNumber    INT             = 1,
    @PageSize      INT             = 25,
    @UserId        BIGINT          = NULL,

    @TotalCount    INT             = NULL OUTPUT,
    @NewId         BIGINT          = NULL OUTPUT,
    @ResultCode    VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    SET @AsOf = ISNULL(@AsOf, @Today);
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* the employee is in the user's companies (My Leave: the user's own employee, checked by the caller) */
    DECLARE @EmpOk BIT = CASE WHEN @EmployeeId IS NULL THEN 1
                              WHEN @SelfOnly = 1 THEN 1
                              WHEN EXISTS (SELECT 1 FROM [Employee].[Employees] e WHERE e.EmployeeId = @EmployeeId AND e.Deleted = 0
                                             AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                                             AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)) THEN 1
                              ELSE 0 END;
    IF @EmpOk = 0
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee.'; RETURN; END;

    /* ======================= LIST - employee x type ============== */
    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN @PageSize < 1 THEN 25 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;
        SELECT  b.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                co.CompanyName, d.DepartmentName, e.HireDate,
                b.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted, b.Entitled, b.Taken, b.Pending, b.Available,
                COUNT(1) OVER () AS TotalRows
        INTO    #B
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = b.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        WHERE   e.IsDeleted = 0 AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND   (@LeaveTypeId IS NULL OR b.LeaveTypeId = @LeaveTypeId)
          AND   (@Category IS NULL OR t.Category = @Category)
          AND   (@Search IS NULL OR e.FirstName LIKE N'%' + @Search + N'%' OR e.LastName LIKE N'%' + @Search + N'%'
                 OR e.EmployeeCode LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%');

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #B;
        SELECT * FROM #B
        ORDER BY EmployeeName, LeaveTypeId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= EMPLOYEE - one employee's balances ==== */
    IF @Action = 'EMPLOYEE'
    BEGIN
        SELECT  b.EmployeeId, b.LeaveTypeId, t.TypeCode, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                t.AccrualMethod, t.DaysPerYear, t.PayType, b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted,
                b.Entitled, b.Taken, b.Pending, b.Available
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        WHERE   @EmployeeId IS NOT NULL
        ORDER BY t.SortOrder, t.TypeName;
        RETURN;
    END;

    /* ======================= LEDGER - how a balance is made up ===== */
    IF @Action = 'LEDGER'
    BEGIN
        SELECT  'ENTRY' AS Kind, l.EntryId AS RefId, l.EntryType AS Code, l.EntryDate AS OnDate, NULL AS ToDate, l.Days, l.Comment,
                u.Username AS ByName, l.CreatedDate, NULL AS RequestNo, NULL AS Status,
                CAST(NULL AS VARCHAR(10)) AS SettlementMode, CAST(NULL AS DECIMAL(12, 3)) AS SettlementAmount
        FROM    [Leave].[LeaveLedger] AS l
        LEFT JOIN [Security].[Users] AS u ON u.UserId = l.CreatedBy
        WHERE   l.EmployeeId = @EmployeeId AND l.LeaveTypeId = @LeaveTypeId AND l.Deleted = 0
        UNION ALL
        SELECT  'REQUEST', r.LeaveRequestId, 'TAKEN', r.StartDate, ISNULL(r.ActualEndDate, r.EndDate), -(r.Days - r.UnpaidDays),
                CASE WHEN r.UnpaidDays > 0   -- db/86: the unpaid days are not taken from the balance
                     THEN CONCAT(r.Reason, CASE WHEN r.Reason IS NULL THEN N'' ELSE N' - ' END,
                                 N'+ ', FORMAT(r.UnpaidDays, '0.##', 'en-US'), N' unpaid days')
                     ELSE r.Reason END,
                u.Username, r.CreatedDate, r.RequestNo, r.Status,
                r.SettlementMode, r.SettlementAmount     -- db/98: how its leave salary was paid (cash / payroll)
        FROM    [Leave].[LeaveRequests] AS r
        LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
        WHERE   r.EmployeeId = @EmployeeId AND r.LeaveTypeId = @LeaveTypeId AND r.Deleted = 0 AND r.Status IN ('APPROVED', 'PENDING')
        ORDER BY OnDate DESC, CreatedDate DESC;
        RETURN;
    END;

    /* ======================= ANNUAL - each employee's annual leave balance (db/98) ==
       the balance left to take (approved and waiting requests off); @MinDays = only those over it.
       The dashboard counts those over 30 days; the Employees list shows and filters them. */
    IF @Action = 'ANNUAL'
    BEGIN
        SELECT  b.EmployeeId, b.LeaveTypeId, b.Available, b.Pending,
                CAST(b.Available - b.Pending AS DECIMAL(9, 2)) AS Balance
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = b.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        WHERE   t.Category = 'ANNUAL' AND b.Available IS NOT NULL
          AND   e.IsDeleted = 0 AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND   (@MinDays IS NULL OR b.Available - b.Pending > @MinDays);
        RETURN;
    END;

    /* ======================= ELIMINATE - force days off a large annual balance (db/98) ==
       only a balance over 60 days; at least 30 days always stay: 70 -> up to 40 eliminated.
       Kept in the ledger as ELIMINATE (minus days) with the remark. */
    IF @Action = 'ELIMINATE'
    BEGIN
        DECLARE @MinKeep DECIMAL(9, 2) = 30, @EliminateOver DECIMAL(9, 2) = 60;
        DECLARE @xCo INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @xCo IS NULL OR NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND CompanyId = @xCo
                                         AND Deleted = 0 AND Category = 'ANNUAL')
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee and annual leave.'; RETURN; END;

        DECLARE @Bal DECIMAL(9, 2) = (SELECT b.Available - b.Pending FROM [Leave].[tvf_Balances](@Today, @EmployeeId) AS b
                                      WHERE b.LeaveTypeId = @LeaveTypeId);
        IF @Bal IS NULL OR @Bal <= @EliminateOver
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Leave can be eliminated only from a balance over 60 days.'; RETURN; END;
        IF @Days IS NULL OR @Days <= 0
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days to eliminate.'; RETURN; END;
        IF @Days > @Bal - @MinKeep
        BEGIN
            SELECT @ResultCode = 'VALIDATION',
                   @ResultMessage = CONCAT(N'At most ', FORMAT(@Bal - @MinKeep, '0.##', 'en-US'), N' days can be eliminated - 30 days must remain.');
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the remarks for the elimination.'; RETURN; END;

        INSERT INTO [Leave].[LeaveLedger] (CompanyId, EmployeeId, LeaveTypeId, EntryType, EntryDate, Days, Comment, CreatedBy)
        VALUES (@xCo, @EmployeeId, @LeaveTypeId, 'ELIMINATE', @Today, -@Days, @Comment, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CONCAT(FORMAT(@Days, '0.##', 'en-US'), N' days eliminated.');
        RETURN;
    END;

    /* ======================= ADJUST / OPENING ===================== */
    IF @Action = 'ADJUST'
    BEGIN
        DECLARE @eCo INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @eCo IS NULL OR NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND CompanyId = @eCo AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee and leave type.'; RETURN; END;
        IF @EntryType NOT IN ('OPENING', 'ADJUST') OR @Days IS NULL OR @Days NOT BETWEEN -999 AND 999
           OR (@EntryType = 'OPENING' AND @Days < 0) OR (@EntryType = 'ADJUST' AND @Days = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days (an opening balance cannot be negative).'; RETURN; END;
        IF @EntryType = 'ADJUST' AND @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for the adjustment.'; RETURN; END;
        SET @EntryDate = ISNULL(@EntryDate, @Today);

        INSERT INTO [Leave].[LeaveLedger] (CompanyId, EmployeeId, LeaveTypeId, EntryType, EntryDate, Days, Comment, CreatedBy)
        VALUES (@eCo, @EmployeeId, @LeaveTypeId, @EntryType, @EntryDate, @Days, @Comment, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CASE WHEN @EntryType = 'OPENING' THEN N'Opening balance saved.' ELSE N'Balance adjusted.' END;
        RETURN;
    END;

    IF @Action = 'DELETE_ENTRY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Leave].[LeaveLedger] l JOIN [Employee].[Employees] e ON e.EmployeeId = l.EmployeeId
                       WHERE l.EntryId = @Id AND l.Deleted = 0
                         AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                         AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        UPDATE [Leave].[LeaveLedger] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EntryId = @Id;
        SELECT @NewId = @Id, @ResultMessage = N'Balance entry removed.';
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ---- 4. right LEAVE_ELIMINATE ------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM [Security].[Permissions] WHERE PermissionCode = 'LEAVE_ELIMINATE' AND Deleted = 0)
BEGIN
    INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action) VALUES ('LEAVE_ELIMINATE', 'Leave', 'Eliminate');

    INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
    SELECT DISTINCT r.RoleId, p.PermissionId
    FROM   [Security].[Roles] AS r
    JOIN   [Security].[Permissions] AS p ON p.PermissionCode = 'LEAVE_ELIMINATE' AND p.Deleted = 0
    WHERE  r.Deleted = 0
      AND  (r.RoleCode = N'SYSADMIN'
            OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                       WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = 'LEAVE_MANAGE'))
      AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);
    PRINT N'Right LEAVE_ELIMINATE created (users see it after signing in again).';
END;
GO

/* ---- 5. labels ----------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('lv.e_eliminate', 'lv', N'Eliminated', N'ملغاة', NULL),
        ('lv.paid_cash', 'lv', N'Leave salary paid in cash', N'راتب الإجازة مدفوع نقداً', NULL),
        ('lv.paid_payroll', 'lv', N'Leave salary paid in payroll', N'راتب الإجازة مدفوع مع الرواتب', NULL),
        ('lv.not_settled', 'lv', N'Leave salary not settled yet', N'لم تتم تسوية راتب الإجازة بعد', NULL),
        ('lv.eliminate_title', 'lv', N'Eliminate leave', N'إلغاء رصيد إجازة', NULL),
        ('lv.eliminate_hint', 'lv', N'The balance is over 60 days. Up to {0} days can be eliminated - 30 days always remain.', N'الرصيد أكثر من 60 يوماً. يمكن إلغاء حتى {0} يوم - يبقى دائماً 30 يوماً.', NULL),
        ('lv.eliminate_days', 'lv', N'Days to eliminate', N'الأيام المراد إلغاؤها', NULL),
        ('lv.eliminate_remarks', 'lv', N'Remarks', N'ملاحظات', NULL),
        ('lv.eliminate_remarks_hint', 'lv', N'Why the leave is eliminated', N'سبب إلغاء الإجازة', NULL),
        ('lv.eliminate_button', 'lv', N'Eliminate', N'إلغاء الأيام', NULL),
        ('lv.eliminate_after', 'lv', N'Balance after', N'الرصيد بعد الإلغاء', NULL),
        ('lv.transactions', 'lv', N'Leave transactions', N'حركات الإجازة', NULL),
        ('dash.leave_over_30', 'dash', N'Leave balance > 30 days', N'رصيد إجازة > 30 يوماً', NULL),
        ('dash.leave_over_30_note', 'dash', N'Annual leave left to take', N'الإجازة السنوية المتبقية', NULL),
        ('dash.leave_over_30_open', 'dash', N'Show these employees', N'عرض هؤلاء الموظفين', NULL),
        ('emp.f_leave_over_30', 'emp', N'Leave balance over 30 days', N'رصيد إجازة أكثر من 30 يوماً', NULL),
        ('emp.f_leave_over_60', 'emp', N'Leave balance over 60 days', N'رصيد إجازة أكثر من 60 يوماً', NULL),
        ('emp.leave_balance_title', 'emp', N'Annual leave balance: {0} days', N'رصيد الإجازة السنوية: {0} يوم', NULL),
        ('emp.act_leave_transactions', 'emp', N'Leave transactions', N'حركات الإجازة', NULL),
        ('emp.act_eliminate_leave', 'emp', N'Eliminate leave', N'إلغاء رصيد إجازة', NULL),
        ('sec.fn_leave_eliminate', 'sec', N'Eliminate leave', N'إلغاء رصيد الإجازة', NULL),
        ('sec.fn_leave_eliminate_hint', 'sec', N'Force days off an annual leave balance over 60 days (30 days always remain)', N'خصم أيام من رصيد إجازة سنوية يزيد عن 60 يوماً (يبقى دائماً 30 يوماً)', NULL),
        ('js.lv_eliminate_days', 'js', N'Enter the days to eliminate (at most {0}).', N'أدخل الأيام المراد إلغاؤها (بحد أقصى {0}).', NULL),
        ('js.lv_eliminate_ok', 'js', N'Eliminate', N'إلغاء الأيام', NULL),
        ('js.lv_eliminate_remarks', 'js', N'Enter the remarks.', N'أدخل الملاحظات.', NULL),
        ('js.lv_eliminate_confirm', 'js', N'Eliminate {0} days?', N'إلغاء {0} يوم؟', NULL),
        ('js.lv_eliminate_confirm_text', 'js', N'The balance goes from {0} to {1} days. This is kept in the leave transactions.', N'يصبح الرصيد {1} يوماً بدلاً من {0}. يُحفظ ذلك في حركات الإجازة.', NULL),
        ('msg.lv_elim_only_over', 'msg', N'Leave can be eliminated only from a balance over 60 days.', N'يمكن إلغاء الإجازة فقط من رصيد يزيد عن 60 يوماً.', N'Leave can be eliminated only from a balance over 60 days.'),
        ('msg.lv_elim_days', 'msg', N'Enter the number of days to eliminate.', N'أدخل عدد الأيام المراد إلغاؤها.', N'Enter the number of days to eliminate.'),
        ('msg.lv_elim_max', 'msg', N'At most {0} days can be eliminated - 30 days must remain.', N'يمكن إلغاء {0} يوم كحد أقصى - يجب أن يبقى 30 يوماً.', N'At most {0} days can be eliminated - 30 days must remain.'),
        ('msg.lv_elim_remarks', 'msg', N'Enter the remarks for the elimination.', N'أدخل ملاحظات الإلغاء.', N'Enter the remarks for the elimination.'),
        ('msg.lv_elim_done', 'msg', N'{0} days eliminated.', N'تم إلغاء {0} يوم.', N'{0} days eliminated.'),
        ('msg.lv_elim_choose', 'msg', N'Choose the employee and annual leave.', N'اختر الموظف والإجازة السنوية.', N'Choose the employee and annual leave.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Leave elimination labels inserted: ', @LabelsInserted);
GO

SET NOEXEC OFF;
GO
