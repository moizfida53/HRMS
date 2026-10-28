/* =====================================================================
   Loading
   ===================================================================== */
DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
DECLARE @KuwaitId INT = (SELECT TOP (1) CountryId FROM [Core].[Countries]
                         WHERE CountryCode IN (N'KW', N'KWT') OR CountryName LIKE N'Kuwait%'
                         ORDER BY CASE WHEN CountryCode IN (N'KW', N'KWT') THEN 0 ELSE 1 END);
DECLARE @KwdId INT = (SELECT TOP (1) CurrencyId FROM [Core].[Currencies] WHERE CurrencyCode = N'KWD');

/* nationalities: reuse by ISO code or name, add the missing ones (outside the
   transaction - if Core.Countries has other required columns the employee's
   nationality is just left blank) */
BEGIN TRY
    INSERT INTO [Core].[Countries] (CountryCode, CountryName, IsActive)
    SELECT m.CountryCode, m.CountryName, 1
    FROM   @CountryMap AS m
    WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Countries] AS c
                       WHERE c.CountryCode = m.CountryCode OR c.CountryName = m.CountryName OR c.CountryName LIKE m.CountryName + N'%');
END TRY
BEGIN CATCH
    PRINT N'NOTE: could not add missing countries (' + ERROR_MESSAGE() + N') - nationality left blank for those employees.';
END CATCH;
UPDATE m
   SET CountryId = (SELECT TOP (1) c.CountryId FROM [Core].[Countries] AS c
                    WHERE c.CountryCode = m.CountryCode OR c.CountryName = m.CountryName OR c.CountryName LIKE m.CountryName + N'%'
                    ORDER BY CASE WHEN c.CountryCode = m.CountryCode THEN 0 WHEN c.CountryName = m.CountryName THEN 1 ELSE 2 END)
FROM @CountryMap AS m;

SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

/* ---------------------------------------------------------------------
   1. Companies (+ a default monthly payroll calendar, pay components,
      leave types - the app's own seed procedures)
   --------------------------------------------------------------------- */
INSERT INTO [Core].[Companies] (CompanyCode, CompanyName, LegalName, CountryId, DefaultCurrencyId, IsActive)
SELECT c.Code, c.NameEn, c.LegalAr, @KuwaitId, @KwdId, 1
FROM   @Company AS c
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Companies] AS x WHERE x.CompanyCode = c.Code AND x.Deleted = 0);
DECLARE @CompaniesAdded INT = @@ROWCOUNT;

UPDATE x SET CompanyName = c.NameEn, LegalName = c.LegalAr
FROM   [Core].[Companies] AS x
JOIN   @Company AS c ON c.Code = x.CompanyCode
WHERE  x.Deleted = 0;

UPDATE c SET CompanyId = x.CompanyId
FROM   @Company AS c
JOIN   [Core].[Companies] AS x ON x.CompanyCode = c.Code AND x.Deleted = 0;

INSERT INTO [Payroll].[PayrollCalendars]
    (CompanyId, CalendarCode, CalendarName, ArabicName, PayFrequency, FirstPeriodStartDate, CutOffDay, PaymentDay,
     PaymentMonthOffset, WorkingDaysBasis, FixedDaysPerMonth, CurrencyId, Description, IsDefault, IsActive, CreatedBy)
SELECT c.CompanyId, N'MONTHLY', N'Monthly Payroll', N'الرواتب الشهرية', 'MONTHLY',
       DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), 31, 31, 0, 'FIXED', 26, @KwdId,
       N'Added by the data import (db/92) - check the cut-off and payment day.', 1, 1, @UserId
FROM   @Company AS c
WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] AS k WHERE k.CompanyId = c.CompanyId AND k.Deleted = 0);

