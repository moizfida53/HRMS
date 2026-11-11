/* ============================================================================
   147 - Security: delete a user, delete a role together with its users
   ----------------------------------------------------------------------------
   Security.usp_SecurityDelete_Manage (new; usp_SecurityAdmin_Manage is not touched)

     USER_DELETE   delete one user: the account and every role link are flagged
                   deleted (db/28 soft delete - the row stays for the audit trail),
                   the user is signed out within a minute, the employee record is
                   NOT touched. Refused for: your own account, a System
                   Administrator unless you are one, the last active System
                   Administrator.

     ROLE_IMPACT   what deleting a role would do to the users who hold it:
                   one row per user - OtherRoles (how many other roles they hold)
                   and WillDelete (1 = this is their ONLY role, so the user is
                   deleted too; 0 = they keep the account and only lose this role).
                   Shown in the confirmation popup.

     ROLE_DELETE   delete a role:
                     * nobody holds it           -> the role is deleted
                     * users hold it, @Confirm=1 -> users whose only role it is are
                       deleted; every other user just loses this role and stays
                     * users hold it, @Confirm=0 -> IN_USE (nothing changes)
                   Refused for: the System Administrator role, a role shared by
                   every company when the caller is pinned to one company, and a
                   role that is the ONLY role of the caller (it would delete them).
                   One transaction; every change is written to Security.RoleAccessLog.

   Permissions: the pages' own rights (SECURITY_ROLE_DELETE for roles, the Full
   level of Manage Users = SECURITY_USER_DISABLE for users) - checked by the app.

   Safe to run more than once.
   ============================================================================ */

SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE [Security].[usp_SecurityDelete_Manage]
    @Action           VARCHAR(20),
    @CompanyId        INT             = NULL,     -- the caller's company when pinned (scope)
    @RoleId           INT             = NULL,
    @UserId           BIGINT          = NULL,     -- USER_DELETE: the user to delete
    @Confirm          BIT             = 0,        -- ROLE_DELETE: the caller confirmed the users' fate
    @CallerIsSysAdmin BIT             = 0,
    @ActionBy         BIGINT          = NULL,

    @TotalCount       INT             = NULL OUTPUT,
    @NewId            BIGINT          = NULL OUTPUT,
    @ResultCode       VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage    NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@RoleId, ISNULL(@UserId, 0)), @TotalCount = 0;
    DECLARE @Now DATETIME2(7) = SYSUTCDATETIME();

    IF @Action NOT IN ('USER_DELETE', 'ROLE_IMPACT', 'ROLE_DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= USER_DELETE ========================== */
    IF @Action = 'USER_DELETE'
    BEGIN
        DECLARE @uName NVARCHAR(100);
        SELECT @uName = Username FROM [Security].[Users]
        WHERE  UserId = @UserId AND Deleted = 0 AND (@CompanyId IS NULL OR CompanyId = @CompanyId);
        IF @uName IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That user was not found.';
            RETURN;
        END;
        IF @UserId = @ActionBy
        BEGIN
            SELECT @ResultCode = 'SELF', @ResultMessage = N'You cannot delete your own account.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Security].[UserRoles] ur JOIN [Security].[Roles] r ON r.RoleId = ur.RoleId AND r.Deleted = 0
                   WHERE ur.UserId = @UserId AND ur.Deleted = 0 AND r.RoleCode = N'SYSADMIN')
        BEGIN
            IF ISNULL(@CallerIsSysAdmin, 0) = 0
            BEGIN
                SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only a System Administrator can delete a System Administrator''s account.';
                RETURN;
            END;
            IF NOT EXISTS (SELECT 1 FROM [Security].[UserRoles] ur JOIN [Security].[Roles] r ON r.RoleId = ur.RoleId AND r.Deleted = 0
                           JOIN [Security].[Users] u ON u.UserId = ur.UserId
                           WHERE ur.Deleted = 0 AND r.RoleCode = N'SYSADMIN' AND u.Deleted = 0 AND u.IsActive = 1 AND u.UserId <> @UserId)
            BEGIN
                SELECT @ResultCode = 'LAST_ADMIN', @ResultMessage = N'This is the last active System Administrator - give the role to another user first.';
                RETURN;
            END;
        END;

        BEGIN TRANSACTION;
            UPDATE [Security].[UserRoles] SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now
            WHERE  UserId = @UserId AND Deleted = 0;

            /* a new security stamp ends the user's open sessions (PermissionRefresh) */
            UPDATE [Security].[Users]
               SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now, SecurityStamp = NEWID(),
                   ModifiedBy = @ActionBy, ModifiedDate = CAST(@Now AS DATETIME2(0))
            WHERE  UserId = @UserId;

            INSERT INTO [Security].[RoleAccessLog] (UserId, ActionCode, Detail, ActionBy)
            VALUES (@UserId, 'USER_DELETED', LEFT(@uName, 2000), @ActionBy);
        COMMIT TRANSACTION;

        SET @NewId = @UserId;
        SET @ResultMessage = N'User deleted.';
        RETURN;
    END;

    /* ======================= ROLE_IMPACT / ROLE_DELETE ============ */
    DECLARE @dCode NVARCHAR(50), @dCompany INT;
    SELECT @dCode = RoleCode, @dCompany = CompanyId
    FROM   [Security].[Roles]
    WHERE  RoleId = @RoleId AND Deleted = 0 AND (@CompanyId IS NULL OR CompanyId IS NULL OR CompanyId = @CompanyId);
    IF @dCode IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That role no longer exists. Refresh and try again.';
        RETURN;
    END;
    IF @dCode = N'SYSADMIN'
    BEGIN
        SELECT @ResultCode = 'SYSTEM_ROLE', @ResultMessage = N'System Administrator is a system role and cannot be deleted.';
        RETURN;
    END;
    IF @CompanyId IS NOT NULL AND ISNULL(@dCompany, 0) <> @CompanyId
    BEGIN
        SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only a System Administrator can delete a role shared by every company.';
        RETURN;
    END;

    /* who holds the role, and how many OTHER roles each of them has */
    DECLARE @Holders TABLE (UserId BIGINT PRIMARY KEY, OtherRoles INT NOT NULL);
    INSERT INTO @Holders (UserId, OtherRoles)
    SELECT  u.UserId,
            (SELECT COUNT(DISTINCT o.RoleId)
             FROM   [Security].[UserRoles] o
             JOIN   [Security].[Roles] orr ON orr.RoleId = o.RoleId AND orr.Deleted = 0
             WHERE  o.UserId = u.UserId AND o.Deleted = 0 AND o.RoleId <> @RoleId)
    FROM    [Security].[UserRoles] ur
    JOIN    [Security].[Users] u ON u.UserId = ur.UserId AND u.Deleted = 0
    WHERE   ur.RoleId = @RoleId AND ur.Deleted = 0
    GROUP BY u.UserId;

    SET @TotalCount = (SELECT COUNT(1) FROM @Holders);

    /* the caller's own account would go with the role: refused */
    IF EXISTS (SELECT 1 FROM @Holders WHERE UserId = @ActionBy AND OtherRoles = 0)
    BEGIN
        SELECT @ResultCode = 'SELF',
               @ResultMessage = N'This is the only role of your own account, so deleting it would delete you too. Ask another administrator to do it.';
        RETURN;
    END;

    IF @Action = 'ROLE_IMPACT'
    BEGIN
        SELECT  h.UserId, u.Username,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))), N''), u.Username) AS DisplayName,
                h.OtherRoles,
                CAST(CASE WHEN h.OtherRoles = 0 THEN 1 ELSE 0 END AS BIT) AS WillDelete
        FROM    @Holders h
        JOIN    [Security].[Users] u ON u.UserId = h.UserId
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = u.EmployeeId
        ORDER BY CASE WHEN h.OtherRoles = 0 THEN 0 ELSE 1 END,
                 COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))), N''), u.Username);
        RETURN;
    END;

    /* ROLE_DELETE */
    IF @TotalCount > 0 AND ISNULL(@Confirm, 0) = 0
    BEGIN
        SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Users still have this role. Confirm to delete it together with their access.';
        RETURN;
    END;

    DECLARE @UsersDeleted INT = (SELECT COUNT(1) FROM @Holders WHERE OtherRoles = 0),
            @UsersKept    INT = (SELECT COUNT(1) FROM @Holders WHERE OtherRoles > 0);

    BEGIN TRANSACTION;
        /* the users whose only role this is: all their role links go; the others lose just this one */
        UPDATE ur SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now
        FROM   [Security].[UserRoles] ur
        JOIN   @Holders h ON h.UserId = ur.UserId
        WHERE  ur.Deleted = 0 AND (ur.RoleId = @RoleId OR h.OtherRoles = 0);

        UPDATE u
           SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now, SecurityStamp = NEWID(),
               ModifiedBy = @ActionBy, ModifiedDate = CAST(@Now AS DATETIME2(0))
        FROM   [Security].[Users] u
        JOIN   @Holders h ON h.UserId = u.UserId AND h.OtherRoles = 0;

        INSERT INTO [Security].[RoleAccessLog] (RoleId, UserId, ActionCode, Detail, ActionBy)
        SELECT @RoleId, h.UserId,
               CASE WHEN h.OtherRoles = 0 THEN 'USER_DELETED' ELSE 'USER_ROLES' END,
               LEFT(CONCAT(u.Username, CASE WHEN h.OtherRoles = 0 THEN N': deleted with the role ' ELSE N': lost the role ' END, @dCode), 2000),
               @ActionBy
        FROM   @Holders h JOIN [Security].[Users] u ON u.UserId = h.UserId;

        UPDATE [Security].[Roles] SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now WHERE RoleId = @RoleId;
        INSERT INTO [Security].[RoleAccessLog] (RoleId, ActionCode, Detail, ActionBy)
        VALUES (@RoleId, 'ROLE_DELETED', LEFT(CONCAT(@dCode, N': ', @UsersDeleted, N' users deleted, ', @UsersKept, N' kept'), 2000), @ActionBy);
    COMMIT TRANSACTION;

    SET @NewId = @RoleId;
    SET @ResultMessage = CASE WHEN @TotalCount = 0 THEN N'Role deleted.'
                              ELSE N'Role deleted. Users who had only this role were deleted too; the others kept their account and their other roles.' END;
    RETURN;
