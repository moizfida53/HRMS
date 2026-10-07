/* ================================================================
   HRMS Kuwait - Module 4: Kuwait.usp_EmployeeCompliance_Manage
   ----------------------------------------------------------------
   Kuwait.EmployeeCompliance is a 1:1 child of Employee.Employees, so
   this procedure only needs two actions instead of the usual six:

     GET     returns the compliance row for one employee (or an empty
             result set if none has been entered yet - that is a
             perfectly normal state for a newly created employee, not
             an error)
     UPSERT  inserts the row on first save, updates it on every save
             after that - the caller never needs to know which

   No LIST, no paging, no DELETE of its own: the row is deleted as
   part of Employee.usp_Employee_Manage's DELETE action when the
   employee itself is removed.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Kuwait].[usp_EmployeeCompliance_Manage]
    @Action                     VARCHAR(10),
    @EmployeeId                 BIGINT          = NULL,

    @CivilIdNumber               NVARCHAR(20)   = NULL,
    @CivilIdExpiryDate           DATE           = NULL,

    @PassportNumber              NVARCHAR(30)   = NULL,
    @PassportCountryId           INT            = NULL,
    @PassportExpiryDate          DATE           = NULL,

    @ResidencyNumber             NVARCHAR(30)   = NULL,
    @ResidencyType                NVARCHAR(50)  = NULL,
    @ResidencyExpiryDate          DATE          = NULL,

    @SponsorName                  NVARCHAR(200) = NULL,
    @SponsorFileNumber            NVARCHAR(50)  = NULL,

    @MolFileNumber                NVARCHAR(50)  = NULL,
    @WorkPermitNumber             NVARCHAR(50)  = NULL,
    @WorkPermitExpiryDate         DATE          = NULL,

    @PaciNumber                   NVARCHAR(20)  = NULL,
    @PaciAddress                  NVARCHAR(300) = NULL,

    @DrivingLicenseNumber         NVARCHAR(30)  = NULL,
    @DrivingLicenseExpiryDate     DATE          = NULL,
    @BloodType                    NVARCHAR(5)   = NULL,
    @HealthCertificateExpiry      DATE          = NULL,

    @UserId                       BIGINT        = NULL,

    @ResultCode                   VARCHAR(40)   = NULL OUTPUT,
    @ResultMessage                NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'';

    IF @Action NOT IN ('GET', 'UPSERT')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    IF @EmployeeId IS NULL
    BEGIN
        SELECT @ResultCode    = 'INVALID_REQUEST',
               @ResultMessage = N'An employee must be specified.';
        RETURN;
    END;

    /* ======================= GET =================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  ec.EmployeeId,
                ec.CivilIdNumber,
                ec.CivilIdExpiryDate,
                ec.PassportNumber,
                ec.PassportCountryId,
                pc.CountryName                AS PassportCountryName,
                ec.PassportExpiryDate,
                ec.ResidencyNumber,
                ec.ResidencyType,
                ec.ResidencyExpiryDate,
                ec.SponsorName,
                ec.SponsorFileNumber,
                ec.MolFileNumber,
                ec.WorkPermitNumber,
                ec.WorkPermitExpiryDate,
                ec.PaciNumber,
                ec.PaciAddress,
                ec.DrivingLicenseNumber,
                ec.DrivingLicenseExpiryDate,
                ec.BloodType,
                ec.HealthCertificateExpiry
        FROM        [Kuwait].[EmployeeCompliance] AS ec
        LEFT JOIN   [Core].[Countries]            AS pc ON pc.CountryId = ec.PassportCountryId
        WHERE       ec.EmployeeId = @EmployeeId;

        RETURN;
    END;

    /* ======================= UPSERT ================================= */
    IF @Action = 'UPSERT'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] WHERE EmployeeId = @EmployeeId)
        BEGIN
            UPDATE [Kuwait].[EmployeeCompliance]
               SET CivilIdNumber            = @CivilIdNumber,
                   CivilIdExpiryDate        = @CivilIdExpiryDate,
                   PassportNumber           = @PassportNumber,
                   PassportCountryId        = @PassportCountryId,
                   PassportExpiryDate       = @PassportExpiryDate,
                   ResidencyNumber          = @ResidencyNumber,
                   ResidencyType            = @ResidencyType,
                   ResidencyExpiryDate      = @ResidencyExpiryDate,
                   SponsorName              = @SponsorName,
                   SponsorFileNumber        = @SponsorFileNumber,
                   MolFileNumber            = @MolFileNumber,
                   WorkPermitNumber         = @WorkPermitNumber,
                   WorkPermitExpiryDate     = @WorkPermitExpiryDate,
                   PaciNumber               = @PaciNumber,
                   PaciAddress              = @PaciAddress,
                   DrivingLicenseNumber     = @DrivingLicenseNumber,
                   DrivingLicenseExpiryDate = @DrivingLicenseExpiryDate,
                   BloodType                = @BloodType,
                   HealthCertificateExpiry  = @HealthCertificateExpiry,
                   ModifiedBy               = @UserId,
                   ModifiedDate             = SYSUTCDATETIME()
             WHERE EmployeeId = @EmployeeId;
        END
        ELSE
        BEGIN
            INSERT INTO [Kuwait].[EmployeeCompliance]
                (EmployeeId, CivilIdNumber, CivilIdExpiryDate, PassportNumber, PassportCountryId,
                 PassportExpiryDate, ResidencyNumber, ResidencyType, ResidencyExpiryDate,
                 SponsorName, SponsorFileNumber, MolFileNumber, WorkPermitNumber, WorkPermitExpiryDate,
                 PaciNumber, PaciAddress, DrivingLicenseNumber, DrivingLicenseExpiryDate,
                 BloodType, HealthCertificateExpiry, CreatedBy)
            VALUES
                (@EmployeeId, @CivilIdNumber, @CivilIdExpiryDate, @PassportNumber, @PassportCountryId,
                 @PassportExpiryDate, @ResidencyNumber, @ResidencyType, @ResidencyExpiryDate,
                 @SponsorName, @SponsorFileNumber, @MolFileNumber, @WorkPermitNumber, @WorkPermitExpiryDate,
                 @PaciNumber, @PaciAddress, @DrivingLicenseNumber, @DrivingLicenseExpiryDate,
                 @BloodType, @HealthCertificateExpiry, @UserId);
        END;

        SET @ResultMessage = N'Kuwait compliance details saved.';
        RETURN;
    END;
END;
GO

PRINT 'Kuwait compliance stored procedure created: Kuwait.usp_EmployeeCompliance_Manage.';
GO