DECLARE @cid INT;
DECLARE cc CURSOR LOCAL FAST_FORWARD FOR SELECT CompanyId FROM @Company;
OPEN cc; FETCH NEXT FROM cc INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @cid, @UserId = @UserId;
    IF OBJECT_ID(N'[Leave].[usp_LeaveType_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Leave].[usp_LeaveType_SeedDefaults] @CompanyId = @cid, @UserId = @UserId;
    FETCH NEXT FROM cc INTO @cid;
END;
CLOSE cc; DEALLOCATE cc;

/* ---------------------------------------------------------------------
   2. Issuing authorities and company document types
   --------------------------------------------------------------------- */
INSERT INTO [Documents].[IssuingAuthorities] (AuthorityName, ArabicName, ShortName, IsGovernment, SortOrder)
SELECT a.AuthorityName, a.ArabicName, a.ShortName, 1, 30 + a.n
FROM  (VALUES (N'National Fund for SME Development', N'الصندوق الوطني لرعاية وتنمية المشروعات الصغيرة والمتوسطة', N'NFSMED', 1),
              (N'General Traffic Department (Ministry of Interior)', N'الإدارة العامة للمرور - وزارة الداخلية', N'GTD', 2),
              (N'Central Agency for Public Tenders', N'الجهاز المركزي للمناقصات العامة', N'CAPT', 3)) AS a (AuthorityName, ArabicName, ShortName, n)
WHERE NOT EXISTS (SELECT 1 FROM [Documents].[IssuingAuthorities] AS x
                  WHERE x.Deleted = 0 AND (x.ShortName = a.ShortName OR x.AuthorityName = a.AuthorityName));

DECLARE @PrivateAuthority INT = (SELECT TOP (1) IssuingAuthorityId FROM [Documents].[IssuingAuthorities]
                                 WHERE IsGovernment = 0 AND Deleted = 0 ORDER BY IssuingAuthorityId);

INSERT INTO [Documents].[OrganizationDocumentTypes]
    (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, SortOrder, IsActive, CreatedBy)
SELECT t.TypeName, t.ArabicName, t.Category, 0, 1, 1, 1, 'M2,M1,W2,D0',
       (SELECT ISNULL(MAX(SortOrder), 0) FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)
           + ROW_NUMBER() OVER (ORDER BY t.TypeName), 1, @UserId
FROM   @TypeDef AS t
WHERE  NOT EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes] AS x WHERE x.TypeName = t.TypeName AND x.Deleted = 0);

UPDATE x
   SET IssuingAuthorityId = COALESCE(a.IssuingAuthorityId, @PrivateAuthority)
FROM   [Documents].[OrganizationDocumentTypes] AS x
JOIN   @TypeDef AS t ON t.TypeName = x.TypeName
LEFT JOIN [Documents].[IssuingAuthorities] AS a ON a.ShortName = t.AuthorityShort AND a.Deleted = 0
WHERE  x.Deleted = 0 AND x.IssuingAuthorityId IS NULL;

/* ---------------------------------------------------------------------
   3. Company documents (licences): the current one of each type
   --------------------------------------------------------------------- */
DECLARE @DocRows TABLE (Seq INT PRIMARY KEY, CompanyId INT, TypeId INT, CurrentId BIGINT NULL);
INSERT INTO @DocRows (Seq, CompanyId, TypeId, CurrentId)
SELECT d.Seq, c.CompanyId, x.OrgDocumentTypeId,
       (SELECT TOP (1) o.OrgDocumentId FROM [Documents].[OrganizationDocuments] AS o
        WHERE o.CompanyId = c.CompanyId AND o.OrgDocumentTypeId = x.OrgDocumentTypeId AND o.State = 'C' AND o.Deleted = 0)
FROM   @Doc AS d
JOIN   @Company AS c ON c.Code = d.CompanyCode
JOIN   @TypeDef AS t ON t.TypeKey = d.TypeKey
JOIN   [Documents].[OrganizationDocumentTypes] AS x ON x.TypeName = t.TypeName AND x.Deleted = 0;

