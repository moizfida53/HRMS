/* =====================================================================
   86_Leave_Unpaid_Resume_Settlement.sql  -  HRMS Leave
   ---------------------------------------------------------------------
   Run after 82 (and 84/85). CREATE OR ALTER / IF NOT EXISTS everywhere -
   safe to re-run. It replaces Leave.usp_LeaveRequest_Manage,
   Leave.usp_LeaveBalance_Manage (db/69) and Leave.tvf_Balances (db/82):
   do not run db/69 or db/82 again after this script.

     1. More days than the balance: the request is no longer refused. The
        days over the balance are UNPAID - the form shows the paid / unpaid
        split and the employee confirms it (Leave.LeaveRequests.UnpaidDays).
        Only the paid days come off the balance. An early return gives
        back the unpaid days first.
     2. Resume date (ResumeDate): the day the employee is back at work -
        blank = the next working day after the leave (weekend and public
        holidays skipped). For reference only, no effect on the balance.
     3. Leave salary settlement, by HR on an approved leave (LEAVE_SETTLE):
          PAYROLL  the leave salary is paid with the monthly payroll (as
                   usual)
          CASH     the leave salary is paid in cash before the leave; the
                   payroll of the leave month(s) recovers it (pay
                   component "Leave Salary Advance", LEAVE_ADV)
     4. Payroll: an approved leave with unpaid days gets a one-time
        "Unpaid Leave" deduction (UNPAID_LV) in the month(s) of those days;
        a leave type paid "Unpaid" deducts all its days. Daily rate =
        monthly salary / the daily wage divisor of the indemnity rules
        (26). Both kinds of pay items are kept in step with the leave
        (Leave.usp_LeaveRequest_SyncPay): a change, early return or
        cancellation replaces them - except those a payroll has already
        taken (they stay; settle any difference on Pay Items). A month
        whose payroll is closed moves the item to the next month.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NULL OR COL_LENGTH(N'Employee.Employees', N'AnnualLeaveDays') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/68, db/69 and db/82 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. new columns ---------------------------------------------------- */
IF COL_LENGTH(N'Leave.LeaveRequests', N'UnpaidDays') IS NULL
    ALTER TABLE [Leave].[LeaveRequests] ADD UnpaidDays DECIMAL(6, 2) NOT NULL CONSTRAINT DF_LeaveRequests_Unpaid DEFAULT (0);
IF COL_LENGTH(N'Leave.LeaveRequests', N'ResumeDate') IS NULL
    ALTER TABLE [Leave].[LeaveRequests] ADD ResumeDate DATE NULL;
IF COL_LENGTH(N'Leave.LeaveRequests', N'SettlementMode') IS NULL
    ALTER TABLE [Leave].[LeaveRequests] ADD
        SettlementMode       VARCHAR(10)    NULL,      -- PAYROLL / CASH (NULL = not settled yet: the monthly payroll)
        SettlementAmount     DECIMAL(12, 3) NULL,      -- CASH: the amount paid
        SettlementDailyRate  DECIMAL(12, 3) NULL,      -- the daily leave salary when it was settled
        SettlementDate       DATE           NULL,      -- CASH: the day it was paid
        SettlementRemarks    NVARCHAR(500)  NULL,
        SettledBy            BIGINT         NULL,
        SettledDate          DATETIME2(0)   NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveRequests_Unpaid')
    ALTER TABLE [Leave].[LeaveRequests] ADD CONSTRAINT CK_LeaveRequests_Unpaid CHECK (UnpaidDays >= 0 AND UnpaidDays <= Days);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_LeaveRequests_Settlement')
    ALTER TABLE [Leave].[LeaveRequests] ADD CONSTRAINT CK_LeaveRequests_Settlement
        CHECK (SettlementMode IS NULL OR SettlementMode IN ('PAYROLL', 'CASH'));
GO

/* ------------------------------------------------------------------
   2. Leave.fn_ResumeDate - the next working day after the leave
   ------------------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[fn_ResumeDate]
(
    @CompanyId  INT,
    @LastDay    DATE,
    @HalfDay    BIT
)
RETURNS DATE
AS
BEGIN
    IF @LastDay IS NULL RETURN NULL;
    IF @HalfDay = 1 RETURN @LastDay;          -- the other half of the day is worked

    DECLARE @Weekend VARCHAR(30) = (SELECT WeekendDays FROM [Leave].[Settings] WHERE CompanyId = @CompanyId AND Deleted = 0);
    SET @Weekend = ',' + REPLACE(ISNULL(@Weekend, '5,6'), ' ', '') + ',';
    DECLARE @Day DATE = DATEADD(DAY, 1, @LastDay), @Step INT = 0;
    -- ISO weekday without depending on DATEFIRST: 1900-01-01 was a Monday
    WHILE @Step < 60
          AND (CHARINDEX(',' + CAST(DATEDIFF(DAY, CAST('19000101' AS DATE), @Day) % 7 + 1 AS VARCHAR(1)) + ',', @Weekend) > 0
               OR EXISTS (SELECT 1 FROM [Leave].[PublicHolidays] AS h
                          WHERE h.Deleted = 0 AND (h.CompanyId IS NULL OR h.CompanyId = @CompanyId)
                            AND @Day BETWEEN h.FromDate AND h.ToDate))
    BEGIN
        SET @Day = DATEADD(DAY, 1, @Day);
        SET @Step += 1;
    END;
    RETURN @Day;
END;
GO

/* existing requests: the resume date they would have had */
UPDATE r SET ResumeDate = [Leave].[fn_ResumeDate](r.CompanyId, ISNULL(r.ActualEndDate, r.EndDate), r.HalfDay)
FROM   [Leave].[LeaveRequests] AS r
WHERE  r.ResumeDate IS NULL AND r.Deleted = 0 AND r.ActualReturnDate IS NULL;
UPDATE [Leave].[LeaveRequests] SET ResumeDate = ActualReturnDate WHERE ResumeDate IS NULL AND ActualReturnDate IS NOT NULL;
GO

/* ------------------------------------------------------------------
   3. Leave.tvf_PayRate - monthly salary and daily rates of an employee
      (the salary items of the month, else the profile salary - as the
      payroll and the final settlement read it)
   ------------------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[tvf_PayRate]
(
    @EmployeeId  BIGINT,
    @Month       DATE           -- the first day of a month
)
RETURNS TABLE
AS
RETURN
WITH s AS (
    SELECT  SUM(f.Amount) AS Monthly,
            SUM(CASE WHEN f.IsLeaveSalaryApplicable = 1 THEN f.Amount ELSE 0 END) AS LeaveBase
    FROM    [Payroll].[ufn_FinalSettlement_Salary](@EmployeeId, @Month) AS f
), d AS (
    SELECT  ISNULL(NULLIF((SELECT TOP (1) r.DailyWageDivisor
                           FROM   [Payroll].[IndemnityRuleSets] AS r
                           WHERE  r.Deleted = 0 AND r.IsActive = 1 AND r.EffectiveFrom <= EOMONTH(@Month)
                             AND  (r.EffectiveTo IS NULL OR r.EffectiveTo >= @Month)
                           ORDER BY r.EffectiveFrom DESC, r.IndemnityRuleSetId DESC), 0), 26) AS Divisor
)
SELECT  CAST(ISNULL(s.Monthly, 0) AS DECIMAL(12, 3)) AS MonthlySalary,
        CAST(CASE WHEN ISNULL(s.LeaveBase, 0) > 0 THEN s.LeaveBase ELSE ISNULL(s.Monthly, 0) END AS DECIMAL(12, 3)) AS LeaveSalary,
        CAST(d.Divisor AS DECIMAL(5, 2)) AS Divisor,
        CAST(ROUND(ISNULL(s.Monthly, 0) / d.Divisor, 3) AS DECIMAL(12, 3)) AS DailyRate,
        CAST(ROUND(CASE WHEN ISNULL(s.LeaveBase, 0) > 0 THEN s.LeaveBase ELSE ISNULL(s.Monthly, 0) END / d.Divisor, 3) AS DECIMAL(12, 3)) AS DailyLeaveRate
FROM    s CROSS JOIN d;
GO

/* ------------------------------------------------------------------
   4. pay component "Leave Salary Advance" for every company with payroll
   ------------------------------------------------------------------ */
INSERT INTO [Payroll].[PayComponents]
    (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod,
     IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, SystemCode, IsSystem, IsActive)
