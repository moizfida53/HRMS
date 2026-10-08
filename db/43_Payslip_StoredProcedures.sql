/* =====================================================================
   43_Payslip_StoredProcedures.sql  -  HRMS Payroll: Payslips
   ---------------------------------------------------------------------
   Run after 42. CREATE OR ALTER - safe to re-run. Then run 44 (labels).

     Payroll.usp_Payslip_Manage
       RUNS          payrolls that have payslips to show (in validation,
                     awaiting approval or closed), newest first, with
                     generated / emailed counts and the payslips still to
                     generate (none yet or outdated)
       SUMMARY       key figures of one payroll's payslips
       LIST          employees of a payroll (or of every payroll, or of a year
                     / month) with their payslip and email status - paged,
                     searchable;
                     @SelfEmployeeId = My Payslips (generated payslips of
                     closed payrolls only)
       GET           the payslip header of one employee in one payroll:
                     company, period, employee, bank, figures
       GENERATE      generate (or regenerate) the payslips of a CLOSED
                     payroll - everyone, one department or chosen employees
       QUEUE_EMAIL   queue payslip emails: every generated payslip not yet
                     sent, or the chosen employees (@Resend = 1: also
                     those already sent)
       VIEWED        the employee opened their payslip in My Payslips
       NAV_COUNTS    the figures next to the Payslips sub-sections in the
                     sidebar: payslips to generate (closed payrolls, not
                     generated or outdated), payslips generated, emails to
                     send (up to date, not sent or failed, with an address)
       EMAIL_CLAIM   (the email sender) take the next queued emails;
                     emails stuck in SENDING for 15 minutes are taken again
       EMAIL_RESULT  (the email sender) record SENT or FAILED

   The figures are always the payroll's own (Payroll.PayrollRunEmployees and
   Payroll.PayrollRunLines - the lines come from usp_PayrollRunEmployee_Manage
   @Action = 'LINES'). A payslip of an employee excluded from the payroll, or
   of an off-cycle payroll with no line for them, does not exist.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[Payslips]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 42 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Payroll].[usp_Payslip_Manage]
    @Action             VARCHAR(20),

    /* scope (the company filter of the signed-in user) */
    @CompanyId          INT             = NULL,
    @CompanyIds         NVARCHAR(2000)  = NULL,

    @Id                 BIGINT          = NULL,     -- PayslipId (VIEWED, EMAIL_RESULT)
    @RunId              BIGINT          = NULL,
    @EmployeeId         BIGINT          = NULL,
    @SelfEmployeeId     BIGINT          = NULL,     -- My Payslips: only this employee's own payslips
    @Year               INT             = NULL,     -- LIST: payrolls of this year
    @RunMonth           DATE            = NULL,     -- LIST: payrolls of this month (period)

    /* LIST */
    @DepartmentId       INT             = NULL,
    @StatusFilter       VARCHAR(20)     = NULL,
    @Search             NVARCHAR(200)   = NULL,
    @PageNumber         INT             = 1,
    @PageSize           INT             = 25,

    /* GENERATE / QUEUE_EMAIL */
    @Template           VARCHAR(10)     = NULL,
    @EmployeeIds        NVARCHAR(MAX)   = NULL,     -- comma separated
    @Resend             BIT             = 0,

    /* EMAIL_RESULT */
    @Success            BIT             = NULL,
    @Error              NVARCHAR(400)   = NULL,

    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    SET @Search       = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @CompanyIds   = NULLIF(LTRIM(RTRIM(@CompanyIds)), N'');
    SET @EmployeeIds  = NULLIF(LTRIM(RTRIM(@EmployeeIds)), N'');
    SET @StatusFilter = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@StatusFilter))), ''), 'ALL');
    SET @Template     = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@Template))), ''), 'BILINGUAL');
    SET @Error        = NULLIF(LTRIM(RTRIM(@Error)), N'');
    SET @PageNumber   = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize     = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 10000 THEN 10000 ELSE @PageSize END;
    IF @RunMonth IS NOT NULL SET @RunMonth = DATEFROMPARTS(YEAR(@RunMonth), MONTH(@RunMonth), 1);

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @CompanyCsv NVARCHAR(2002) = CASE WHEN @CompanyIds IS NULL THEN NULL ELSE ',' + REPLACE(@CompanyIds, ' ', '') + ',' END;

    IF @Action NOT IN ('RUNS', 'SUMMARY', 'LIST', 'GET', 'GENERATE', 'QUEUE_EMAIL', 'VIEWED', 'EMAIL_CLAIM', 'EMAIL_RESULT', 'NAV_COUNTS')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* the chosen employees */
    DECLARE @Picked TABLE (EmployeeId BIGINT PRIMARY KEY);
    IF @EmployeeIds IS NOT NULL
        INSERT INTO @Picked (EmployeeId)
        SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@EmployeeIds, ',') WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

    /* ======================= EMAIL_CLAIM (sender, no scope) ====== */
    IF @Action = 'EMAIL_CLAIM'
    BEGIN
        DECLARE @Claimed TABLE (PayslipId BIGINT PRIMARY KEY);
        DECLARE @Stale DATETIME2(0) = DATEADD(MINUTE, -15, @Now);

        UPDATE TOP (@PageSize) p
           SET EmailStatus = 'SENDING', EmailClaimedDate = @Now
        OUTPUT inserted.PayslipId INTO @Claimed (PayslipId)
        FROM   [Payroll].[Payslips] AS p WITH (ROWLOCK, READPAST, UPDLOCK)
        WHERE  p.Deleted = 0
          AND  (p.EmailStatus = 'QUEUED' OR (p.EmailStatus = 'SENDING' AND p.EmailClaimedDate < @Stale));

        SELECT  p.PayslipId, p.PayslipNo, p.EmailTo, p.Template, p.EmployeeId,
                re.EmployeeName, re.ArabicName, co.CompanyName, r.RunCode, r.RunMonth,
                pc.PayFrequency, pp.PeriodNumber, pp.StartDate, pp.EndDate, pp.PaymentDate
        FROM    @Claimed AS c
        JOIN    [Payroll].[Payslips]            AS p  ON p.PayslipId = c.PayslipId
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = p.RunEmployeeId
        JOIN    [Payroll].[PayrollRuns]         AS r  ON r.PayrollRunId = p.PayrollRunId
        JOIN    [Payroll].[PayrollCalendars]    AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]      AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        JOIN    [Core].[Companies]              AS co ON co.CompanyId = p.CompanyId
        ORDER BY p.PayslipId;
        RETURN;
    END;

    /* ======================= EMAIL_RESULT (sender) =============== */
    IF @Action = 'EMAIL_RESULT'
    BEGIN
        UPDATE [Payroll].[Payslips]
           SET EmailStatus   = CASE WHEN @Success = 1 THEN 'SENT' ELSE 'FAILED' END,
               EmailSentDate = CASE WHEN @Success = 1 THEN @Now ELSE EmailSentDate END,
               EmailError    = CASE WHEN @Success = 1 THEN NULL ELSE ISNULL(@Error, N'The email could not be sent.') END,
               EmailAttempts = CASE WHEN EmailAttempts < 255 THEN EmailAttempts + 1 ELSE EmailAttempts END
        WHERE  PayslipId = @Id AND Deleted = 0 AND EmailStatus = 'SENDING';
        IF @@ROWCOUNT = 0
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This payslip email is no longer being sent.';
        RETURN;
    END;

    /* ======================= NAV_COUNTS (sidebar) =============== */
    IF @Action = 'NAV_COUNTS'
    BEGIN
        SELECT  COUNT(CASE WHEN r.Stage = 'CLOSED' AND (p.PayslipId IS NULL OR p.NetPay <> re.NetPay OR p.GeneratedDate < r.ClosedDate) THEN 1 END) AS ToGenerateCount,
                COUNT(p.PayslipId)                                                                                                   AS GeneratedCount,
                COUNT(CASE WHEN r.Stage = 'CLOSED' AND p.PayslipId IS NOT NULL AND p.EmailStatus IN ('NOT_SENT', 'FAILED')
                                AND p.NetPay = re.NetPay AND (r.ClosedDate IS NULL OR p.GeneratedDate >= r.ClosedDate)
                                AND em.Email IS NOT NULL THEN 1 END)                                                                AS ToEmailCount
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
        JOIN    [Employee].[Employees]          AS e ON e.EmployeeId = re.EmployeeId
        LEFT JOIN [Payroll].[Payslips]          AS p ON p.PayrollRunId = re.PayrollRunId AND p.EmployeeId = re.EmployeeId AND p.Deleted = 0
        CROSS APPLY (SELECT COALESCE(NULLIF(LTRIM(RTRIM(e.WorkEmail)), N''), NULLIF(LTRIM(RTRIM(e.PersonalEmail)), N'')) AS Email) AS em
        WHERE   re.Deleted = 0 AND re.IsExcluded = 0 AND (r.RunType = 'REGULAR' OR re.LineCount > 0)
          AND   r.Deleted = 0 AND r.Stage IN ('VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
          AND   (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);
        RETURN;
    END;

    /* ======================= RUNS ================================ */
    IF @Action = 'RUNS'
    BEGIN
        SELECT TOP (100)
                r.PayrollRunId, r.CompanyId, co.CompanyCode, co.CompanyName, r.RunCode, r.RunType, r.RunMonth, r.Stage, r.ClosedDate,
                pc.CalendarName, pc.ArabicName AS CalendarArabicName, pc.PayFrequency,
                pp.PeriodNumber, pp.StartDate, pp.EndDate, pp.PaymentDate,
                ISNULL(x.EmployeeCount, 0) AS EmployeeCount, ISNULL(x.TotalNet, 0) AS TotalNet,
                ISNULL(s.GeneratedCount, 0) AS GeneratedCount, ISNULL(s.SentCount, 0) AS SentCount,
                ISNULL(x.ToGenerateCount, 0) AS ToGenerateCount
        FROM    [Payroll].[PayrollRuns]      AS r
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]   AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        OUTER APPLY (SELECT COUNT(1) AS EmployeeCount, SUM(re.NetPay) AS TotalNet,
                            /* payslips still to generate: none yet, or outdated (figures changed / reopened) */
                            SUM(t.ToDo) AS ToGenerateCount
                     FROM   [Payroll].[PayrollRunEmployees] AS re
                     LEFT JOIN [Payroll].[Payslips] AS p ON p.PayrollRunId = re.PayrollRunId AND p.EmployeeId = re.EmployeeId AND p.Deleted = 0
                     CROSS APPLY (SELECT CASE WHEN p.PayslipId IS NULL OR p.NetPay <> re.NetPay OR p.GeneratedDate < r.ClosedDate THEN 1 ELSE 0 END AS ToDo) AS t
                     WHERE  re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0 AND re.IsExcluded = 0
                       AND  (r.RunType = 'REGULAR' OR re.LineCount > 0)) AS x
        OUTER APPLY (SELECT COUNT(1) AS GeneratedCount, COUNT(CASE WHEN p.EmailStatus = 'SENT' THEN 1 END) AS SentCount
                     FROM   [Payroll].[Payslips] AS p
                     WHERE  p.PayrollRunId = r.PayrollRunId AND p.Deleted = 0) AS s
        WHERE   r.Deleted = 0 AND r.Stage IN ('VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
          AND   (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0)
        ORDER BY r.RunMonth DESC, r.RunSeq DESC, r.PayrollRunId DESC;
        RETURN;
    END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
        SELECT  r.PayrollRunId, r.RunCode, r.RunMonth, r.Stage, r.CompanyId, co.CompanyName,
                pc.PayFrequency, pp.PeriodNumber, pp.StartDate, pp.EndDate, pp.PaymentDate,
                re.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName, re.DepartmentId, re.DepartmentName, re.NetPay,
                p.PayslipId, p.PayslipNo, p.Template, p.NetPay AS SlipNetPay, p.GeneratedDate,
                CAST(CASE WHEN p.PayslipId IS NOT NULL AND (p.NetPay <> re.NetPay OR p.GeneratedDate < r.ClosedDate) THEN 1 ELSE 0 END AS BIT) AS IsOutdated,
                em.Email, p.EmailTo, ISNULL(p.EmailStatus, 'NOT_SENT') AS EmailStatus, p.EmailQueuedDate, p.EmailSentDate, p.EmailError,
                ISNULL(p.EmailAttempts, 0) AS EmailAttempts, ISNULL(p.ViewCount, 0) AS ViewCount, p.FirstViewedDate
        INTO    #L
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    [Payroll].[PayrollRuns]         AS r  ON r.PayrollRunId = re.PayrollRunId
        JOIN    [Core].[Companies]              AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars]    AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]      AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        JOIN    [Employee].[Employees]          AS e  ON e.EmployeeId = re.EmployeeId
        LEFT JOIN [Payroll].[Payslips]          AS p  ON p.PayrollRunId = re.PayrollRunId AND p.EmployeeId = re.EmployeeId AND p.Deleted = 0
        CROSS APPLY (SELECT COALESCE(NULLIF(LTRIM(RTRIM(e.WorkEmail)), N''), NULLIF(LTRIM(RTRIM(e.PersonalEmail)), N'')) AS Email) AS em
        WHERE   re.Deleted = 0 AND re.IsExcluded = 0 AND (r.RunType = 'REGULAR' OR re.LineCount > 0)
          AND   r.Deleted = 0 AND r.Stage IN ('VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
          AND   (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0)
          AND   (@RunId IS NULL OR r.PayrollRunId = @RunId)
          AND   (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND   (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
          AND   (@SelfEmployeeId IS NULL OR (re.EmployeeId = @SelfEmployeeId AND r.Stage = 'CLOSED' AND p.PayslipId IS NOT NULL))
          AND   (@EmployeeId IS NULL OR re.EmployeeId = @EmployeeId)
          AND   (@DepartmentId IS NULL OR re.DepartmentId = @DepartmentId)
          AND   (@Pattern IS NULL OR re.EmployeeNo LIKE @Pattern ESCAPE '\' OR re.EmployeeName LIKE @Pattern ESCAPE '\'
                 OR re.ArabicName LIKE @Pattern ESCAPE '\' OR p.PayslipNo LIKE @Pattern ESCAPE '\' OR em.Email LIKE @Pattern ESCAPE '\');

        /* status filter - payslip or email */
        DELETE FROM #L
        WHERE  NOT (   @StatusFilter = 'ALL'
                    OR (@StatusFilter = 'GENERATED'     AND PayslipId IS NOT NULL)
                    OR (@StatusFilter = 'NOT_GENERATED' AND PayslipId IS NULL)
                    OR (@StatusFilter = 'OUTDATED'      AND IsOutdated = 1)
                    OR (@StatusFilter = 'NOT_SENT'      AND PayslipId IS NOT NULL AND EmailStatus = 'NOT_SENT' AND Email IS NOT NULL)
                    OR (@StatusFilter = 'QUEUED'        AND EmailStatus IN ('QUEUED', 'SENDING'))
                    OR (@StatusFilter = 'SENT'          AND EmailStatus = 'SENT')
                    OR (@StatusFilter = 'FAILED'        AND EmailStatus = 'FAILED')
                    OR (@StatusFilter = 'NO_EMAIL'      AND Email IS NULL));

        SELECT @TotalCount = COUNT(1) FROM #L;
        SELECT * FROM #L
        ORDER BY RunMonth DESC, PayrollRunId DESC,
                 CASE WHEN @StatusFilter = 'FAILED' OR @StatusFilter = 'ALL' THEN CASE EmailStatus WHEN 'FAILED' THEN 0 ELSE 1 END ELSE 0 END,
                 EmployeeName, EmployeeNo
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ---------------- the payroll being worked on ---------------- */
    DECLARE @rComp INT, @rStage VARCHAR(20), @rCode NVARCHAR(40), @rType VARCHAR(10), @rClosed DATETIME2(0);
    IF @RunId IS NOT NULL
        SELECT  @rComp = r.CompanyId, @rStage = r.Stage, @rCode = r.RunCode, @rType = r.RunType, @rClosed = r.ClosedDate
        FROM    [Payroll].[PayrollRuns] AS r
        WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0
          AND   (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);

    /* ======================= VIEWED ============================== */
    IF @Action = 'VIEWED'
    BEGIN
        UPDATE [Payroll].[Payslips]
           SET ViewCount = ViewCount + 1, FirstViewedDate = ISNULL(FirstViewedDate, @Now)
        WHERE  PayrollRunId = @RunId AND EmployeeId = @SelfEmployeeId AND Deleted = 0 AND @rStage = 'CLOSED';
        RETURN;
    END;

    IF @rStage IS NULL OR @rStage NOT IN ('VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
    BEGIN
        IF @Action IN ('SUMMARY', 'GET') RETURN;
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This payroll no longer exists or has no payslips.';
        RETURN;
    END;

    /* ======================= SUMMARY ============================= */
    IF @Action = 'SUMMARY'
    BEGIN
        SELECT  COUNT(1)                                                                                        AS EmployeeCount,
                COUNT(p.PayslipId)                                                                              AS GeneratedCount,
                COUNT(CASE WHEN p.PayslipId IS NULL THEN 1 END)                                                 AS NotGeneratedCount,
                COUNT(CASE WHEN p.PayslipId IS NOT NULL AND (p.NetPay <> re.NetPay OR p.GeneratedDate < @rClosed) THEN 1 END) AS OutdatedCount,
                COUNT(CASE WHEN em.Email IS NULL THEN 1 END)                                                    AS NoEmailCount,
                COUNT(CASE WHEN p.PayslipId IS NOT NULL AND p.EmailStatus = 'NOT_SENT' AND em.Email IS NOT NULL THEN 1 END) AS NotSentCount,
                COUNT(CASE WHEN p.EmailStatus IN ('QUEUED', 'SENDING') THEN 1 END)                              AS QueuedCount,
                COUNT(CASE WHEN p.EmailStatus = 'SENT' THEN 1 END)                                              AS SentCount,
                COUNT(CASE WHEN p.EmailStatus = 'FAILED' THEN 1 END)                                            AS FailedCount,
                COUNT(CASE WHEN p.ViewCount > 0 THEN 1 END)                                                     AS ViewedCount,
                ISNULL(SUM(re.NetPay), 0)                                                                       AS TotalNet,
                MAX(p.GeneratedDate)                                                                            AS LastGeneratedDate
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    [Employee].[Employees]          AS e ON e.EmployeeId = re.EmployeeId
        LEFT JOIN [Payroll].[Payslips]          AS p ON p.PayrollRunId = re.PayrollRunId AND p.EmployeeId = re.EmployeeId AND p.Deleted = 0
        CROSS APPLY (SELECT COALESCE(NULLIF(LTRIM(RTRIM(e.WorkEmail)), N''), NULLIF(LTRIM(RTRIM(e.PersonalEmail)), N'')) AS Email) AS em
        WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0 AND (@rType = 'REGULAR' OR re.LineCount > 0);
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        IF @SelfEmployeeId IS NOT NULL AND (@SelfEmployeeId <> ISNULL(@EmployeeId, @SelfEmployeeId) OR @rStage <> 'CLOSED')
            RETURN;

        SELECT  r.PayrollRunId, r.RunCode, r.RunType, r.RunMonth, r.Stage, r.ClosedDate, r.CompanyId,
                co.CompanyCode, co.CompanyName,
                pc.CalendarName, pc.ArabicName AS CalendarArabicName, pc.PayFrequency,
                pp.PeriodNumber, pp.StartDate, pp.EndDate, pp.PaymentDate,
                re.RunEmployeeId, re.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName, re.DepartmentName,
                re.IsKuwaiti, re.HireDate, re.TerminationDate, re.PeriodDays, re.PaidDays,
                re.SalaryTotal, re.EarningsTotal, re.DeductionsTotal, re.NetPay,
                ds.DesignationName, ds.ArabicName AS DesignationArabicName,
                ci.CivilIdNumber, ep.BankName, ep.Iban,
                em.Email,
                p.PayslipId, p.PayslipNo, p.Template, p.NetPay AS SlipNetPay, p.GeneratedDate, p.GenerationCount,
                p.EmailStatus, p.EmailTo, p.EmailSentDate, p.ViewCount,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ge.FirstName, N' ', ge.LastName))), N''), gu.Username) AS GeneratedByName
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    [Payroll].[PayrollRuns]         AS r  ON r.PayrollRunId = re.PayrollRunId
        JOIN    [Core].[Companies]              AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars]    AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]      AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        JOIN    [Employee].[Employees]          AS e  ON e.EmployeeId = re.EmployeeId
        LEFT JOIN [Core].[Designations]         AS ds ON ds.DesignationId = e.DesignationId
        LEFT JOIN [Kuwait].[EmployeeCompliance] AS ci ON ci.EmployeeId = e.EmployeeId
        LEFT JOIN [Employee].[EmployeePayroll]  AS ep ON ep.EmployeeId = e.EmployeeId
        LEFT JOIN [Payroll].[Payslips]          AS p  ON p.PayrollRunId = re.PayrollRunId AND p.EmployeeId = re.EmployeeId AND p.Deleted = 0
        LEFT JOIN [Security].[Users]            AS gu ON gu.UserId = p.GeneratedBy
        LEFT JOIN [Employee].[Employees]        AS ge ON ge.EmployeeId = gu.EmployeeId
        CROSS APPLY (SELECT COALESCE(NULLIF(LTRIM(RTRIM(e.WorkEmail)), N''), NULLIF(LTRIM(RTRIM(e.PersonalEmail)), N'')) AS Email) AS em
        WHERE   re.PayrollRunId = @RunId AND re.EmployeeId = @EmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
          AND   (@rType = 'REGULAR' OR re.LineCount > 0)
          AND   (@SelfEmployeeId IS NULL OR p.PayslipId IS NOT NULL);
        RETURN;
    END;

    /* =============================================================
       Changes - only on a closed payroll
       ============================================================= */
    IF @rStage <> 'CLOSED'
    BEGIN
        SELECT @ResultCode = 'NOT_CLOSED',
               @ResultMessage = N'Payslips can only be generated and emailed once the payroll is approved and closed.';
        RETURN;
    END;

    /* ======================= GENERATE ============================ */
    IF @Action = 'GENERATE'
    BEGIN
        IF @Template NOT IN ('BILINGUAL', 'ENGLISH', 'ARABIC')
        BEGIN
            SELECT @ResultCode = 'TEMPLATE_INVALID', @ResultMessage = N'Select the payslip language.';
            RETURN;
        END;

        DECLARE @G TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, PayslipNo NVARCHAR(70) NOT NULL, NetPay DECIMAL(12,3) NOT NULL);
        INSERT INTO @G (RunEmployeeId, EmployeeId, PayslipNo, NetPay)
        SELECT  re.RunEmployeeId, re.EmployeeId,
                LEFT(CONCAT(@rCode, N'-', ISNULL(NULLIF(re.EmployeeNo, N''), CAST(re.EmployeeId AS NVARCHAR(20)))), 70), re.NetPay
        FROM    [Payroll].[PayrollRunEmployees] AS re
        WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0 AND (@rType = 'REGULAR' OR re.LineCount > 0)
          AND   (@DepartmentId IS NULL OR re.DepartmentId = @DepartmentId)
          AND   (@EmployeeIds IS NULL OR re.EmployeeId IN (SELECT EmployeeId FROM @Picked));

        SET @TotalCount = (SELECT COUNT(1) FROM @G);
        IF @TotalCount = 0
        BEGIN
            SELECT @ResultCode = 'NOTHING_TO_GENERATE', @ResultMessage = N'No employee of this payroll matches your choice.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE p
               SET Template = @Template, NetPay = g.NetPay, PayslipNo = g.PayslipNo, RunEmployeeId = g.RunEmployeeId,
                   GenerationCount = CASE WHEN p.GenerationCount < 32000 THEN p.GenerationCount + 1 ELSE p.GenerationCount END,
                   GeneratedBy = @UserId, GeneratedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            FROM   [Payroll].[Payslips] AS p
            JOIN   @G AS g ON g.EmployeeId = p.EmployeeId
            WHERE  p.PayrollRunId = @RunId AND p.Deleted = 0;

            INSERT INTO [Payroll].[Payslips] (PayrollRunId, RunEmployeeId, EmployeeId, CompanyId, PayslipNo, Template, NetPay, GeneratedBy, GeneratedDate)
            SELECT @RunId, g.RunEmployeeId, g.EmployeeId, @rComp, g.PayslipNo, @Template, g.NetPay, @UserId, @Now
            FROM   @G AS g
            WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[Payslips] AS p WHERE p.PayrollRunId = @RunId AND p.EmployeeId = g.EmployeeId AND p.Deleted = 0);

            /* a payslip of an employee no longer paid by this payroll (excluded after a reopen) is withdrawn */
            IF @DepartmentId IS NULL AND @EmployeeIds IS NULL
                UPDATE p
                   SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
                FROM   [Payroll].[Payslips] AS p
                WHERE  p.PayrollRunId = @RunId AND p.Deleted = 0
                  AND  NOT EXISTS (SELECT 1 FROM @G AS g WHERE g.EmployeeId = p.EmployeeId);
        COMMIT TRANSACTION;

        SET @NewId = @RunId;
        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'1 payslip generated.'
                                  ELSE CONCAT(@TotalCount, N' payslips generated.') END;
        RETURN;
    END;

    /* ======================= QUEUE_EMAIL ========================= */
    IF @Action = 'QUEUE_EMAIL'
    BEGIN
        DECLARE @Q TABLE (PayslipId BIGINT PRIMARY KEY, Email NVARCHAR(150) NULL);
        INSERT INTO @Q (PayslipId, Email)
        SELECT  p.PayslipId, em.Email
        FROM    [Payroll].[Payslips]            AS p
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = p.RunEmployeeId
        JOIN    [Employee].[Employees]          AS e  ON e.EmployeeId = p.EmployeeId
        CROSS APPLY (SELECT LEFT(COALESCE(NULLIF(LTRIM(RTRIM(e.WorkEmail)), N''), NULLIF(LTRIM(RTRIM(e.PersonalEmail)), N'')), 150) AS Email) AS em
        WHERE   p.PayrollRunId = @RunId AND p.Deleted = 0
          AND   p.NetPay = re.NetPay AND (@rClosed IS NULL OR p.GeneratedDate >= @rClosed)      -- not outdated
          AND   p.EmailStatus NOT IN ('QUEUED', 'SENDING')
          AND   (   (@EmployeeIds IS NULL AND p.EmailStatus = 'NOT_SENT')
                 OR (@EmployeeIds IS NOT NULL AND p.EmployeeId IN (SELECT EmployeeId FROM @Picked)
                     AND (@Resend = 1 OR p.EmailStatus IN ('NOT_SENT', 'FAILED'))));

        DECLARE @NoEmail INT = (SELECT COUNT(1) FROM @Q WHERE Email IS NULL);
        SET @TotalCount = (SELECT COUNT(1) FROM @Q WHERE Email IS NOT NULL);

        IF @TotalCount = 0
        BEGIN
            SELECT @ResultCode = 'NOTHING_TO_SEND',
                   @ResultMessage = CASE WHEN @NoEmail > 0 AND @EmployeeIds IS NOT NULL THEN N'None of these employees has an email address. Add it on the employee profile.'
                                         ELSE N'There is no generated, up-to-date payslip left to email. Generate the payslips first.' END;
            RETURN;
        END;

        UPDATE p
           SET EmailTo = q.Email, EmailStatus = 'QUEUED', EmailQueuedBy = @UserId, EmailQueuedDate = @Now,
               EmailClaimedDate = NULL, EmailSentDate = NULL, EmailAttempts = 0, EmailError = NULL,
               ModifiedBy = @UserId, ModifiedDate = @Now
        FROM   [Payroll].[Payslips] AS p
        JOIN   @Q AS q ON q.PayslipId = p.PayslipId
        WHERE  q.Email IS NOT NULL;

        SET @NewId = @RunId;
        SET @ResultMessage = CONCAT(CASE WHEN @TotalCount = 1 THEN N'1 payslip email queued.' ELSE CONCAT(@TotalCount, N' payslip emails queued.') END,
                                    CASE WHEN @NoEmail > 0 THEN CONCAT(N' No email address: ', @NoEmail, N'.') END);
        RETURN;
    END;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/43 applied: Payroll.usp_Payslip_Manage. Run db/44 (labels) next.';
GO