UPDATE o
   SET DocumentNumber = d.DocNumber, IssuingAuthority = d.Authority, IssueDate = d.IssueDate, ExpiryDate = d.ExpiryDate,
       Notes = d.Notes, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Documents].[OrganizationDocuments] AS o
JOIN   @DocRows AS r ON r.CurrentId = o.OrgDocumentId
JOIN   @Doc AS d ON d.Seq = r.Seq;

INSERT INTO [Documents].[OrganizationDocuments]
    (CompanyId, OrgDocumentTypeId, State, DocumentNumber, IssuingAuthority, IssueDate, ExpiryDate, Notes, CreatedBy)
SELECT r.CompanyId, r.TypeId, 'C', d.DocNumber, d.Authority, d.IssueDate, d.ExpiryDate, d.Notes, @UserId
FROM   @DocRows AS r
JOIN   @Doc AS d ON d.Seq = r.Seq
WHERE  r.CurrentId IS NULL;

/* ---------------------------------------------------------------------
   4. Vehicles -> Assets (matched on company + plate)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM [Assets].[AssetTypes] WHERE TypeName = N'Trucks & Pickups' AND Deleted = 0)
    INSERT INTO [Assets].[AssetTypes] (TypeName, ArabicName, Icon, HasExpiryDate, ExpiryLabel, ExpiryLabelAr, AlertRules, SortOrder, IsActive, CreatedBy)
    VALUES (N'Trucks & Pickups', N'شاحنات ونصف نقل', 'CAR', 1, N'Registration (Daftar) expiry', N'انتهاء الدفتر (الترخيص)', 'M1,W2,W1,D0',
            (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Assets].[AssetTypes] WHERE Deleted = 0), 1, @UserId);

UPDATE a
   SET AssetTypeId = t.AssetTypeId, Brand = v.Brand, Model = v.Model, Color = v.Color, ExpiryDate = v.ExpiryDate,
       Notes = v.Notes, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Assets].[Assets] AS a
JOIN   @Company AS c ON c.CompanyId = a.CompanyId
JOIN   @Vehicle AS v ON v.CompanyCode = c.Code AND v.Plate = a.SerialNumber
JOIN   [Assets].[AssetTypes] AS t ON t.TypeName = v.TypeName AND t.Deleted = 0
WHERE  a.Deleted = 0;

INSERT INTO [Assets].[Assets] (CompanyId, AssetTypeId, AssetCode, Brand, Model, Color, SerialNumber, ExpiryDate, Notes, IsActive, CreatedBy)
SELECT c.CompanyId, t.AssetTypeId, N'VEH-' + REPLACE(v.Plate, N'/', N'-'), v.Brand, v.Model, v.Color, v.Plate, v.ExpiryDate, v.Notes, 1, @UserId
FROM   @Vehicle AS v
JOIN   @Company AS c ON c.Code = v.CompanyCode
JOIN   [Assets].[AssetTypes] AS t ON t.TypeName = v.TypeName AND t.Deleted = 0
WHERE  NOT EXISTS (SELECT 1 FROM [Assets].[Assets] AS a WHERE a.CompanyId = c.CompanyId AND a.SerialNumber = v.Plate AND a.Deleted = 0);

/* ---------------------------------------------------------------------
   5. Designations (per company) and the "works at" locations
   --------------------------------------------------------------------- */
INSERT INTO [Core].[Designations] (CompanyId, DesignationCode, DesignationName, ArabicName, GradeId, Description, IsActive, CreatedBy)
SELECT DISTINCT c.CompanyId, j.JobCode, j.NameEn, j.NameAr, NULL, N'Work permit job title (data import db/92).', 1, @UserId
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
JOIN   @Job AS j ON j.JobCode = i.JobCode
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Designations] AS d
                   WHERE d.CompanyId = c.CompanyId AND (d.DesignationCode = j.JobCode OR d.DesignationName = j.NameEn));

