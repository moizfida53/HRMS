/* =====================================================================
   123_Payroll_Workspace.sql  -  one workspace per payroll; Approved,
                                 Execution and Completed
   ---------------------------------------------------------------------
   Run after db/42, db/49-50, db/115, db/116 and db/118. Safe to re-run.

   A payroll is now worked on from one place - its workspace (Payrolls >
   open a payroll). The tabs open as the payroll moves on:

     Overview · Register · Validation · Approval   from the start
     Payslips · Bank transfer · Collections · Accounting   once approved
     History                                        always

   After approval (Stage = CLOSED, unchanged) the payroll goes through
   three pay-out statuses (Payroll.PayrollRuns.PayoutStatus):

     APPROVED    approved - nothing paid out yet
     EXECUTION   the first pay-out action is done (a payslip generated, a
                 bank file made, a payment recorded or the journal created)
     COMPLETED   every employee has a payslip, every payment is Paid (the
                 net pay of each employee reached them in full) and the
                 journal is posted to the GL.

   Emailing payslips is shown but optional. Collections still pending do
   not hold the payroll back (they are shown as a reminder). A completed
   payroll is read-only; it goes back to Execution only when its journal
   is reversed.

   The status is worked out by Payroll.usp_PayrollRun_Payout (SYNC) after
   each pay-out action and saved with the dates; the payroll's history
   keeps "Pay-out started", "Completed" and "Reopened".
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[Payslips]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[BankPayments]', N'U') IS NULL
   OR OBJECT_ID(N'[Payroll].[JournalBatches]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[Collections]', N'U') IS NULL
   OR COL_LENGTH(N'Payroll.BankPayments', N'Stage') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/42, db/49, db/115 and db/116 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the pay-out status of a payroll ---------------------------------- */
IF COL_LENGTH(N'Payroll.PayrollRuns', N'PayoutStatus') IS NULL
    ALTER TABLE [Payroll].[PayrollRuns] ADD PayoutStatus VARCHAR(10) NULL
        CONSTRAINT CK_PayrollRuns_PayoutStatus CHECK (PayoutStatus IS NULL OR PayoutStatus IN ('APPROVED', 'EXECUTION', 'COMPLETED'));
IF COL_LENGTH(N'Payroll.PayrollRuns', N'ExecutionDate') IS NULL
    ALTER TABLE [Payroll].[PayrollRuns] ADD ExecutionDate DATETIME2(0) NULL;
IF COL_LENGTH(N'Payroll.PayrollRuns', N'CompletedDate') IS NULL
    ALTER TABLE [Payroll].[PayrollRuns] ADD CompletedDate DATETIME2(0) NULL;
IF COL_LENGTH(N'Payroll.PayrollRuns', N'CompletedBy') IS NULL
    ALTER TABLE [Payroll].[PayrollRuns] ADD CompletedBy BIGINT NULL;
GO