SELECT  c.CompanyId, N'LEAVE_ADV', N'Leave Salary Advance', N'سلفة راتب الإجازة', N'Leave Salary Advance', 'DEDUCTION', 'VARIABLE', 'SYSTEM',
        0, 0, 1, 245, 'LEAVE_ADVANCE', 1, 1
FROM    [Core].[Companies] AS c
WHERE   c.Deleted = 0
  AND   EXISTS (SELECT 1 FROM [Payroll].[PayComponents] p WHERE p.CompanyId = c.CompanyId AND p.Deleted = 0 AND p.SystemCode = 'BASIC')
  AND   NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] p
                    WHERE p.CompanyId = c.CompanyId AND p.Deleted = 0 AND (p.SystemCode = 'LEAVE_ADVANCE' OR p.ComponentCode = N'LEAVE_ADV'));
PRINT CONCAT(N'Leave Salary Advance pay components added: ', @@ROWCOUNT);
GO

/* ------------------------------------------------------------------
   5. Leave.usp_LeaveRequest_SyncPay - the request's pay items
      (inside the caller's transaction)
        LEAVE:<id>:UNPAID  one-time Unpaid Leave deduction per month
        LEAVE:<id>:CASH    one-time Leave Salary Advance recovery per month
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveRequest_SyncPay]
    @Id      BIGINT,
    @UserId  BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Co INT, @Emp BIGINT, @Type INT, @Start DATE, @Last DATE, @Half BIT, @Status VARCHAR(12), @Days DECIMAL(6, 2),
            @Unpaid DECIMAL(6, 2), @Mode VARCHAR(10), @Cash DECIMAL(12, 3), @No VARCHAR(20), @PayType VARCHAR(10),
            @Now DATETIME2(0) = SYSUTCDATETIME();
    SELECT  @Co = r.CompanyId, @Emp = r.EmployeeId, @Type = r.LeaveTypeId, @Start = r.StartDate, @Last = ISNULL(r.ActualEndDate, r.EndDate),
            @Half = r.HalfDay, @Status = r.Status, @Days = r.Days, @Unpaid = r.UnpaidDays, @Mode = r.SettlementMode,
            @Cash = r.SettlementAmount, @No = r.RequestNo, @PayType = t.PayType
    FROM    [Leave].[LeaveRequests] AS r
    JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
    WHERE   r.LeaveRequestId = @Id AND r.Deleted = 0;
    IF @Co IS NULL RETURN;

    DECLARE @RefU NVARCHAR(50) = CONCAT(N'LEAVE:', @Id, N':UNPAID'), @RefC NVARCHAR(50) = CONCAT(N'LEAVE:', @Id, N':CASH');

    /* the request's items; those a payroll has taken (not a draft) stay as they are */
    DECLARE @Items TABLE (ItemId BIGINT PRIMARY KEY, Ref NVARCHAR(50), StartMonth DATE, Amount DECIMAL(12, 3), Locked BIT);
    INSERT INTO @Items (ItemId, Ref, StartMonth, Amount, Locked)
    SELECT  i.EmployeePayItemId, i.SourceRef, i.StartMonth, i.Amount,
            CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollRunLines] AS l
                              JOIN [Payroll].[PayrollRuns] AS pr ON pr.PayrollRunId = l.PayrollRunId
                              WHERE l.EmployeePayItemId = i.EmployeePayItemId AND l.Deleted = 0 AND pr.Deleted = 0
                                AND pr.Stage NOT IN ('DRAFT', 'CANCELLED')) THEN 1 ELSE 0 END
    FROM    [Payroll].[EmployeePayItems] AS i
    WHERE   i.EmployeeId = @Emp AND i.Deleted = 0 AND i.SourceRef IN (@RefU, @RefC);

    /* the cash recovery stays while the leave is not approved (the cash was paid) */
    DECLARE @Redo TABLE (ItemId BIGINT PRIMARY KEY, Amount DECIMAL(12, 3));
    INSERT INTO @Redo (ItemId, Amount)
    SELECT ItemId, Amount FROM @Items
    WHERE  Locked = 0 AND (Ref = @RefU OR (Ref = @RefC AND @Status = 'APPROVED'));

    UPDATE i SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
    FROM   [Payroll].[EmployeePayItems] AS i JOIN @Redo AS x ON x.ItemId = i.EmployeePayItemId;
    INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, OldAmount, NewAmount, Comment, ActionBy)
    SELECT x.ItemId, @Emp, 'DELETED', 2, x.Amount, NULL, CONCAT(N'Leave ', @No, N' changed'), @UserId FROM @Redo AS x;

    IF @Status <> 'APPROVED' RETURN;

    /* the leave days of each month; the unpaid ones are the last days */
    DECLARE @UnpaidTotal DECIMAL(6, 2) = CASE WHEN @PayType = 'UNPAID' THEN @Days ELSE @Unpaid END;
    DECLARE @M TABLE (MonthStart DATE PRIMARY KEY, Days DECIMAL(6, 2), Unpaid DECIMAL(6, 2) NULL, Paid DECIMAL(6, 2) NULL, PayMonth DATE NULL);
    ;WITH m AS (
        SELECT DATEFROMPARTS(YEAR(@Start), MONTH(@Start), 1) AS ms
        UNION ALL
        SELECT DATEADD(MONTH, 1, ms) FROM m WHERE DATEADD(MONTH, 1, ms) <= @Last
    )
    INSERT INTO @M (MonthStart, Days)
    SELECT ms, [Leave].[fn_LeaveDays](@Co, @Type, CASE WHEN ms > @Start THEN ms ELSE @Start END,
                                      CASE WHEN EOMONTH(ms) < @Last THEN EOMONTH(ms) ELSE @Last END,
                                      CASE WHEN @Start = @Last THEN @Half ELSE 0 END)
    FROM   m
    OPTION (MAXRECURSION 30);

    UPDATE x
       SET Unpaid = CASE WHEN a.Later >= @UnpaidTotal THEN 0
                         WHEN a.Later + x.Days <= @UnpaidTotal THEN x.Days
                         ELSE @UnpaidTotal - a.Later END
    FROM   @M AS x
    CROSS APPLY (SELECT ISNULL(SUM(y.Days), 0) AS Later FROM @M AS y WHERE y.MonthStart > x.MonthStart) AS a;
    UPDATE @M SET Paid = Days - Unpaid;

    /* the payroll month: a month whose payroll is waiting for approval or closed
       for the employee moves the item on to the next month */
    UPDATE x
       SET PayMonth = (SELECT MIN(c.mo)
                       FROM   (SELECT DATEADD(MONTH, v.n, x.MonthStart) AS mo
                               FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS v(n)) AS c
                       WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] AS re
                                          JOIN [Payroll].[PayrollRuns] AS pr ON pr.PayrollRunId = re.PayrollRunId
                                          WHERE re.EmployeeId = @Emp AND re.Deleted = 0 AND pr.Deleted = 0 AND pr.RunType = 'REGULAR'
                                            AND pr.RunMonth = c.mo AND pr.Stage IN ('AWAITING_APPROVAL', 'CLOSED')))
    FROM   @M AS x;
    UPDATE @M SET PayMonth = MonthStart WHERE PayMonth IS NULL;

    DECLARE @Rate DECIMAL(12, 3), @Divisor DECIMAL(5, 2);
    SELECT @Rate = p.DailyRate, @Divisor = p.Divisor FROM [Leave].[tvf_PayRate](@Emp, DATEFROMPARTS(YEAR(@Start), MONTH(@Start), 1)) AS p;

    /* the pay components (added when a company does not have them yet) */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @Co AND Deleted = 0 AND SystemCode = 'UNPAID_LEAVE')
       AND OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @Co, @UserId = @UserId;
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @Co AND Deleted = 0 AND (SystemCode = 'LEAVE_ADVANCE' OR ComponentCode = N'LEAVE_ADV'))
        INSERT INTO [Payroll].[PayComponents]
            (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod,
             IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, SystemCode, IsSystem, IsActive, CreatedBy)
        VALUES (@Co, N'LEAVE_ADV', N'Leave Salary Advance', N'سلفة راتب الإجازة', N'Leave Salary Advance', 'DEDUCTION', 'VARIABLE', 'SYSTEM',
                0, 0, 1, 245, 'LEAVE_ADVANCE', 1, 1, @UserId);

    DECLARE @CompU INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents]
                          WHERE CompanyId = @Co AND Deleted = 0 AND SystemCode = 'UNPAID_LEAVE' ORDER BY PayComponentId);
    DECLARE @CompC INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents]
                          WHERE CompanyId = @Co AND Deleted = 0 AND (SystemCode = 'LEAVE_ADVANCE' OR ComponentCode = N'LEAVE_ADV')
                          ORDER BY CASE WHEN SystemCode = 'LEAVE_ADVANCE' THEN 0 ELSE 1 END, PayComponentId);

    DECLARE @New TABLE (ItemId BIGINT, Amount DECIMAL(12, 3), Comment NVARCHAR(500));

    /* unpaid days (not again for a month a payroll has already deducted) */
    IF @CompU IS NOT NULL AND @UnpaidTotal > 0 AND ISNULL(@Rate, 0) > 0
        INSERT INTO [Payroll].[EmployeePayItems]
            (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, SourceRef, CreatedBy,
             ApprovalLevel, SubmittedBy, SubmittedDate)
        OUTPUT inserted.EmployeePayItemId, inserted.Amount, inserted.Comment INTO @New (ItemId, Amount, Comment)
        SELECT  @Co, @Emp, @CompU, ROUND(x.Unpaid * @Rate, 3), 'ONCE', x.PayMonth,
                CONCAT(N'Unpaid leave ', @No, N': ', FORMAT(x.Unpaid, '0.##', 'en-US'), N' days in ', FORMAT(x.MonthStart, 'MMM yyyy', 'en-US'),
                       N' x ', FORMAT(@Rate, '0.000', 'en-US'), N' (monthly salary / ', FORMAT(@Divisor, '0.##', 'en-US'), N')'),
                'ACTIVE', @RefU, @UserId, 2, @UserId, @Now
        FROM    @M AS x
        WHERE   x.Unpaid > 0 AND ROUND(x.Unpaid * @Rate, 3) > 0
          AND   NOT EXISTS (SELECT 1 FROM @Items AS k WHERE k.Ref = @RefU AND k.Locked = 1
                                                    AND k.StartMonth BETWEEN x.MonthStart AND x.PayMonth);

    /* the leave salary paid in cash: recovered from the leave month(s), by paid days
       (not again once a payroll has started to recover it) */
    DECLARE @PaidTotal DECIMAL(9, 2) = (SELECT SUM(Paid) FROM @M);
    IF @CompC IS NOT NULL AND @Mode = 'CASH' AND @Cash > 0
       AND NOT EXISTS (SELECT 1 FROM @Items WHERE Ref = @RefC AND Locked = 1)
    BEGIN
        IF ISNULL(@PaidTotal, 0) <= 0
            UPDATE @M SET Paid = CASE WHEN MonthStart = (SELECT MIN(MonthStart) FROM @M) THEN 1 ELSE 0 END;
        SET @PaidTotal = (SELECT SUM(Paid) FROM @M);

        ;WITH a AS (
            SELECT  x.MonthStart, x.PayMonth, x.Paid,
                    ROUND(@Cash * x.Paid / @PaidTotal, 3) AS Share,
                    ROW_NUMBER() OVER (ORDER BY x.MonthStart DESC) AS rn
            FROM    @M AS x
            WHERE   x.Paid > 0
        ), b AS (
            SELECT  a.*, CASE WHEN a.rn = 1
                              THEN @Cash - ISNULL((SELECT SUM(z.Share) FROM a AS z WHERE z.rn > 1), 0)
                              ELSE a.Share END AS Amount
            FROM    a
        )
        INSERT INTO [Payroll].[EmployeePayItems]
            (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, SourceRef, CreatedBy,
             ApprovalLevel, SubmittedBy, SubmittedDate)
        OUTPUT inserted.EmployeePayItemId, inserted.Amount, inserted.Comment INTO @New (ItemId, Amount, Comment)
        SELECT  @Co, @Emp, @CompC, b.Amount, 'ONCE', b.PayMonth,
                CONCAT(N'Leave salary of ', @No, N' paid in cash before the leave - ', FORMAT(b.MonthStart, 'MMM yyyy', 'en-US'), N' share'),
                'ACTIVE', @RefC, @UserId, 2, @UserId, @Now
        FROM    b
        WHERE   b.Amount > 0;
    END;

    INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, OldAmount, NewAmount, Comment, ActionBy)
    SELECT n.ItemId, @Emp, 'CREATED', 2, NULL, n.Amount, n.Comment, @UserId FROM @New AS n;