END;
GO

/* ---- Arabic for the messages and the screens ------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('sec.m_user_deleted', 'sec', N'User deleted.', N'تم حذف المستخدم.', NULL),
        ('sec.m_delete_self', 'sec', N'You cannot delete your own account.', N'لا يمكنك حذف حسابك الخاص.', NULL),
        ('sec.m_delete_sysadmin', 'sec', N'Only a System Administrator can delete a System Administrator''s account.', N'يمكن لمسؤول النظام فقط حذف حساب مسؤول النظام.', NULL),
        ('sec.m_role_self', 'sec', N'This is the only role of your own account, so deleting it would delete you too. Ask another administrator to do it.', N'هذا هو الدور الوحيد لحسابك، وحذفه سيحذفك أنت أيضاً. اطلب من مسؤول آخر القيام بذلك.', NULL),
        ('sec.m_role_in_use', 'sec', N'Users still have this role. Confirm to delete it together with their access.', N'ما زال مستخدمون يملكون هذا الدور. أكّد حذفه مع صلاحيات المستخدمين.', NULL),
        ('sec.m_role_deleted_users', 'sec', N'Role deleted. Users who had only this role were deleted too; the others kept their account and their other roles.', N'تم حذف الدور. حُذف أيضاً المستخدمون الذين لا يملكون غيره، أما الباقون فاحتفظوا بحسابهم وأدوارهم الأخرى.', NULL),
        ('js.sec_delete_user', 'js', N'Delete user', N'حذف المستخدم', NULL),
        ('js.sec_delete_user_text', 'js', N'The account and all its roles are removed and the user can no longer sign in. The employee record is not affected.', N'يُحذف الحساب وكل أدواره ولا يستطيع المستخدم تسجيل الدخول بعد ذلك. لا يتأثر سجل الموظف.', NULL),
        ('js.sec_delete_user_ok', 'js', N'Delete user', N'حذف المستخدم', NULL),
        ('js.sec_role_no_users', 'js', N'Delete the role {0}? No user has it.', N'هل تريد حذف الدور {0}؟ لا يملكه أي مستخدم.', NULL),
        ('js.sec_role_impact_intro', 'js', N'Delete the role {0}? It is assigned to {1} user(s).', N'هل تريد حذف الدور {0}؟ هو مُسنَد إلى {1} مستخدم.', NULL),
        ('js.sec_role_impact_delete', 'js', N'These users have only this role, so their accounts will be DELETED: {0}', N'هؤلاء المستخدمون لا يملكون غير هذا الدور، لذلك سيتم حذف حساباتهم: {0}', NULL),
        ('js.sec_role_impact_keep', 'js', N'These users have other roles: they only lose this role and keep their account: {0}', N'هؤلاء المستخدمون لديهم أدوار أخرى: يفقدون هذا الدور فقط ويحتفظون بحسابهم: {0}', NULL),
        ('js.sec_and_more', 'js', N'and {0} more', N'و{0} آخرين', NULL),
        ('js.sec_delete_role_ok', 'js', N'Delete role', N'حذف الدور', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

PRINT '147_Security_Delete_User_Role.sql applied.';
GO