/* ---- 2. Payroll.ufn_RunPayout - where the pay-out of one payroll stands ---- */
CREATE OR ALTER FUNCTION [Payroll].[ufn_RunPayout] (@RunId BIGINT)
RETURNS TABLE
AS
RETURN
    WITH e AS (
        SELECT  COUNT(1) AS EmployeeCount,
                ISNULL(SUM(CASE WHEN re.NetPay > 0 THEN 1 ELSE 0 END), 0) AS PayeeCount,
                ISNULL(SUM(re.NetPay), 0) AS NetPayable,
                /* employees whose net pay has not reached them in full (paid payments of every step) */
                ISNULL(SUM(CASE WHEN re.NetPay > 0 AND ISNULL(pd.Paid, 0) < re.NetPay THEN 1 ELSE 0 END), 0) AS UnpaidPayeeCount
        FROM    [Payroll].[PayrollRunEmployees] AS re
        OUTER APPLY (SELECT SUM(bp.Amount) AS Paid FROM [Payroll].[BankPayments] AS bp
                     WHERE bp.PayrollRunId = @RunId AND bp.RunEmployeeId = re.RunEmployeeId AND bp.Deleted = 0 AND bp.Status = 'PAID') AS pd
        WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0
    ), s AS (
        SELECT  COUNT(1) AS PayslipCount,
                ISNULL(SUM(CASE WHEN ps.EmailStatus = 'SENT' THEN 1 ELSE 0 END), 0) AS EmailedCount,
                ISNULL(SUM(CASE WHEN ps.EmailStatus IN ('QUEUED', 'SENDING') THEN 1 ELSE 0 END), 0) AS EmailQueuedCount,
                ISNULL(SUM(CASE WHEN ps.EmailStatus = 'FAILED' THEN 1 ELSE 0 END), 0) AS EmailFailedCount
        FROM    [Payroll].[Payslips] AS ps
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = ps.RunEmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
        WHERE   ps.PayrollRunId = @RunId AND ps.Deleted = 0
    ), p AS (
        SELECT  COUNT(1) AS PaymentCount,
                ISNULL(SUM(CASE WHEN bp.Status = 'PAID' THEN 1 ELSE 0 END), 0) AS PaidCount,
                ISNULL(SUM(CASE WHEN bp.Status = 'FAILED' THEN 1 ELSE 0 END), 0) AS FailedCount,
                ISNULL(SUM(CASE WHEN bp.Status <> 'PAID' THEN 1 ELSE 0 END), 0) AS OpenPaymentCount,
                ISNULL(SUM(CASE WHEN bp.Status = 'PAID' THEN bp.Amount END), 0) AS PaidAmount
        FROM    [Payroll].[BankPayments] AS bp
        WHERE   bp.PayrollRunId = @RunId AND bp.Deleted = 0
    ), f AS (
        SELECT  COUNT(1) AS BankFileCount,
                ISNULL(SUM(CASE WHEN bf.Status = 'SENT' THEN 1 ELSE 0 END), 0) AS SentFileCount
        FROM    [Payroll].[BankFiles] AS bf
        WHERE   bf.PayrollRunId = @RunId AND bf.Deleted = 0 AND bf.Status <> 'SUPERSEDED'
    ), c AS (
        SELECT  COUNT(1) AS CollectionCount,
                ISNULL(SUM(CASE WHEN co.Status = 'PENDING' THEN 1 ELSE 0 END), 0) AS CollectionPendingCount,
                ISNULL(SUM(CASE WHEN co.Status = 'PENDING' THEN co.Amount END), 0) AS CollectionPendingAmount,
                ISNULL(SUM(CASE WHEN co.Status = 'COLLECTED' THEN co.Amount END), 0) AS CollectedAmount
        FROM    [Payroll].[Collections] AS co
        WHERE   co.PayrollRunId = @RunId AND co.Deleted = 0
    ), j AS (
        SELECT  TOP (1) jb.JournalId, jb.JournalNo, jb.Status AS JournalStatus, jb.PostedDate AS GlPostedDate, jb.PostedReference AS GlReference
        FROM    [Payroll].[JournalBatches] AS jb
        WHERE   jb.PayrollRunId = @RunId AND jb.Deleted = 0 AND jb.Status <> 'REVERSED'
        ORDER BY jb.JournalId DESC
    )
    SELECT  e.EmployeeCount, e.PayeeCount, e.NetPayable, e.UnpaidPayeeCount,
            s.PayslipCount, s.EmailedCount, s.EmailQueuedCount, s.EmailFailedCount,
            p.PaymentCount, p.PaidCount, p.FailedCount, p.OpenPaymentCount, p.PaidAmount,
            f.BankFileCount, f.SentFileCount,
            c.CollectionCount, c.CollectionPendingCount, c.CollectionPendingAmount, c.CollectedAmount,
            j.JournalId, j.JournalNo, j.JournalStatus, j.GlPostedDate, j.GlReference,
            CASE WHEN e.EmployeeCount - s.PayslipCount <= 0
                      AND e.UnpaidPayeeCount = 0 AND p.OpenPaymentCount = 0
                      AND j.JournalStatus = 'POSTED'                               THEN 'COMPLETED'
                 WHEN s.PayslipCount > 0 OR p.PaymentCount > 0 OR f.BankFileCount > 0
                      OR j.JournalId IS NOT NULL OR c.CollectedAmount > 0           THEN 'EXECUTION'
                 ELSE 'APPROVED' END AS LiveStatus
    FROM    e CROSS JOIN s CROSS JOIN p CROSS JOIN f CROSS JOIN c
    LEFT JOIN j ON 1 = 1;