END;
GO

/* ------------------------------------------------------------------
   6. Leave.tvf_Balances (db/82) - the paid days only
   ------------------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[tvf_Balances]
(
    @AsOf        DATE,
    @EmployeeId  BIGINT        -- NULL = every employee
)
RETURNS TABLE
AS
RETURN
/* db/86: Taken / Pending count the paid days only - the days over the balance
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
                    WHERE a.EmployeeId = et.EmployeeId AND a.LeaveTypeId = et.LeaveTypeId AND a.EntryType = 'ADJUST'
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

/* ------------------------------------------------------------------
   7. Leave.usp_LeaveRequest_Manage (db/69) + unpaid days, resume date,
      SETTLEMENT / SETTLE / PAY_ITEMS
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveRequest_Manage]
    @Action            VARCHAR(20),
    @Id                BIGINT          = NULL,
    @CompanyId         INT             = NULL,
    @CompanyIds        NVARCHAR(2000)  = NULL,
    /* LIST filters */
    @StatusFilter      VARCHAR(12)     = NULL,     -- PENDING, APPROVED, REJECTED, CANCELLED, MINE (waiting for me), ALL
    @LeaveTypeId       INT             = NULL,
    @EmployeeId        BIGINT          = NULL,
    @FromDate          DATE            = NULL,
    @ToDate            DATE            = NULL,
    @Search            NVARCHAR(200)   = NULL,
    @SelfOnly          BIT             = 0,        -- My Leave: only @SelfEmployeeId's own requests
    @SelfEmployeeId    BIGINT          = NULL,     -- the signed-in user's employee
    @TeamOnly          BIT             = 0,        -- My Leave > team: requests waiting for the user as line manager
    @PageNumber        INT             = 1,
    @PageSize          INT             = 25,
    /* SAVE */
    @StartDate         DATE            = NULL,
    @EndDate           DATE            = NULL,
    @HalfDay           BIT             = 0,
    @Reason            NVARCHAR(500)   = NULL,
    @DocumentPath      NVARCHAR(400)   = NULL,
    @DocumentName      NVARCHAR(260)   = NULL,
    @DocumentType      NVARCHAR(100)   = NULL,
    @DocumentSize      BIGINT          = NULL,
    @IsHr              BIT             = 0,        -- entered / handled by HR (LEAVE_MANAGE): no notice rule
    @ApproveNow        BIT             = 0,        -- HR with the final approval right: approved at once
    /* decisions */
    @Comment           NVARCHAR(500)   = NULL,
    @ExpectedLevel     TINYINT         = NULL,
    @CanApproveL1      BIT             = 0,
    @CanApproveL2      BIT             = 0,
    @AllowSelf         BIT             = 0,
    @ReturnDate        DATE            = NULL,
    /* db/86 */
    @ResumeDate        DATE            = NULL,     -- back at work: for reference only, no effect on the balance
    @AcceptUnpaid      BIT             = 0,        -- the days over the balance are taken unpaid (asked first)
    @SettlementMode    VARCHAR(10)     = NULL,     -- SETTLE: PAYROLL (with the monthly salary) or CASH (paid before the leave)
    @SettlementAmount  DECIMAL(12, 3)  = NULL,     -- SETTLE CASH: blank = paid days x daily leave salary
    @SettlementDate    DATE            = NULL,     -- SETTLE CASH: the day the cash is paid
    @UserId            BIGINT          = NULL,

    @TotalCount        INT             = NULL OUTPUT,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* the employees the user may see: own company / top-bar filter; My Leave: only their own */
    DECLARE @MyEmployee BIGINT = (SELECT TOP (1) u.EmployeeId FROM [Security].[Users] u WHERE u.UserId = @UserId AND u.Deleted = 0);

    /* ======================= EMPLOYEES (pickers) ================== */
    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, e.CompanyId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName, e.Gender, e.HireDate
        FROM    [Employee].[Employees] AS e
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0
          AND   NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
        ORDER BY e.FirstName, e.LastName;
        RETURN;
    END;

    /* ======================= TYPES (for one employee) ============= */
    IF @Action = 'TYPES'
    BEGIN
        SELECT  t.LeaveTypeId, t.CompanyId, t.TypeCode, t.TypeName, t.ArabicName, t.Category, t.BalanceMode, t.PayType, t.CountMode,
                t.AllowHalfDay, t.RequiresDocument, t.MinNoticeDays, t.MaxDaysPerRequest, t.Color, t.EligibleAfterMonths,
                b.Entitled, b.Taken, b.Pending, b.Available
        FROM    [Employee].[Employees] AS e
        JOIN    [Leave].[LeaveTypes] AS t ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
                                         AND (t.Gender IS NULL OR t.Gender = e.Gender)
        LEFT JOIN [Leave].[tvf_Balances](ISNULL(@StartDate, @Today), @EmployeeId) AS b ON b.LeaveTypeId = t.LeaveTypeId
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0
        ORDER BY t.SortOrder, t.TypeName;
        RETURN;
    END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN @PageSize < 1 THEN 25 WHEN @PageSize > 1000 THEN 1000 ELSE @PageSize END;

        ;WITH x AS (
            SELECT  r.LeaveRequestId, r.RequestNo, r.CompanyId, co.CompanyName, r.EmployeeId,
                    ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                    LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                    d.DepartmentName,
                    r.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category,
                    r.StartDate, r.EndDate, r.ActualEndDate, r.ActualReturnDate, r.HalfDay, r.Days, r.PlannedDays, r.Status, r.ApprovalLevel,
                    r.Reason, r.ManagerUserId, r.CreatedDate, r.CreatedBy, r.EnteredByHr,
                    CASE WHEN r.DocumentPath IS NULL THEN 0 ELSE 1 END AS HasDocument,
                    u.EmployeeId AS SubmitterEmployeeId,
                    r.UnpaidDays, r.ResumeDate, r.SettlementMode, t.PayType
            FROM    [Leave].[LeaveRequests] AS r
            JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
            JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
            LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = r.CompanyId
            LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
            LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
            WHERE   r.Deleted = 0
              AND   (@SelfOnly = 1 OR @TeamOnly = 1
                     OR ((@CompanyId IS NULL OR r.CompanyId = @CompanyId)
                         AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)))
              AND   (@SelfOnly = 0 OR r.EmployeeId = @SelfEmployeeId)
              AND   (@TeamOnly = 0 OR (e.ReportingManagerId = @MyEmployee AND @MyEmployee IS NOT NULL))
              AND   (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId)
              AND   (@LeaveTypeId IS NULL OR r.LeaveTypeId = @LeaveTypeId)
              AND   (@FromDate IS NULL OR ISNULL(r.ActualEndDate, r.EndDate) >= @FromDate)
              AND   (@ToDate IS NULL OR r.StartDate <= @ToDate)
              AND   (ISNULL(@StatusFilter, 'ALL') = 'ALL'
                     OR (@StatusFilter = 'MINE' AND r.Status = 'PENDING'
                         AND ((r.ApprovalLevel = 1 AND (r.ManagerUserId = @UserId OR @CanApproveL1 = 1))
                              OR (r.ApprovalLevel = 2 AND @CanApproveL2 = 1)))
                     OR (@StatusFilter = 'ONLEAVE' AND r.Status = 'APPROVED' AND @Today BETWEEN r.StartDate AND ISNULL(r.ActualEndDate, r.EndDate))
                     OR (@StatusFilter = 'UPCOMING' AND r.Status = 'APPROVED' AND r.StartDate > @Today AND r.StartDate <= DATEADD(DAY, 7, @Today))   -- the next 7 days, as the "Starting soon" figure
                     /* db/86: a returned leave is no longer "approved" - it has its own filter */
                     OR (@StatusFilter = 'APPROVED' AND r.Status = 'APPROVED' AND r.ActualReturnDate IS NULL)
                     OR (@StatusFilter = 'RETURNED' AND r.Status = 'APPROVED' AND r.ActualReturnDate IS NOT NULL)
                     OR (@StatusFilter = 'DUEBACK' AND r.Status = 'APPROVED' AND r.ActualReturnDate IS NULL
                         AND ISNULL(r.ActualEndDate, r.EndDate) < @Today AND ISNULL(r.ActualEndDate, r.EndDate) >= DATEADD(DAY, -30, @Today))
                     OR (@StatusFilter IN ('PENDING', 'REJECTED', 'CANCELLED') AND r.Status = @StatusFilter))
              AND   (@Search IS NULL OR r.RequestNo LIKE N'%' + @Search + N'%' OR e.FirstName LIKE N'%' + @Search + N'%'
                     OR e.LastName LIKE N'%' + @Search + N'%' OR e.EmployeeCode LIKE N'%' + @Search + N'%'
                     OR e.EmployeeNo LIKE N'%' + @Search + N'%' OR t.TypeName LIKE N'%' + @Search + N'%')
        )
        SELECT  *, COUNT(1) OVER () AS TotalRows
        INTO    #List
        FROM    x;

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #List;
        SELECT  LeaveRequestId, RequestNo, CompanyId, CompanyName, EmployeeId, EmployeeNo, EmployeeName, EmployeeArabicName, DepartmentName,
                LeaveTypeId, TypeName, TypeArabicName, Color, Category, StartDate, EndDate, ActualEndDate, ActualReturnDate, HalfDay, Days, PlannedDays,
                Status, ApprovalLevel, Reason, ManagerUserId, CreatedDate, CreatedBy, EnteredByHr, HasDocument, SubmitterEmployeeId,
                UnpaidDays, ResumeDate, SettlementMode, PayType
        FROM    #List
        ORDER BY CASE WHEN Status = 'PENDING' THEN 0 ELSE 1 END, StartDate DESC, LeaveRequestId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  r.LeaveRequestId, r.RequestNo, r.CompanyId, co.CompanyName, r.EmployeeId,
                ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                d.DepartmentName, e.ReportingManagerId,
                r.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.CountMode, t.AllowHalfDay, t.RequiresDocument,
                r.StartDate, r.EndDate, r.ActualEndDate, r.ActualReturnDate, r.HalfDay, r.Days, r.PlannedDays, r.Status, r.ApprovalLevel,
                r.Reason, r.ManagerUserId, r.ManagerApprovedBy, r.ManagerApprovedDate, r.DecidedBy, r.DecidedDate, r.DecisionComment,
                r.CancelledBy, r.CancelledDate, r.DocumentName, r.DocumentType, r.DocumentSize, r.DocumentPath,
                CASE WHEN r.DocumentPath IS NULL THEN 0 ELSE 1 END AS HasDocument,
                r.EnteredByHr, r.CreatedBy, r.CreatedDate,
                cu.Username AS CreatedByName, mu.Username AS ManagerName, du.Username AS DecidedByName,
                LTRIM(RTRIM(CONCAT(me.FirstName, N' ', me.LastName))) AS ManagerEmployeeName,
                cu.EmployeeId AS SubmitterEmployeeId,
                r.UnpaidDays, r.ResumeDate, t.PayType, t.BalanceMode,
                r.SettlementMode, r.SettlementAmount, r.SettlementDailyRate, r.SettlementDate, r.SettlementRemarks,
                r.SettledBy, su.Username AS SettledByName, r.SettledDate
        FROM    [Leave].[LeaveRequests] AS r
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = r.CompanyId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Employee].[Employees] AS me ON me.EmployeeId = e.ReportingManagerId
        LEFT JOIN [Security].[Users] AS cu ON cu.UserId = r.CreatedBy
        LEFT JOIN [Security].[Users] AS mu ON mu.UserId = r.ManagerUserId
        LEFT JOIN [Security].[Users] AS du ON du.UserId = r.DecidedBy
        LEFT JOIN [Security].[Users] AS su ON su.UserId = r.SettledBy
        WHERE   r.LeaveRequestId = @Id AND r.Deleted = 0;
        RETURN;
    END;

    IF @Action = 'HISTORY'
    BEGIN
        SELECT  h.HistoryId, h.ActionCode, h.ActionBy, u.Username AS ActionByName, h.ActionDate, h.Comment
        FROM    [Leave].[LeaveRequestHistory] AS h
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        WHERE   h.LeaveRequestId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate, h.HistoryId;
        RETURN;
    END;

    /* ======================= SUMMARY (KPIs, Dashboard) ============ */
    IF @Action = 'SUMMARY'
    BEGIN
        DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@FromDate, @Today)), MONTH(ISNULL(@FromDate, @Today)), 1);
        DECLARE @MonthEnd DATE = EOMONTH(@MonthStart);
        ;WITH r AS (
            SELECT  q.*, t.Category, ISNULL(q.ActualEndDate, q.EndDate) AS LastDay
            FROM    [Leave].[LeaveRequests] AS q
            JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = q.LeaveTypeId
            JOIN    [Employee].[Employees] AS e ON e.EmployeeId = q.EmployeeId AND e.Deleted = 0
            WHERE   q.Deleted = 0
              AND   (@CompanyId IS NULL OR q.CompanyId = @CompanyId)
              AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(q.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
        )
        SELECT
            PendingTotal      = (SELECT COUNT(1) FROM r WHERE Status = 'PENDING'),
            PendingForMe      = (SELECT COUNT(1) FROM r WHERE Status = 'PENDING'
                                  AND ((ApprovalLevel = 1 AND (ManagerUserId = @UserId OR @CanApproveL1 = 1)) OR (ApprovalLevel = 2 AND @CanApproveL2 = 1))),
            OnLeaveToday      = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND @Today BETWEEN StartDate AND LastDay),
            StartingThisWeek  = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND StartDate > @Today AND StartDate <= DATEADD(DAY, 7, @Today)),
            ApprovedThisMonth = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            /* employees on leave in the month, by kind (Dashboard) */
            AnnualInMonth     = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'ANNUAL' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            SickInMonth       = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'SICK' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            EmergencyInMonth  = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'EMERGENCY' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            OtherInMonth      = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category NOT IN ('ANNUAL', 'SICK', 'EMERGENCY') AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            DueBack           = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND ActualReturnDate IS NULL AND LastDay < @Today AND LastDay >= DATEADD(DAY, -30, @Today));
        RETURN;
    END;

    /* ======================= PREVIEW / SAVE ======================= */
    IF @Action IN ('PREVIEW', 'SAVE')
    BEGIN
        DECLARE @eCo INT, @eHire DATE, @eGender CHAR(1), @eStatus NVARCHAR(20), @eMgr BIGINT, @eDel BIT;
        DECLARE @old_Status VARCHAR(12), @old_Employee BIGINT, @old_Doc NVARCHAR(400), @old_Creator BIGINT;
        IF @Id > 0
        BEGIN
            SELECT @old_Status = Status, @old_Employee = EmployeeId, @old_Doc = DocumentPath, @old_Creator = CreatedBy
            FROM [Leave].[LeaveRequests] WHERE LeaveRequestId = @Id AND Deleted = 0;
            IF @old_Status IS NULL
            BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That request was not found.'; RETURN; END;
            IF @old_Status <> 'PENDING'
            BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'Only a pending request can be changed.'; RETURN; END;
            SET @EmployeeId = @old_Employee;
        END;

        SELECT @eCo = e.CompanyId, @eHire = e.HireDate, @eGender = e.Gender, @eStatus = e.EmploymentStatus,
               @eMgr = e.ReportingManagerId, @eDel = CASE WHEN e.Deleted = 1 OR e.IsDeleted = 1 THEN 1 ELSE 0 END
        FROM   [Employee].[Employees] AS e WHERE e.EmployeeId = @EmployeeId;

        IF @eCo IS NULL OR @eDel = 1
           OR (@IsHr = 1 AND ((@CompanyId IS NOT NULL AND @eCo <> @CompanyId)
                              OR (@CompanyIds IS NOT NULL AND CHARINDEX(N',' + CAST(@eCo AS NVARCHAR(12)) + N',', @Csv) = 0)))
           OR (@IsHr = 0 AND (@MyEmployee IS NULL OR @EmployeeId <> @MyEmployee))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee.'; RETURN; END;

        DECLARE @tCo INT, @tActive BIT, @tGender CHAR(1), @tHalf BIT, @tMode VARCHAR(10), @tNeg BIT, @tNotice SMALLINT, @tMax SMALLINT,
                @tElig SMALLINT, @tName NVARCHAR(100);
        SELECT @tCo = CompanyId, @tActive = IsActive, @tGender = Gender, @tHalf = AllowHalfDay, @tMode = BalanceMode, @tNeg = AllowNegative,
               @tNotice = MinNoticeDays, @tMax = MaxDaysPerRequest, @tElig = EligibleAfterMonths, @tName = TypeName
        FROM   [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND Deleted = 0;

        IF @tCo IS NULL OR @tCo <> @eCo OR @tActive = 0 OR (@tGender IS NOT NULL AND @tGender <> ISNULL(@eGender, ''))
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'This leave type is not available for the employee.'; RETURN; END;
        IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the first and last day of the leave.'; RETURN; END;
        IF DATEDIFF(DAY, @StartDate, @EndDate) > 365
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A leave can be at most one year long.'; RETURN; END;
        IF ISNULL(@HalfDay, 0) = 1 AND (@tHalf = 0 OR @StartDate <> @EndDate)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A half day is a single day, for a leave type that allows it.'; RETURN; END;

        DECLARE @Days DECIMAL(6, 2) = [Leave].[fn_LeaveDays](@eCo, @LeaveTypeId, @StartDate, @EndDate, ISNULL(@HalfDay, 0));

        DECLARE @bEntitled DECIMAL(9, 2), @bTaken DECIMAL(9, 2), @bPending DECIMAL(9, 2), @bAvail DECIMAL(9, 2);
        SELECT @bEntitled = b.Entitled, @bTaken = b.Taken, @bAvail = b.Available,
               @bPending = b.Pending - ISNULL((SELECT r.Days - r.UnpaidDays FROM [Leave].[LeaveRequests] r WHERE r.LeaveRequestId = @Id AND r.Status = 'PENDING' AND r.Deleted = 0
                                               AND r.StartDate BETWEEN b.WinStart AND b.WinEnd), 0)
        FROM   [Leave].[tvf_Balances](@StartDate, @EmployeeId) AS b
        WHERE  b.LeaveTypeId = @LeaveTypeId;

        /* the problems, worst first; PREVIEW shows them all, SAVE stops at the first */
        DECLARE @Problems TABLE (Seq INT IDENTITY(1, 1), Code VARCHAR(40), Message NVARCHAR(400));
        IF @Days <= 0
            INSERT INTO @Problems VALUES ('NO_DAYS', N'These dates have no working days to take (weekend or public holiday).');
        IF EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] r
                   WHERE r.EmployeeId = @EmployeeId AND r.Deleted = 0 AND r.Status IN ('PENDING', 'APPROVED') AND r.LeaveRequestId <> ISNULL(@Id, 0)
                     AND r.StartDate <= @EndDate AND ISNULL(r.ActualEndDate, r.EndDate) >= @StartDate)
            INSERT INTO @Problems VALUES ('OVERLAP', N'The employee already has a leave on some of these days.');
        IF @tElig > 0 AND @eHire IS NOT NULL AND DATEADD(MONTH, @tElig, @eHire) > @StartDate
            INSERT INTO @Problems VALUES ('NOT_ELIGIBLE', CONCAT(N'Not eligible yet: this leave can be taken from ',
                                                                 FORMAT(DATEADD(MONTH, @tElig, @eHire), 'dd MMM yyyy', 'en-US'), N'.'));
        IF @tMax IS NOT NULL AND @Days > @tMax
            INSERT INTO @Problems VALUES ('TOO_LONG', CONCAT(N'At most ', @tMax, N' days per request for this leave type.'));
        /* db/86: more days than the balance is no longer refused - the days over it are
           unpaid (the employee is asked to confirm them, see SAVE) */
        DECLARE @Free DECIMAL(9, 2) = ISNULL(@bAvail, 0) - ISNULL(@bPending, 0);
        IF @Free < 0 SET @Free = 0;
        DECLARE @Unpaid DECIMAL(6, 2) = CASE WHEN @tMode <> 'UNLIMITED' AND @tNeg = 0 AND @Days > @Free THEN @Days - @Free ELSE 0 END;

        /* db/86: the day the employee is back at work - for reference only (the
           manager sees it); blank = the next working day after the leave */
        DECLARE @Resume DATE = ISNULL(@ResumeDate, [Leave].[fn_ResumeDate](@eCo, @EndDate, ISNULL(@HalfDay, 0)));
        IF @ResumeDate IS NOT NULL
           AND (@ResumeDate < @EndDate OR (@ResumeDate = @EndDate AND ISNULL(@HalfDay, 0) = 0) OR DATEDIFF(DAY, @EndDate, @ResumeDate) > 90)
            INSERT INTO @Problems VALUES ('RESUME', N'The resume date must be after the last day of the leave.');
        IF ISNULL(@IsHr, 0) = 0 AND @tNotice > 0 AND DATEDIFF(DAY, @Today, @StartDate) < @tNotice
            INSERT INTO @Problems VALUES ('NOTICE', CONCAT(N'This leave needs ', @tNotice, N' days notice.'));

        IF @Action = 'PREVIEW'
        BEGIN
            SELECT @Days AS Days, @bEntitled AS Entitled, @bTaken AS Taken, @bPending AS Pending, @bAvail AS Available,
                   CASE WHEN @tMode = 'UNLIMITED' THEN NULL ELSE ISNULL(@bAvail, 0) - ISNULL(@bPending, 0) - (@Days - @Unpaid) END AS After,
                   @Days - @Unpaid AS PaidDays, @Unpaid AS UnpaidDays, @Resume AS ResumeDate,
                   (SELECT STRING_AGG(Message, N'|') WITHIN GROUP (ORDER BY Seq) FROM @Problems) AS Problems;
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM @Problems)
        BEGIN
            SELECT TOP (1) @ResultCode = Code, @ResultMessage = Message FROM @Problems ORDER BY Seq;
            RETURN;
        END;

        /* db/86: days over the balance go only with the employee's consent */
        IF @Unpaid > 0 AND ISNULL(@AcceptUnpaid, 0) = 0
        BEGIN
            SELECT @ResultCode = 'UNPAID_CONFIRM',
                   @ResultMessage = CONCAT(N'Only ', FORMAT(@Days - @Unpaid, '0.##', 'en-US'), N' of the ', FORMAT(@Days, '0.##', 'en-US'),
                                           N' days are covered by the balance - the other ', FORMAT(@Unpaid, '0.##', 'en-US'),
                                           N' days are unpaid. Confirm to send the request.');
            RETURN;
        END;

        /* who approves: the line manager first (company setting, a manager with a user account who is not the submitter) */
        DECLARE @MgrUser BIGINT = NULL, @NeedMgr BIT = ISNULL((SELECT ManagerApproval FROM [Leave].[Settings] WHERE CompanyId = @eCo AND Deleted = 0), 1);
        IF @NeedMgr = 1 AND @eMgr IS NOT NULL
            SET @MgrUser = (SELECT TOP (1) u.UserId FROM [Security].[Users] u
                            WHERE u.EmployeeId = @eMgr AND u.Deleted = 0 AND u.IsActive = 1 ORDER BY u.UserId);
        DECLARE @Level TINYINT = CASE WHEN @MgrUser IS NOT NULL AND @MgrUser <> ISNULL(@UserId, 0) THEN 1 ELSE 2 END;
        DECLARE @Final BIT = CASE WHEN ISNULL(@ApproveNow, 0) = 1 AND @IsHr = 1 AND @CanApproveL2 = 1
                                       AND (@EmployeeId <> ISNULL(@MyEmployee, 0) OR @AllowSelf = 1) THEN 1 ELSE 0 END;

        BEGIN TRANSACTION;
        IF @Id > 0
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET LeaveTypeId = @LeaveTypeId, StartDate = @StartDate, EndDate = @EndDate, HalfDay = ISNULL(@HalfDay, 0),
                   Days = @Days, PlannedDays = @Days, Reason = @Reason,
                   UnpaidDays = @Unpaid, ResumeDate = @Resume,
                   Status = CASE WHEN @Final = 1 THEN 'APPROVED' ELSE 'PENDING' END,
                   ApprovalLevel = @Level, ManagerUserId = @MgrUser, ManagerApprovedBy = NULL, ManagerApprovedDate = NULL,
                   DecidedBy = CASE WHEN @Final = 1 THEN @UserId END, DecidedDate = CASE WHEN @Final = 1 THEN @Now END,
                   DocumentPath = ISNULL(@DocumentPath, DocumentPath), DocumentName = ISNULL(@DocumentName, DocumentName),
                   DocumentType = ISNULL(@DocumentType, DocumentType), DocumentSize = ISNULL(@DocumentSize, DocumentSize),
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
            VALUES (@Id, 'EDITED', @UserId, CONCAT(FORMAT(@StartDate, 'dd/MM/yyyy', 'en-US'), N' - ', FORMAT(@EndDate, 'dd/MM/yyyy', 'en-US'),
                                                   N' (', FORMAT(@Days, '0.##', 'en-US'), N')'));
        END
        ELSE
        BEGIN
            DECLARE @Year INT = YEAR(@StartDate);
            DECLARE @Seq INT = ISNULL((SELECT MAX(TRY_CAST(RIGHT(RequestNo, 5) AS INT)) FROM [Leave].[LeaveRequests] WITH (UPDLOCK, HOLDLOCK)
                                       WHERE RequestNo LIKE CONCAT('LV-', @Year, '-%')), 0) + 1;
            INSERT INTO [Leave].[LeaveRequests] (RequestNo, CompanyId, EmployeeId, LeaveTypeId, StartDate, EndDate, HalfDay, Days, PlannedDays, Reason,
                   Status, ApprovalLevel, ManagerUserId, DecidedBy, DecidedDate, DocumentPath, DocumentName, DocumentType, DocumentSize,
                   EnteredByHr, CreatedBy, UnpaidDays, ResumeDate)
            VALUES (CONCAT('LV-', @Year, '-', RIGHT(CONCAT('00000', @Seq), 5)), @eCo, @EmployeeId, @LeaveTypeId, @StartDate, @EndDate,
                    ISNULL(@HalfDay, 0), @Days, @Days, @Reason,
                    CASE WHEN @Final = 1 THEN 'APPROVED' ELSE 'PENDING' END, @Level, @MgrUser,
                    CASE WHEN @Final = 1 THEN @UserId END, CASE WHEN @Final = 1 THEN @Now END,
                    @DocumentPath, @DocumentName, @DocumentType, @DocumentSize, ISNULL(@IsHr, 0), @UserId, @Unpaid, @Resume);
            SET @Id = SCOPE_IDENTITY();
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
            VALUES (@Id, 'SUBMITTED', @UserId, @Reason);
        END;
        IF @Unpaid > 0
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
            VALUES (@Id, 'UNPAID', @UserId, CONCAT(FORMAT(@Days - @Unpaid, '0.##', 'en-US'), N' days paid, ',
                                                   FORMAT(@Unpaid, '0.##', 'en-US'), N' days unpaid (agreed by the employee)'));
        IF @Final = 1
        BEGIN
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'APPROVED', @UserId, N'Entered and approved by HR');
            EXEC [Leave].[usp_LeaveRequest_SyncPay] @Id = @Id, @UserId = @UserId;
        END;
        COMMIT;

        SELECT @NewId = @Id,
               @ResultMessage = CASE WHEN @Final = 1 THEN N'Leave request saved and approved.'
                                     WHEN @Level = 1 THEN N'Leave request sent to the line manager for approval.'
                                     ELSE N'Leave request sent to HR for approval.' END;
        RETURN;
    END;

    /* ======================= decisions ============================ */
    DECLARE @rStatus VARCHAR(12), @rLevel TINYINT, @rEmp BIGINT, @rCo INT, @rMgr BIGINT, @rStart DATE, @rEnd DATE, @rType INT, @rHalf BIT, @rCreator BIGINT;
    SELECT @rStatus = Status, @rLevel = ApprovalLevel, @rEmp = EmployeeId, @rCo = CompanyId, @rMgr = ManagerUserId,
           @rStart = StartDate, @rEnd = EndDate, @rType = LeaveTypeId, @rHalf = HalfDay, @rCreator = CreatedBy
    FROM   [Leave].[LeaveRequests] WHERE LeaveRequestId = @Id AND Deleted = 0;

    IF @rStatus IS NULL AND @Action IN ('APPROVE', 'REJECT', 'CANCEL', 'RETURN', 'SETTLEMENT', 'SETTLE', 'PAY_ITEMS')
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That request was not found.'; RETURN; END;

    /* HR actions stay inside the user's companies; a line manager acts on their own team */
    DECLARE @InScope BIT = CASE WHEN (@CompanyId IS NULL OR @rCo = @CompanyId)
                                     AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(@rCo AS NVARCHAR(12)) + N',', @Csv) > 0) THEN 1 ELSE 0 END;

    IF @Action IN ('APPROVE', 'REJECT')
    BEGIN
        IF @rStatus <> 'PENDING'
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'This request has already been decided.'; RETURN; END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @rLevel
        BEGIN SELECT @ResultCode = 'STALE', @ResultMessage = N'Someone else has acted on this request - reload the list.'; RETURN; END;
        IF NOT ((@rLevel = 1 AND (@rMgr = @UserId OR (@CanApproveL1 = 1 AND @InScope = 1)))
                OR (@rLevel = 2 AND @CanApproveL2 = 1 AND @InScope = 1))
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You are not an approver for this step.'; RETURN; END;
        IF @rEmp = ISNULL(@MyEmployee, 0) AND @AllowSelf = 0
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You cannot approve your own leave.'; RETURN; END;
        IF @Action = 'REJECT' AND @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for rejecting.'; RETURN; END;

        BEGIN TRANSACTION;
        IF @Action = 'REJECT'
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET Status = 'REJECTED', DecidedBy = @UserId, DecidedDate = @Now, DecisionComment = @Comment, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'REJECTED', @UserId, @Comment);
            SET @ResultMessage = N'Leave request rejected.';
        END
        ELSE IF @rLevel = 1
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET ApprovalLevel = 2, ManagerApprovedBy = @UserId, ManagerApprovedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'MANAGER_APPROVED', @UserId, @Comment);
            SET @ResultMessage = N'Approved - sent to HR for the final approval.';
        END
        ELSE
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET Status = 'APPROVED', DecidedBy = @UserId, DecidedDate = @Now, DecisionComment = @Comment, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'APPROVED', @UserId, @Comment);
            EXEC [Leave].[usp_LeaveRequest_SyncPay] @Id = @Id, @UserId = @UserId;   -- db/86: unpaid days to the payroll
            SET @ResultMessage = N'Leave request approved.';
        END;
        COMMIT;
        SET @NewId = @Id;
        RETURN;
    END;

    IF @Action = 'CANCEL'
    BEGIN
        IF @rStatus NOT IN ('PENDING', 'APPROVED')
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'This request can no longer be cancelled.'; RETURN; END;
        /* the employee cancels their own request until the leave starts; HR (in scope) at any time */
        IF NOT ((@IsHr = 1 AND @InScope = 1)
                OR (@rEmp = ISNULL(@MyEmployee, 0) AND (@rStatus = 'PENDING' OR @rStart > @Today)))
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only HR can cancel a leave that has started.'; RETURN; END;

        BEGIN TRANSACTION;
        UPDATE [Leave].[LeaveRequests]
           SET Status = 'CANCELLED', CancelledBy = @UserId, CancelledDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE LeaveRequestId = @Id;
        INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'CANCELLED', @UserId, @Comment);
        EXEC [Leave].[usp_LeaveRequest_SyncPay] @Id = @Id, @UserId = @UserId;       -- db/86: the unpaid-days deduction goes
        COMMIT;
        SELECT @NewId = @Id, @ResultMessage = N'Leave request cancelled - the days are back in the balance.';
        RETURN;
    END;

    IF @Action = 'RETURN'
    BEGIN
        IF @rStatus <> 'APPROVED'
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'The return can be recorded for an approved leave only.'; RETURN; END;
        IF NOT (@IsHr = 1 AND @InScope = 1)
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You do not have permission to do this.'; RETURN; END;
        IF @ReturnDate IS NULL OR @ReturnDate <= @rStart OR DATEDIFF(DAY, @rStart, @ReturnDate) > 400
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The return date must be after the first day of the leave.'; RETURN; END;

        DECLARE @ActualEnd DATE = DATEADD(DAY, -1, @ReturnDate);
        DECLARE @ActualDays DECIMAL(6, 2) = [Leave].[fn_LeaveDays](@rCo, @rType, @rStart, @ActualEnd, CASE WHEN @ActualEnd = @rStart THEN @rHalf ELSE 0 END);
        IF @ActualEnd > @rEnd
           AND EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] r
                       WHERE r.EmployeeId = @rEmp AND r.Deleted = 0 AND r.Status IN ('PENDING', 'APPROVED') AND r.LeaveRequestId <> @Id
                         AND r.StartDate <= @ActualEnd AND ISNULL(r.ActualEndDate, r.EndDate) >= @rStart)
        BEGIN SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'The late return runs into another leave of the employee.'; RETURN; END;

        /* db/86: the days are split again - an early return gives back the unpaid days
           first; the days of a late return are paid while the balance lasts */
        DECLARE @OldPaid DECIMAL(9, 2), @rTypeMode VARCHAR(10), @rTypeNeg BIT, @Room DECIMAL(9, 2);
        SELECT @OldPaid = q.Days - q.UnpaidDays, @rTypeMode = t.BalanceMode, @rTypeNeg = t.AllowNegative
        FROM   [Leave].[LeaveRequests] AS q JOIN [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = q.LeaveTypeId
        WHERE  q.LeaveRequestId = @Id;
        SELECT @Room = b.Available - b.Pending FROM [Leave].[tvf_Balances](@rStart, @rEmp) AS b WHERE b.LeaveTypeId = @rType;
        SET @Room = CASE WHEN ISNULL(@Room, 0) > 0 THEN @Room ELSE 0 END + @OldPaid;
        DECLARE @NewUnpaid DECIMAL(6, 2) = CASE WHEN @rTypeMode <> 'UNLIMITED' AND @rTypeNeg = 0 AND @ActualDays > @Room
                                                THEN @ActualDays - @Room ELSE 0 END;

        BEGIN TRANSACTION;
        UPDATE [Leave].[LeaveRequests]
           SET ActualReturnDate = @ReturnDate, ActualEndDate = @ActualEnd, Days = @ActualDays, UnpaidDays = @NewUnpaid,
               ReturnRecordedBy = @UserId, ReturnRecordedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE LeaveRequestId = @Id;
        INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
        VALUES (@Id, 'RETURNED', @UserId,
                CONCAT(N'Back on ', FORMAT(@ReturnDate, 'dd/MM/yyyy', 'en-US'), N' - ', FORMAT(@ActualDays, '0.##', 'en-US'), N' days',
                       CASE WHEN @Comment IS NULL THEN N'' ELSE N' - ' + @Comment END));
        EXEC [Leave].[usp_LeaveRequest_SyncPay] @Id = @Id, @UserId = @UserId;       -- db/86
        COMMIT;
        SELECT @NewId = @Id,
               @ResultMessage = CASE WHEN @ActualEnd < @rEnd THEN N'Early return recorded - the unused days are back in the balance.'
                                     WHEN @ActualEnd > @rEnd THEN N'Late return recorded - the extra days are counted.'
                                     ELSE N'Return to work recorded.' END;
        RETURN;
    END;

    /* ======================= db/86: leave salary settlement ======= */
    IF @Action IN ('SETTLEMENT', 'SETTLE', 'PAY_ITEMS') AND NOT (@IsHr = 1 AND @InScope = 1)
    BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You do not have permission to do this.'; RETURN; END;

    IF @Action = 'PAY_ITEMS'
    BEGIN
        /* the pay items the leave made, and whether a payroll has taken them */
        SELECT  i.EmployeePayItemId, CASE WHEN i.SourceRef LIKE N'%:CASH' THEN 'CASH' ELSE 'UNPAID' END AS Kind,
                c.ComponentName, c.ArabicName AS ComponentArabicName, i.StartMonth, i.Amount, i.Comment,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollRunLines] AS l
                                       JOIN [Payroll].[PayrollRuns] AS pr ON pr.PayrollRunId = l.PayrollRunId
                                       WHERE l.EmployeePayItemId = i.EmployeePayItemId AND l.Deleted = 0 AND pr.Deleted = 0
                                         AND pr.Stage NOT IN ('DRAFT', 'CANCELLED')) THEN 1 ELSE 0 END AS BIT) AS InPayroll
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
        WHERE   i.EmployeeId = @rEmp AND i.Deleted = 0
          AND   i.SourceRef IN (CONCAT(N'LEAVE:', @Id, N':UNPAID'), CONCAT(N'LEAVE:', @Id, N':CASH'))
        ORDER BY i.StartMonth, Kind;
        RETURN;
    END;

    DECLARE @sPaid DECIMAL(9, 2), @sUnpaid DECIMAL(9, 2), @sMonth DATE = DATEFROMPARTS(YEAR(@rStart), MONTH(@rStart), 1);
    SELECT  @sPaid = CASE WHEN t.PayType = 'UNPAID' THEN 0 ELSE q.Days - q.UnpaidDays END,
            @sUnpaid = CASE WHEN t.PayType = 'UNPAID' THEN q.Days ELSE q.UnpaidDays END
    FROM    [Leave].[LeaveRequests] AS q JOIN [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = q.LeaveTypeId
    WHERE   q.LeaveRequestId = @Id;
    DECLARE @sCashTaken BIT = CASE WHEN EXISTS (
                SELECT 1 FROM [Payroll].[EmployeePayItems] AS i
                JOIN   [Payroll].[PayrollRunLines] AS l ON l.EmployeePayItemId = i.EmployeePayItemId AND l.Deleted = 0
                JOIN   [Payroll].[PayrollRuns] AS pr ON pr.PayrollRunId = l.PayrollRunId AND pr.Deleted = 0
                WHERE  i.EmployeeId = @rEmp AND i.Deleted = 0 AND i.SourceRef = CONCAT(N'LEAVE:', @Id, N':CASH')
                  AND  pr.Stage NOT IN ('DRAFT', 'CANCELLED')) THEN 1 ELSE 0 END;

    IF @Action = 'SETTLEMENT'
    BEGIN
        SELECT  q.LeaveRequestId, q.RequestNo, q.Status, q.StartDate, ISNULL(q.ActualEndDate, q.EndDate) AS LastDay, q.Days,
                @sPaid AS PaidDays, @sUnpaid AS UnpaidDays,
                p.MonthlySalary, p.LeaveSalary, p.Divisor, p.DailyRate, p.DailyLeaveRate,
                CAST(ROUND(@sPaid * p.DailyLeaveRate, 3) AS DECIMAL(12, 3)) AS SuggestedAmount,
                CAST(ROUND(@sUnpaid * p.DailyRate, 3) AS DECIMAL(12, 3)) AS UnpaidDeduction,
                q.SettlementMode, q.SettlementAmount, q.SettlementDailyRate, q.SettlementDate, q.SettlementRemarks,
                su.Username AS SettledByName, q.SettledDate, @sCashTaken AS CashInPayroll
        FROM    [Leave].[LeaveRequests] AS q
        CROSS JOIN [Leave].[tvf_PayRate](@rEmp, @sMonth) AS p
        LEFT JOIN [Security].[Users] AS su ON su.UserId = q.SettledBy
        WHERE   q.LeaveRequestId = @Id;
        RETURN;
    END;

    IF @Action = 'SETTLE'
    BEGIN
        IF @rStatus <> 'APPROVED'
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'The leave salary is settled for an approved leave only.'; RETURN; END;
        SET @SettlementMode = UPPER(LTRIM(RTRIM(@SettlementMode)));
        IF @SettlementMode IS NULL OR @SettlementMode NOT IN ('PAYROLL', 'CASH')
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose how the leave salary is paid.'; RETURN; END;
        IF @SettlementMode = 'CASH' AND ISNULL(@sPaid, 0) <= 0
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'This leave has no paid days to pay in cash.'; RETURN; END;

        DECLARE @sRate DECIMAL(12, 3) = (SELECT p.DailyLeaveRate FROM [Leave].[tvf_PayRate](@rEmp, @sMonth) AS p);
        IF @SettlementMode = 'CASH'
            SELECT @SettlementAmount = ISNULL(@SettlementAmount, ROUND(@sPaid * ISNULL(@sRate, 0), 3)),
                   @SettlementDate = ISNULL(@SettlementDate, @Today);
        ELSE
            SELECT @SettlementAmount = NULL, @SettlementDate = NULL;
        IF @SettlementMode = 'CASH' AND (@SettlementAmount <= 0 OR @SettlementAmount > 999999)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the amount paid in cash.'; RETURN; END;

        IF @sCashTaken = 1
           AND EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] WHERE LeaveRequestId = @Id
                         AND (ISNULL(SettlementMode, '') <> @SettlementMode OR ISNULL(SettlementAmount, -1) <> ISNULL(@SettlementAmount, -1)))
        BEGIN
            SELECT @ResultCode = 'LOCKED',
                   @ResultMessage = N'A payroll has already started to recover the cash paid - the settlement can no longer be changed (use Pay Items).';
            RETURN;
        END;

        BEGIN TRANSACTION;
        UPDATE [Leave].[LeaveRequests]
           SET SettlementMode = @SettlementMode, SettlementAmount = @SettlementAmount, SettlementDailyRate = @sRate,
               SettlementDate = @SettlementDate, SettlementRemarks = @Comment, SettledBy = @UserId, SettledDate = @Now,
               ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE LeaveRequestId = @Id;
        INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
        VALUES (@Id, 'SETTLED', @UserId,
                CASE WHEN @SettlementMode = 'CASH'
                     THEN CONCAT(N'Leave salary paid in cash: ', FORMAT(@SettlementAmount, '#,0.000', 'en-US'), N' on ',
                                 FORMAT(@SettlementDate, 'dd/MM/yyyy', 'en-US'), CASE WHEN @Comment IS NULL THEN N'' ELSE N' - ' + @Comment END)
                     ELSE CONCAT(N'Leave salary with the monthly payroll', CASE WHEN @Comment IS NULL THEN N'' ELSE N' - ' + @Comment END) END);
        EXEC [Leave].[usp_LeaveRequest_SyncPay] @Id = @Id, @UserId = @UserId;
        COMMIT;
        SELECT @NewId = @Id,
               @ResultMessage = CASE WHEN @SettlementMode = 'CASH'
                                     THEN N'Settlement saved - the payroll of the leave month recovers the cash paid.'
                                     ELSE N'Settlement saved - the leave salary is paid with the monthly payroll.' END;
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ------------------------------------------------------------------
   8. Leave.usp_LeaveBalance_Manage (db/69) - the ledger shows the paid days
   ------------------------------------------------------------------ */
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
                u.Username AS ByName, l.CreatedDate, NULL AS RequestNo, NULL AS Status
        FROM    [Leave].[LeaveLedger] AS l
        LEFT JOIN [Security].[Users] AS u ON u.UserId = l.CreatedBy
        WHERE   l.EmployeeId = @EmployeeId AND l.LeaveTypeId = @LeaveTypeId AND l.Deleted = 0
        UNION ALL
        SELECT  'REQUEST', r.LeaveRequestId, 'TAKEN', r.StartDate, ISNULL(r.ActualEndDate, r.EndDate), -(r.Days - r.UnpaidDays),
                CASE WHEN r.UnpaidDays > 0   -- db/86: the unpaid days are not taken from the balance
                     THEN CONCAT(r.Reason, CASE WHEN r.Reason IS NULL THEN N'' ELSE N' - ' END,
                                 N'+ ', FORMAT(r.UnpaidDays, '0.##', 'en-US'), N' unpaid days')
                     ELSE r.Reason END,
                u.Username, r.CreatedDate, r.RequestNo, r.Status
        FROM    [Leave].[LeaveRequests] AS r
        LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
        WHERE   r.EmployeeId = @EmployeeId AND r.LeaveTypeId = @LeaveTypeId AND r.Deleted = 0 AND r.Status IN ('APPROVED', 'PENDING')
        ORDER BY OnDate DESC, CreatedDate DESC;
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

/* ------------------------------------------------------------------
   9. right: LEAVE_SETTLE (Security > Create Roles > Leave requests)
      first run: System Administrator and the roles that manage leave
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM [Security].[Permissions] WHERE PermissionCode = 'LEAVE_SETTLE' AND Deleted = 0)
BEGIN
    INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action) VALUES ('LEAVE_SETTLE', 'Leave', 'Settle');

    INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
    SELECT DISTINCT r.RoleId, p.PermissionId
    FROM   [Security].[Roles] AS r
    JOIN   [Security].[Permissions] AS p ON p.PermissionCode = 'LEAVE_SETTLE' AND p.Deleted = 0
    WHERE  r.Deleted = 0
      AND  (r.RoleCode = N'SYSADMIN'
            OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                       WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = 'LEAVE_MANAGE'))
      AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);
    PRINT N'Right LEAVE_SETTLE created (users see it after signing in again).';
END;
GO

SET NOEXEC OFF;
GO