INSERT INTO [Core].[Locations] (CompanyId, BranchId, LocationCode, LocationName, LocationType, IsActive, CreatedBy)
SELECT DISTINCT c.CompanyId, NULL, N'LOC-' + w.Code, w.NameEn, N'Workplace', 1, @UserId
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
JOIN   @Company AS w ON w.Code = i.WorkplaceCode
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Locations] AS l WHERE l.CompanyId = c.CompanyId AND l.LocationCode = N'LOC-' + w.Code);

/* ---------------------------------------------------------------------
   6. Employees (matched on company + civil ID, else company + code)
   --------------------------------------------------------------------- */
DECLARE @Rows TABLE (Sl INT PRIMARY KEY, EmployeeId BIGINT NULL, CompanyId INT, CountryId INT, DesignationId INT, LocationId INT);
INSERT INTO @Rows (Sl, CompanyId, CountryId, DesignationId, LocationId, EmployeeId)
SELECT i.Sl, c.CompanyId, m.CountryId,
       (SELECT TOP (1) d.DesignationId FROM [Core].[Designations] AS d
        WHERE d.CompanyId = c.CompanyId AND d.DesignationCode = i.JobCode),
       (SELECT TOP (1) l.LocationId FROM [Core].[Locations] AS l
        WHERE l.CompanyId = c.CompanyId AND l.LocationCode = N'LOC-' + i.WorkplaceCode),
       COALESCE((SELECT TOP (1) e.EmployeeId FROM [Employee].[Employees] AS e
                 JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = e.EmployeeId
                 WHERE e.CompanyId = c.CompanyId AND k.CivilIdNumber = i.CivilIdNumber),
                (SELECT TOP (1) e.EmployeeId FROM [Employee].[Employees] AS e
                 WHERE e.CompanyId = c.CompanyId AND e.EmployeeCode = i.EmployeeCode))
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
LEFT JOIN @CountryMap AS m ON m.Nationality = i.Nationality;

UPDATE e
   SET EmployeeCode = i.EmployeeCode, EmployeeNo = i.EmployeeCode,
       FirstName = i.FirstName, MiddleName = i.MiddleName, LastName = i.LastName, ArabicName = i.ArabicName,
       Gender = i.Gender, DateOfBirth = i.DateOfBirth, NationalityCountryId = r.CountryId,
       DesignationId = r.DesignationId, WorkLocationId = r.LocationId,
       ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Employee].[Employees] AS e
JOIN   @Rows AS r ON r.EmployeeId = e.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl;
DECLARE @EmployeesUpdated INT = @@ROWCOUNT;

INSERT INTO [Employee].[Employees]
    (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, ArabicName, Gender, DateOfBirth, NationalityCountryId,
     CompanyId, DesignationId, WorkLocationId, EmploymentType, EmploymentStatus, FatherIsDeceased, IsDeleted, CreatedBy)
SELECT i.EmployeeCode, i.EmployeeCode, i.FirstName, i.MiddleName, i.LastName, i.ArabicName, i.Gender, i.DateOfBirth, r.CountryId,
       r.CompanyId, r.DesignationId, r.LocationId, N'Full-Time', N'Active', 0, 0, @UserId
FROM   @Import AS i
JOIN   @Rows AS r ON r.Sl = i.Sl
WHERE  r.EmployeeId IS NULL;
DECLARE @EmployeesAdded INT = @@ROWCOUNT;

UPDATE r SET EmployeeId = e.EmployeeId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
JOIN   [Employee].[Employees] AS e ON e.CompanyId = r.CompanyId AND e.EmployeeCode = i.EmployeeCode
WHERE  r.EmployeeId IS NULL;

/* Kuwait compliance (1:1) - only the columns the sheet carries */
UPDATE k
   SET CivilIdNumber = i.CivilIdNumber, CivilIdExpiryDate = i.CivilIdExpiry, ResidencyExpiryDate = i.CivilIdExpiry,
       PassportNumber = i.PassportNumber, PassportCountryId = r.CountryId, PassportExpiryDate = i.PassportExpiry,
       SponsorName = i.SponsorName, WorkPermitSalary = i.PermitSalary,
       WorkPermitDesignation = j.NameEn, WorkPermitDesignationAr = j.NameAr,
       ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Kuwait].[EmployeeCompliance] AS k