GO

/* ---- 3. Payroll.usp_PayrollRun_Payout -------------------------------------
     LIST    the pay-out of the payrolls in @RunIds (CSV) or @RunId
     COUNTS  how many payrolls in scope are Approved / in Execution / Completed
     SYNC    saves the status of @RunId (NULL = every closed payroll in scope)
             that changed, with the dates and the payroll's history
     LOCKED  how many of the payments (@PaymentIds) or the payroll (@RunId)
             belong to a completed payroll (read-only)
   -------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Payout]
    @Action      VARCHAR(10),
    @RunId       BIGINT          = NULL,
    @RunIds      NVARCHAR(MAX)   = NULL,
    @PaymentIds  NVARCHAR(MAX)   = NULL,
    @CompanyId   INT             = NULL,
    @CompanyIds  NVARCHAR(2000)  = NULL,
    @UserId      BIGINT          = NULL,
    @Quiet       BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action = 'LIST'
    BEGIN
        SELECT  r.PayrollRunId,
                CASE WHEN r.Stage <> 'CLOSED' THEN NULL
                     /* a completed payroll stays completed while its journal is posted */
                     WHEN r.PayoutStatus = 'COMPLETED' AND x.JournalStatus = 'POSTED' THEN 'COMPLETED'
                     ELSE x.LiveStatus END AS PayoutStatus,
                r.ExecutionDate, r.CompletedDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ce.FirstName, N' ', ce.LastName))), N''), cu.Username) AS CompletedByName,
                x.EmployeeCount, x.PayeeCount, x.NetPayable, x.UnpaidPayeeCount,
                x.PayslipCount, x.EmailedCount, x.EmailQueuedCount, x.EmailFailedCount,
                x.PaymentCount, x.PaidCount, x.FailedCount, x.OpenPaymentCount, x.PaidAmount,
                x.BankFileCount, x.SentFileCount,
                x.CollectionCount, x.CollectionPendingCount, x.CollectionPendingAmount, x.CollectedAmount,
                x.JournalId, x.JournalNo, x.JournalStatus, x.GlPostedDate, x.GlReference
        FROM    [Payroll].[PayrollRuns] AS r
        CROSS APPLY [Payroll].[ufn_RunPayout](r.PayrollRunId) AS x
        LEFT JOIN [Security].[Users] AS cu ON cu.UserId = r.CompletedBy
        LEFT JOIN [Employee].[Employees] AS ce ON ce.EmployeeId = cu.EmployeeId
        WHERE   r.Deleted = 0
          AND  (r.PayrollRunId = @RunId
                OR r.PayrollRunId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@RunIds, N''), ',')))
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;
        RETURN;
    END;

    IF @Action = 'COUNTS'
    BEGIN
        SELECT  ISNULL(SUM(CASE WHEN s.PayoutStatus = 'APPROVED'  THEN 1 ELSE 0 END), 0) AS ApprovedCount,
                ISNULL(SUM(CASE WHEN s.PayoutStatus = 'EXECUTION' THEN 1 ELSE 0 END), 0) AS ExecutionCount,
                ISNULL(SUM(CASE WHEN s.PayoutStatus = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS CompletedCount
        FROM   (SELECT CASE WHEN r.PayoutStatus = 'COMPLETED' AND x.JournalStatus = 'POSTED' THEN 'COMPLETED' ELSE x.LiveStatus END AS PayoutStatus
                FROM   [Payroll].[PayrollRuns] AS r
                CROSS APPLY [Payroll].[ufn_RunPayout](r.PayrollRunId) AS x
                WHERE  r.Deleted = 0 AND r.Stage = 'CLOSED'
                  AND  [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS s;
        RETURN;
    END;

    IF @Action = 'LOCKED'
    BEGIN
        SELECT  (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] AS r
                 WHERE r.Deleted = 0 AND r.PayoutStatus = 'COMPLETED'
                   AND (r.PayrollRunId = @RunId
                        OR r.PayrollRunId IN (SELECT bp.PayrollRunId FROM [Payroll].[BankPayments] AS bp
                                              WHERE bp.Deleted = 0
                                                AND bp.BankPaymentId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@PaymentIds, N''), ','))))
                ) AS LockedCount;
        RETURN;
    END;

    IF @Action = 'SYNC'
    BEGIN
        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
        DECLARE @Changed TABLE (PayrollRunId BIGINT PRIMARY KEY, OldStatus VARCHAR(10) NULL, NewStatus VARCHAR(10) NULL);

        INSERT INTO @Changed (PayrollRunId, OldStatus, NewStatus)
        SELECT  r.PayrollRunId, r.PayoutStatus, n.NewStatus
        FROM    [Payroll].[PayrollRuns] AS r
        OUTER APPLY (SELECT CASE WHEN r.Stage <> 'CLOSED' THEN NULL
                                 WHEN r.PayoutStatus = 'COMPLETED' AND x.JournalStatus = 'POSTED' THEN 'COMPLETED'
                                 ELSE x.LiveStatus END AS NewStatus
                     FROM [Payroll].[ufn_RunPayout](r.PayrollRunId) AS x) AS n
        WHERE   r.Deleted = 0
          AND  (@RunId IS NULL OR r.PayrollRunId = @RunId)
          AND  (r.Stage = 'CLOSED' OR r.PayoutStatus IS NOT NULL)
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND   ISNULL(r.PayoutStatus, '') <> ISNULL(n.NewStatus, '');

        IF NOT EXISTS (SELECT 1 FROM @Changed)
        BEGIN
            SELECT 0 AS ChangedCount;
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE  r
            SET     r.PayoutStatus  = c.NewStatus,
                    r.ExecutionDate = CASE WHEN c.NewStatus IN ('EXECUTION', 'COMPLETED') THEN ISNULL(r.ExecutionDate, @Now) ELSE NULL END,
                    r.CompletedDate = CASE WHEN c.NewStatus = 'COMPLETED' THEN @Now ELSE NULL END,
                    r.CompletedBy   = CASE WHEN c.NewStatus = 'COMPLETED' THEN @UserId ELSE NULL END
            FROM    [Payroll].[PayrollRuns] AS r
            JOIN    @Changed AS c ON c.PayrollRunId = r.PayrollRunId;

            IF ISNULL(@Quiet, 0) = 0
                INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy, ActionDate)
                SELECT  c.PayrollRunId,
                        CASE WHEN c.NewStatus = 'COMPLETED' THEN 'PAYOUT_COMPLETED'
                             WHEN c.OldStatus = 'COMPLETED' THEN 'PAYOUT_REOPENED'
                             WHEN c.NewStatus = 'EXECUTION' THEN 'PAYOUT_STARTED'
                             ELSE 'PAYOUT_RESET' END,
                        ISNULL(c.OldStatus, 'APPROVED'), ISNULL(c.NewStatus, 'APPROVED'), NULL, @UserId, @Now
                FROM    @Changed AS c
                WHERE   c.NewStatus IS NOT NULL AND NOT (c.OldStatus IS NULL AND c.NewStatus = 'APPROVED');
        COMMIT TRANSACTION;

        SELECT COUNT(1) AS ChangedCount FROM @Changed;
        RETURN;
    END;
