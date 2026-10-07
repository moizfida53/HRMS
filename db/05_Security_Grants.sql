/* ================================================================
   HRMS Kuwait - database security hardening
   ----------------------------------------------------------------
   This is the script that makes the "stored procedures only" decision
   actually pay off in a vulnerability assessment.

   The application login is granted EXECUTE on the procedures and
   NOTHING ELSE. Direct table access is explicitly denied. Even with a
   full application compromise - a leaked connection string, a
   remote-code-execution bug in the web tier - the account cannot run
   "SELECT * FROM Payroll.EmployeePayroll", cannot drop a table, and
   cannot read a salary or a Civil ID except through a procedure you
   have reviewed.

   Review the login name and password policy before running.
   ----------------------------------------------------------------
   Run order: 01 base schema -> 02 additions -> 03 org procedures
              -> 04 shared procedures -> 05 (this file).
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @DatabaseName SYSNAME = DB_NAME();
PRINT 'Applying HRMS security policy to database: ' + @DatabaseName;
GO

/* ================================================================
   1. Application login and user
   ----------------------------------------------------------------
   Replace the password before running. Better still, use a
   contained-database user or an Entra ID / Windows service account
   and delete the SQL login block entirely.
================================================================ */
USE [master];
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hrms_app')
BEGIN
    CREATE LOGIN [hrms_app]
        WITH PASSWORD = N'ChangeThisBeforeRunning#2026',
             CHECK_POLICY   = ON,
             CHECK_EXPIRATION = OFF;
    PRINT 'Login [hrms_app] created. CHANGE THE PASSWORD.';
END
ELSE
    PRINT 'Login [hrms_app] already exists - left unchanged.';
GO

USE [HRMS_Kuwait];   /* <-- adjust if your database has a different name */
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'hrms_app')
BEGIN
    CREATE USER [hrms_app] FOR LOGIN [hrms_app];
    PRINT 'Database user [hrms_app] created.';
END
GO

/* ================================================================
   2. A role that can execute procedures and nothing else
================================================================ */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'hrms_app_role' AND type = 'R')
BEGIN
    CREATE ROLE [hrms_app_role];
    PRINT 'Role [hrms_app_role] created.';
END
GO

ALTER ROLE [hrms_app_role] ADD MEMBER [hrms_app];
GO

/* ================================================================
   3. GRANT EXECUTE on every schema that holds procedures
   ----------------------------------------------------------------
   Schema-level EXECUTE means new procedures are covered automatically
   as later modules are added - no forgotten GRANT causing a
   production 'permission denied'.
================================================================ */
GRANT EXECUTE ON SCHEMA::[Core]         TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Employee]     TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Kuwait]       TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Employment]   TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Attendance]   TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Leave]        TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Payroll]      TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Overtime]     TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Loans]        TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[EOS]          TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Documents]    TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Recruitment]  TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Performance]  TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Training]     TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[ESS]          TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Workflow]     TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Notification] TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Security]     TO [hrms_app_role];
GRANT EXECUTE ON SCHEMA::[Integration]  TO [hrms_app_role];
GO

/* ================================================================
   4. DENY every form of direct data access
   ----------------------------------------------------------------
   DENY beats GRANT in SQL Server, so this holds even if someone later
   adds the account to db_datareader by mistake.

   A procedure still reads and writes these tables normally, because
   ownership chaining applies when the procedure and the table share
   an owner (dbo). Permissions are checked on the procedure only.
================================================================ */
DECLARE @schema SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE schema_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.schemas
    WHERE name IN (N'Core', N'Employee', N'Kuwait', N'Employment', N'Attendance',
                   N'Leave', N'Payroll', N'Overtime', N'Loans', N'EOS',
                   N'Documents', N'Recruitment', N'Performance', N'Training',
                   N'ESS', N'Workflow', N'Notification', N'Security', N'Integration');

OPEN schema_cursor;
FETCH NEXT FROM schema_cursor INTO @schema;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql =
        N'DENY SELECT, INSERT, UPDATE, DELETE, ALTER, REFERENCES ON SCHEMA::' +
        QUOTENAME(@schema) + N' TO [hrms_app_role];';

    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM schema_cursor INTO @schema;
END;

CLOSE schema_cursor;
DEALLOCATE schema_cursor;

PRINT 'Direct table access denied on all schemas. Procedures remain executable.';
GO

/* ================================================================
   5. Remove any inherited blanket permissions
================================================================ */
IF EXISTS (SELECT 1 FROM sys.database_role_members rm
           JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
           JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
           WHERE m.name = N'hrms_app' AND r.name IN (N'db_owner', N'db_datareader', N'db_datawriter', N'db_ddladmin'))
BEGIN
    ALTER ROLE [db_owner]      DROP MEMBER [hrms_app];
    ALTER ROLE [db_datareader] DROP MEMBER [hrms_app];
    ALTER ROLE [db_datawriter] DROP MEMBER [hrms_app];
    ALTER ROLE [db_ddladmin]   DROP MEMBER [hrms_app];
    PRINT 'Blanket role memberships removed from [hrms_app].';
END
GO

/* ================================================================
   6. Verification - run this after deployment and keep the output
      with your security evidence.
================================================================ */
PRINT '';
PRINT '--- Effective permissions for [hrms_app_role] ---';

SELECT  dp.permission_name,
        dp.state_desc,
        dp.class_desc,
        COALESCE(s.name, OBJECT_SCHEMA_NAME(dp.major_id)) AS [Schema],
        OBJECT_NAME(dp.major_id)                          AS [Object]
FROM    sys.database_permissions AS dp
LEFT JOIN sys.schemas AS s
       ON s.schema_id = dp.major_id AND dp.class_desc = 'SCHEMA'
WHERE   dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'hrms_app_role')
ORDER BY dp.state_desc, [Schema], dp.permission_name;
GO

/* Expected result: EXECUTE = GRANT on every schema,
   SELECT / INSERT / UPDATE / DELETE / ALTER / REFERENCES = DENY.
   Any other GRANT is a finding worth investigating. */

PRINT '';
PRINT 'HRMS database security policy applied.';
PRINT 'REMINDER: change the [hrms_app] password and store it in';
PRINT 'user-secrets (development) or Key Vault / environment (production).';
GO
