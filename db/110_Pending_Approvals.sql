/* =====================================================================
   110_Pending_Approvals.sql  -  What is waiting for the signed-in user to approve
   ---------------------------------------------------------------------
   Safe to re-run. Core.usp_PendingApprovals counts the records waiting for
   THIS user's approval - the sidebar badges, the bell and the side alert
   after sign-in show them. The application passes the user's approval
   rights (Security > Create Roles > Approval rights); a record the user
   submitted is left out unless they may approve their own (… SELF).

     PAYROLL     payrolls Awaiting approval      level 1 (HR) PAYROLL_RUN_APPROVE_HR,
                                                 level 2 (Finance) PAYROLL_RUN_APPROVE_FINANCE
     PAYITEM     pay items Pending approval      PAYROLL_ITEM_APPROVE_L1 / _L2
     SETTLEMENT  final settlements Pending       PAYROLL_FS_APPROVE_L1 / _L2
     LEAVE       leave requests Pending          level 1: the line manager or LEAVE_APPROVE_L1,
                                                 level 2: LEAVE_APPROVE_L2 (not one's own request)

   Level convention: payrolls, pay items and settlements ApprovalLevel 0 =
   waiting for level 1, 1 = waiting for level 2; leave requests 1 / 2.
   Labels (English + Arabic) at the end.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE [Core].[usp_PendingApprovals]
    @UserId      BIGINT,
    @EmployeeId  BIGINT          = NULL,    -- the user's own employee (own leave is not theirs to approve)
    @CompanyId   INT             = NULL,    -- a user pinned to one company
    @CompanyIds  NVARCHAR(2000)  = NULL,    -- the company filter (CSV)
    @PrL1 BIT = 0, @PrL2 BIT = 0, @PrSelf BIT = 0,
    @PiL1 BIT = 0, @PiL2 BIT = 0, @PiSelf BIT = 0,
    @FsL1 BIT = 0, @FsL2 BIT = 0, @FsSelf BIT = 0,
    @LvL1 BIT = 0, @LvL2 BIT = 0, @LvSelf BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Csv NVARCHAR(2010) = CASE WHEN NULLIF(LTRIM(RTRIM(@CompanyIds)), N'') IS NULL THEN NULL
                                       ELSE N',' + REPLACE(@CompanyIds, N' ', N'') + N',' END;
    DECLARE @R TABLE (Kind VARCHAR(20) PRIMARY KEY, Cnt INT NOT NULL, Oldest DATETIME2(0) NULL);

    IF (@PrL1 = 1 OR @PrL2 = 1) AND OBJECT_ID(N'[Payroll].[PayrollRuns]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'PAYROLL', COUNT(1), MIN(r.SubmittedDate)
        FROM   [Payroll].[PayrollRuns] AS r
        WHERE  r.Deleted = 0 AND r.Stage = 'AWAITING_APPROVAL'
          AND  (@CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((r.ApprovalLevel = 0 AND @PrL1 = 1) OR (r.ApprovalLevel = 1 AND @PrL2 = 1))
          AND  (@PrSelf = 1 OR r.SubmittedBy IS NULL OR r.SubmittedBy <> @UserId);

    IF (@PiL1 = 1 OR @PiL2 = 1) AND OBJECT_ID(N'[Payroll].[EmployeePayItems]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'PAYITEM', COUNT(1), MIN(i.SubmittedDate)
        FROM   [Payroll].[EmployeePayItems] AS i
        WHERE  i.Deleted = 0 AND i.Status = 'PENDING'
          AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(i.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((i.ApprovalLevel = 0 AND @PiL1 = 1) OR (i.ApprovalLevel = 1 AND @PiL2 = 1))
          AND  (@PiSelf = 1 OR i.SubmittedBy IS NULL OR i.SubmittedBy <> @UserId);

    IF (@FsL1 = 1 OR @FsL2 = 1) AND OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'SETTLEMENT', COUNT(1), MIN(s.SubmittedDate)
        FROM   [Payroll].[FinalSettlements] AS s
        WHERE  s.Deleted = 0 AND s.Status = 'PENDING'
          AND  (@CompanyId IS NULL OR s.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(s.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((s.ApprovalLevel = 0 AND @FsL1 = 1) OR (s.ApprovalLevel = 1 AND @FsL2 = 1))
          AND  (@FsSelf = 1 OR s.SubmittedBy IS NULL OR s.SubmittedBy <> @UserId);

    IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'LEAVE', COUNT(1), MIN(r.CreatedDate)
        FROM   [Leave].[LeaveRequests] AS r
        WHERE  r.Deleted = 0 AND r.Status = 'PENDING'
          AND  (@CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((r.ApprovalLevel = 1 AND (r.ManagerUserId = @UserId OR @LvL1 = 1)) OR (r.ApprovalLevel = 2 AND @LvL2 = 1))
          AND  (@LvSelf = 1 OR @EmployeeId IS NULL OR r.EmployeeId <> @EmployeeId);

    SELECT Kind, Cnt AS [Count], Oldest FROM @R WHERE Cnt > 0 ORDER BY Kind;
END;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('ap.title', 'ap', N'Waiting for your approval', N'بانتظار موافقتك', NULL),
        ('ap.text', 'ap', N'These records need your action.', N'هذه السجلات تحتاج إلى إجراء منك.', NULL),
        ('ap.close', 'ap', N'Close', N'إغلاق', NULL),
        ('ap.open', 'ap', N'Open', N'فتح', NULL),
        ('ap.none', 'ap', N'Nothing is waiting for your approval.', N'لا يوجد ما ينتظر موافقتك.', NULL),
        ('ap.kind_payroll', 'ap', N'Payrolls', N'مسيرات الرواتب', NULL),
        ('ap.kind_payitem', 'ap', N'Pay items', N'بنود الرواتب', NULL),
        ('ap.kind_settlement', 'ap', N'Final settlements', N'التسويات النهائية', NULL),
        ('ap.kind_leave', 'ap', N'Leave requests', N'طلبات الإجازة', NULL),
        ('ap.oldest', 'ap', N'oldest {0}', N'الأقدم {0}', NULL),
        ('ap.badge_title', 'ap', N'{0} waiting for your approval', N'{0} بانتظار موافقتك', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Pending approval labels inserted: ', @@ROWCOUNT);
GO