END;
GO

/* ---- 4. first run: every closed payroll gets its status (no history rows) */
EXEC [Payroll].[usp_PayrollRun_Payout] @Action = 'SYNC', @Quiet = 1;
GO

/* ---- 5. labels ------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('ws.stage_approved', 'ws', N'Approved', N'معتمد', NULL),
        ('ws.stage_execution', 'ws', N'Execution', N'قيد التنفيذ', NULL),
        ('ws.stage_completed', 'ws', N'Completed', N'مكتمل', NULL),
        ('ws.tabs_label', 'ws', N'Payroll workspace', N'مساحة عمل الرواتب', NULL),
        ('ws.group_prepare', 'ws', N'Preparation', N'الإعداد', NULL),
        ('ws.group_payout', 'ws', N'Pay-out', N'الصرف', NULL),
        ('ws.group_record', 'ws', N'Record', N'السجل', NULL),
        ('ws.tab_overview', 'ws', N'Overview', N'نظرة عامة', NULL),
        ('ws.tab_register', 'ws', N'Employees & lines', N'الموظفون والبنود', NULL),
        ('ws.tab_validation', 'ws', N'Validation', N'التحقق', NULL),
        ('ws.tab_approval', 'ws', N'Approval', N'الاعتماد', NULL),
        ('ws.tab_payslips', 'ws', N'Payslips', N'قسائم الرواتب', NULL),
        ('ws.tab_bank', 'ws', N'Bank transfer', N'التحويل البنكي', NULL),
        ('ws.tab_collections', 'ws', N'Collections', N'التحصيلات', NULL),
        ('ws.tab_accounting', 'ws', N'Accounting', N'المحاسبة', NULL),
        ('ws.tab_history', 'ws', N'History', N'السجل', NULL),
        ('ws.done', 'ws', N'Done', N'تم', NULL),
        ('ws.lock_validation', 'ws', N'Opens when registration is complete', N'تفتح عند اكتمال التسجيل', NULL),
        ('ws.lock_approval', 'ws', N'Opens when the payroll is submitted for approval', N'تفتح عند إرسال الرواتب للاعتماد', NULL),
        ('ws.lock_payout', 'ws', N'Opens after approval', N'تفتح بعد الاعتماد', NULL),
        ('ws.lock_cancelled', 'ws', N'This payroll is cancelled', N'هذه الرواتب ملغاة', NULL),
        ('ws.overview_subtitle', 'ws', N'Where this payroll stands and what is left to do.', N'أين وصلت هذه الرواتب وما المتبقي.', NULL),
        ('ws.history_subtitle', 'ws', N'Every action on this payroll, from creation to completion.', N'كل إجراء على هذه الرواتب من الإنشاء حتى الاكتمال.', NULL),
        ('ws.payslips_subtitle', 'ws', N'Generate, view, print and email the payslips of this payroll.', N'إنشاء قسائم هذه الرواتب وعرضها وطباعتها وإرسالها.', NULL),
        ('ws.collections_subtitle', 'ws', N'The work permit collections of this payroll.', N'تحصيلات إذن العمل لهذه الرواتب.', NULL),
        ('ws.accounting_subtitle', 'ws', N'The journal of this payroll and its posting to the GL.', N'قيد هذه الرواتب وترحيله إلى دفتر الأستاذ.', NULL),
        ('ws.checklist_title', 'ws', N'What is left', N'المتبقي', NULL),
        ('ws.checklist_payout_text', 'ws', N'The payroll is completed when the three required steps are done.', N'تكتمل الرواتب عند إنجاز الخطوات الثلاث المطلوبة.', NULL),
        ('ws.checklist_prepare_text', 'ws', N'The pay-out steps open once the payroll is approved.', N'تفتح خطوات الصرف بعد اعتماد الرواتب.', NULL),
        ('ws.0_of_3_done', 'ws', N'{0} of 3 required steps done', N'{0} من 3 خطوات مطلوبة منجزة', NULL),
        ('ws.next_action', 'ws', N'Next action', N'الإجراء التالي', NULL),
        ('ws.next_register', 'ws', N'Review the register and complete registration', N'راجع السجل وأكمل التسجيل', NULL),
        ('ws.next_validate', 'ws', N'Fix the errors, review the warnings and submit for approval', N'صحح الأخطاء وراجع التحذيرات ثم أرسل للاعتماد', NULL),
        ('ws.next_approve_0', 'ws', N'Waiting for approval - level {0} of 2', N'بانتظار الاعتماد - المستوى {0} من 2', NULL),
        ('ws.next_generate_payslips', 'ws', N'Generate the payslips', N'أنشئ قسائم الرواتب', NULL),
        ('ws.next_generate_bank_file', 'ws', N'Generate the bank file', N'أنشئ ملف البنك', NULL),
        ('ws.next_mark_paid', 'ws', N'Mark the payments as paid', N'سجّل الدفعات كمدفوعة', NULL),
        ('ws.next_reissue_failed', 'ws', N'Re-issue the failed payments', N'أعد إصدار الدفعات الفاشلة', NULL),
        ('ws.next_create_journal', 'ws', N'Create the payroll journal', N'أنشئ قيد الرواتب', NULL),
        ('ws.next_post_gl', 'ws', N'Post the journal to the GL', N'رحّل القيد إلى دفتر الأستاذ', NULL),
        ('ws.nothing_left', 'ws', N'Nothing left', N'لا شيء متبقٍ', NULL),
        ('ws.step_prepare', 'ws', N'Prepared and approved', N'أُعدت واعتُمدت', NULL),
        ('ws.step_prepare_done_0_1', 'ws', N'Approved by {0} on {1}', N'اعتمدها {0} في {1}', NULL),
        ('ws.step_payslips', 'ws', N'Payslips generated', N'إنشاء قسائم الرواتب', NULL),
        ('ws.step_email', 'ws', N'Payslips emailed', N'إرسال القسائم بالبريد', NULL),
        ('ws.step_bank', 'ws', N'Salaries paid', N'دفع الرواتب', NULL),
        ('ws.step_collections', 'ws', N'Collections received', N'استلام التحصيلات', NULL),
        ('ws.step_gl', 'ws', N'Journal posted to the GL', N'ترحيل القيد إلى دفتر الأستاذ', NULL),
        ('ws.required', 'ws', N'Required', N'مطلوب', NULL),
        ('ws.optional', 'ws', N'Optional', N'اختياري', NULL),
        ('ws.reminder', 'ws', N'Reminder', N'تذكير', NULL),
        ('ws.0_of_1_generated', 'ws', N'{0} of {1} generated', N'{0} من {1} منشأة', NULL),
        ('ws.0_of_1_emailed', 'ws', N'{0} of {1} emailed', N'{0} من {1} مرسلة', NULL),
        ('ws.0_of_1_paid', 'ws', N'{0} of {1} employees paid in full', N'{0} من {1} موظف مدفوع بالكامل', NULL),
        ('ws.0_failed', 'ws', N'{0} failed', N'{0} فشلت', NULL),
        ('ws.0_files', 'ws', N'{0} file(s)', N'{0} ملف', NULL),
        ('ws.0_pending_1', 'ws', N'{0} pending · KWD {1}', N'{0} معلقة · {1} د.ك', NULL),
        ('ws.no_collections', 'ws', N'Nothing to collect', N'لا شيء للتحصيل', NULL),
        ('ws.posted_0_1', 'ws', N'Posted on {0} · ref. {1}', N'رُحّل في {0} · المرجع {1}', NULL),
        ('ws.journal_ready', 'ws', N'Ready - not posted yet', N'جاهز - لم يُرحّل بعد', NULL),
        ('ws.journal_exported', 'ws', N'Exported - not posted yet', N'مُصدّر - لم يُرحّل بعد', NULL),
        ('ws.journal_posted', 'ws', N'Posted', N'مُرحّل', NULL),
        ('ws.rule_text', 'ws', N'Completed = every employee has a payslip, every payment is paid and the journal is posted to the GL. Emailing payslips is optional; collections still pending do not hold the payroll back.', N'مكتمل = لكل موظف قسيمة، وكل دفعة مدفوعة، والقيد مُرحّل إلى دفتر الأستاذ. إرسال القسائم اختياري، والتحصيلات المعلقة لا تؤخر الرواتب.', NULL),
        ('ws.recent_activity', 'ws', N'Recent activity', N'آخر النشاطات', NULL),
        ('ws.see_all', 'ws', N'See all', N'عرض الكل', NULL),
        ('ws.payroll_history', 'ws', N'Payroll history', N'سجل الرواتب', NULL),
        ('ws.no_history', 'ws', N'Nothing recorded yet.', N'لم يُسجّل شيء بعد.', NULL),
        ('ws.completed_title', 'ws', N'This payroll is completed.', N'اكتملت هذه الرواتب.', NULL),
        ('ws.completed_0_1', 'ws', N'Completed on {0} by {1}.', N'اكتملت في {0} بواسطة {1}.', NULL),
        ('ws.completed_text', 'ws', N'It is read-only; reversing its journal sets it back to Execution.', N'أصبحت للقراءة فقط؛ عكس القيد يعيدها إلى التنفيذ.', NULL),
        ('ws.locked_completed', 'ws', N'The payroll is completed - read-only.', N'الرواتب مكتملة - للقراءة فقط.', NULL),
        ('ws.reverse_reopens', 'ws', N'Reversing the journal sets the payroll back to Execution.', N'عكس القيد يعيد الرواتب إلى التنفيذ.', NULL),
        ('ws.approved_banner_title', 'ws', N'This payroll is approved.', N'تم اعتماد هذه الرواتب.', NULL),
        ('ws.approved_banner_0_1', 'ws', N'Approved by {0} on {1} - payslips, bank transfer, collections and accounting are on its workspace.', N'اعتمدها {0} في {1} - القسائم والتحويل البنكي والتحصيلات والمحاسبة في مساحة عملها.', NULL),
        ('ws.go_to_payout', 'ws', N'Go to pay-out', N'الانتقال إلى الصرف', NULL),
        ('ws.sub_generate_view', 'ws', N'Generate & view', N'إنشاء وعرض', NULL),
        ('ws.sub_email', 'ws', N'Email', N'البريد', NULL),
        ('ws.sub_bank_file', 'ws', N'Bank file', N'ملف البنك', NULL),
        ('ws.payment_register', 'ws', N'Payment register', N'سجل الدفعات', NULL),
        ('ws.collections_note_title', 'ws', N'Company records only.', N'سجلات الشركة فقط.', NULL),
        ('ws.collections_note_text', 'ws', N'Pending collections are a reminder - they do not hold back the completion of the payroll.', N'التحصيلات المعلقة للتذكير - لا تؤخر اكتمال الرواتب.', NULL),
        ('ws.gl_after_bank_title', 'ws', N'Post to the GL once the salaries are paid.', N'رحّل إلى دفتر الأستاذ بعد دفع الرواتب.', NULL),
        ('ws.gl_after_bank_text', 'ws', N'Posting locks the bank files of this payroll.', N'الترحيل يقفل ملفات البنك لهذه الرواتب.', NULL),
        ('ws.col_payout', 'ws', N'Pay-out', N'الصرف', NULL),
        ('ws.dash_paying_out', 'ws', N'Paying out', N'قيد الصرف', NULL),
        ('ws.dash_0_completed', 'ws', N'{0} completed', N'{0} مكتملة', NULL),
        ('ws.h_payout_started', 'ws', N'Pay-out started (Execution)', N'بدأ الصرف (التنفيذ)', NULL),
        ('ws.h_payout_completed', 'ws', N'Completed', N'مكتملة', NULL),
        ('ws.h_payout_reopened', 'ws', N'Reopened - back to Execution', N'أُعيد فتحها - عادت إلى التنفيذ', NULL),
        ('ws.h_payout_reset', 'ws', N'Back to Approved', N'عادت إلى معتمدة', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Workspace labels inserted: ', @@ROWCOUNT);
GO
