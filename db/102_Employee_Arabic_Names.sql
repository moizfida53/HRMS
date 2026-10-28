/* =====================================================================
   102_Employee_Arabic_Names.sql  -  HRMS: employee names in Arabic mode
   ---------------------------------------------------------------------
   Run after 101. Safe to re-run.

   In Arabic the pages show an employee's Arabic name; when it is empty
   they keep the English name. Most lists already return both names - this
   procedure gives the Arabic names for the lists that only carry the
   English one (Dashboard alerts and events, Payment Register, Cost
   Allocation).

   1. Employee.usp_EmployeeArabicNames - the Arabic names of the employees given
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('Employee.Employees', 'ArabicName') IS NULL
    RAISERROR (N'Run db/08 first (this script needs Employee.Employees.ArabicName).', 16, 1);
GO

/* ---------------------------------------------------------------------
   1. The Arabic names of the employees given (CSV of ids). Returns
      EmployeeId, ArabicName - only for employees whose Arabic name is
      filled in (the page keeps the English name for the rest).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeArabicNames]
    @EmployeeIds    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH ids AS (
        SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) AS EmployeeId
        FROM   STRING_SPLIT(@EmployeeIds, N',')
        WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL
    )
    SELECT  e.EmployeeId,
            LTRIM(RTRIM(e.ArabicName)) AS ArabicName
    FROM    ids
    JOIN    [Employee].[Employees] AS e ON e.EmployeeId = ids.EmployeeId
    WHERE   NULLIF(LTRIM(RTRIM(e.ArabicName)), N'') IS NOT NULL;
END
GO

PRINT N'102_Employee_Arabic_Names: done.';
GO