JOIN   @Rows AS r ON r.EmployeeId = k.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl
LEFT JOIN @Job AS j ON j.JobCode = i.JobCode;

INSERT INTO [Kuwait].[EmployeeCompliance]
    (EmployeeId, CivilIdNumber, CivilIdExpiryDate, ResidencyExpiryDate, PassportNumber, PassportCountryId, PassportExpiryDate,
     SponsorName, WorkPermitSalary, WorkPermitDesignation, WorkPermitDesignationAr, CreatedBy)
SELECT r.EmployeeId, i.CivilIdNumber, i.CivilIdExpiry, i.CivilIdExpiry, i.PassportNumber, r.CountryId, i.PassportExpiry,
       i.SponsorName, i.PermitSalary, j.NameEn, j.NameAr, @UserId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
LEFT JOIN @Job AS j ON j.JobCode = i.JobCode
WHERE  NOT EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] AS k WHERE k.EmployeeId = r.EmployeeId);

/* payroll (1:1) - the contract basic salary; allowances and bank are not in the sheet */
UPDATE p SET BasicSalary = i.BasicSalary, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Employee].[EmployeePayroll] AS p
JOIN   @Rows AS r ON r.EmployeeId = p.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl;

INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, CreatedBy)
SELECT r.EmployeeId, i.BasicSalary, @UserId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
WHERE  NOT EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] AS p WHERE p.EmployeeId = r.EmployeeId);

COMMIT TRANSACTION;

/* =====================================================================
   What was loaded, and what still needs your input
   ===================================================================== */
PRINT CONCAT(N'Import finished: ', @CompaniesAdded, N' companies added, ', @EmployeesAdded, N' employees added, ',
             @EmployeesUpdated, N' updated.');

SELECT  c.Code AS Company, x.CompanyName, x.LegalName,
        (SELECT COUNT(1) FROM [Employee].[Employees] AS e WHERE e.CompanyId = c.CompanyId AND e.IsDeleted = 0) AS Employees,
        (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] AS o WHERE o.CompanyId = c.CompanyId AND o.Deleted = 0 AND o.State = 'C') AS Documents,
        (SELECT COUNT(1) FROM [Assets].[Assets] AS a WHERE a.CompanyId = c.CompanyId AND a.Deleted = 0) AS Vehicles
FROM    @Company AS c
JOIN    [Core].[Companies] AS x ON x.CompanyId = c.CompanyId
ORDER BY c.Code;

SELECT  i.CompanyCode AS Company, i.EmployeeCode AS [New code (not in the sheet)], i.FirstName + N' ' + ISNULL(i.LastName, N'') AS Employee
FROM    @Import AS i WHERE i.CodeGenerated = 1 ORDER BY i.CompanyCode, i.EmployeeCode;

SELECT  i.CompanyCode AS Company, i.EmployeeCode AS Code, i.FirstName + N' ' + ISNULL(i.LastName, N'') AS Employee,
        CASE WHEN i.Nationality IS NULL THEN N'nationality missing' END AS [Missing],
        CASE i.PassportCustody WHEN N'✓' THEN N'✓' WHEN N'X' THEN N'X' END AS [Passport status (sheet)],
        i.SheetNotes AS [Sheet notes]
FROM    @Import AS i
WHERE   i.Nationality IS NULL OR i.SheetNotes IS NOT NULL
ORDER BY i.CompanyCode, i.EmployeeCode;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(2000) = CONCAT(N'Import rolled back - nothing was saved. ', ERROR_MESSAGE(), N' (line ', ERROR_LINE(), N')');
    RAISERROR (@Err, 16, 1);
END CATCH;
GO
