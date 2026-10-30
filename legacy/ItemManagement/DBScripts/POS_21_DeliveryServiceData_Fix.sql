/**********************************************************************************
  POS_21_DeliveryServiceData_Fix.sql
  ------------------------------------------------------------------------------
  WHY THIS EXISTS
  ---------------------------------------------------------------------------
  The checkout "Delivery / Pickup" step shows

        "Service Not Connected, Please Contact Your Manager."

  That text is the client-side rendering of a *server-side exception*. In
  MainJs/ItemsViewNew/DeliveryService.js the AJAX success handler falls into
  its else branch whenever the action returns { Message = "Error,Contact Your
  Manager." }, and ItemsViewNewController.GetDeliveryServiceData only returns
  that from its catch block. So the page is not "not connected" to anything -
  the call to sp_GetDeliveryServiceData threw.

  The two realistic causes, in order of likelihood:

    1. POS_20_DeliveryServiceData.sql was never executed against Pistachio_v4,
       so the procedure does not exist. "Could not find stored procedure" is
       caught and reported as the generic message.

    2. It was executed but CREATE PROCEDURE failed, because POS_20 references
       tblbranch columns that were assumed rather than verified: SEQ_NUM,
       branchNameAra, brandId. Column-level errors are raised at CREATE time
       (unlike missing tables, which defer), so a single wrong column name
       leaves no procedure behind at all - the same end result as (1).

  SECTION 1 tells you which of the two happened.
  SECTION 2 recreates the procedure so that neither can happen again: every
  optional tblbranch column is probed with COL_LENGTH and only included in the
  statement if it is really there. The result shape is unchanged.

  RUN: SSMS against Pistachio_v4 (or sqlcmd -S .\TMM -d Pistachio_v4 ...),
       results-to-text so the SECTION 1 PRINTs are readable.
       Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - DIAGNOSIS
==============================================================================*/
PRINT '===== SECTION 1 : diagnosis =====';

IF OBJECT_ID('dbo.sp_GetDeliveryServiceData') IS NULL
    PRINT '  sp_GetDeliveryServiceData : MISSING  <-- this alone causes the error';
ELSE
    PRINT '  sp_GetDeliveryServiceData : present';

-- Tables the procedure depends on.
SELECT  TableName = t.n
      , Status    = CASE WHEN OBJECT_ID('dbo.' + t.n) IS NULL THEN 'MISSING' ELSE 'ok' END
FROM   (VALUES ('tblCustomer'), ('tblCustomerAddress'), ('tblbranch'),
               ('tblArea'), ('TblArea_Mapping')) AS t(n);

-- Columns POS_20 assumed on tblbranch. Anything MISSING here is why the
-- CREATE PROCEDURE in POS_20 failed.
SELECT  ColumnOnTblBranch = c.n
      , Status = CASE WHEN COL_LENGTH('dbo.tblbranch', c.n) IS NULL
                      THEN 'MISSING' ELSE 'ok' END
FROM   (VALUES ('id'), ('branchName'), ('branchNameAra'),
               ('brandId'), ('IsDeleted'), ('SEQ_NUM')) AS c(n);

-- What the branch list will actually be able to return.
SELECT BranchRows = COUNT(*) FROM dbo.tblbranch;
GO


/*==============================================================================
  SECTION 2 - PROCEDURE, REBUILT DEFENSIVELY

  Two result sets, in this order, exactly as the JS expects:
      0 - the customer's saved addresses (matched on mobile, or email)
      1 - branches available for pickup

  Column names matter: BindCustomerAddressList reads obj.flat in lower case and
  calls .trim() on most string fields, so every string is coalesced to ''.
==============================================================================*/
IF OBJECT_ID('dbo.sp_GetDeliveryServiceData') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetDeliveryServiceData;
GO

CREATE PROCEDURE dbo.sp_GetDeliveryServiceData
      @Mobile  NVARCHAR(50)  = NULL
    , @Email   NVARCHAR(100) = NULL
    , @BrandID INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Mobiles are entered with spaces, dashes and sometimes a +965 prefix.
    -- Comparing them raw means a returning customer looks like a new one, so
    -- both sides are reduced to digits before matching.
    DECLARE @M NVARCHAR(50)  = NULLIF(LTRIM(RTRIM(ISNULL(@Mobile, ''))), '');
    DECLARE @E NVARCHAR(100) = NULLIF(LTRIM(RTRIM(ISNULL(@Email,  ''))), '');

    IF @M IS NOT NULL
    BEGIN
        SET @M = REPLACE(REPLACE(REPLACE(REPLACE(@M, ' ', ''), '-', ''), '(', ''), ')', '');
        IF LEFT(@M, 1) = '+' SET @M = SUBSTRING(@M, 2, 50);
        -- Keep the last 8 digits: that is the significant part of a Kuwaiti
        -- number whether or not the country code was typed.
        IF LEN(@M) > 8 SET @M = RIGHT(@M, 8);
    END

    ----------------------------------------------------------------------------
    -- 0 : saved addresses
    ----------------------------------------------------------------------------
    SELECT TOP (10)
           AddressID      = ca.AddressID
         , CustomerId     = ca.CustomerID
         , AreaID         = ISNULL(ca.AreaID, 0)
         , AreaName       = ISNULL(ar.AreaName, N'')
         , AreaNameAra    = ISNULL(ar.AreaNameAra, N'')
         , Block          = ISNULL(ca.Block, N'')
         , Street         = ISNULL(ca.Street, N'')
         , Lane           = ISNULL(ca.Lane, N'')
         , Building       = ISNULL(ca.Building, N'')
         , Floor          = ISNULL(ca.Floor, N'')
         -- lower case on purpose: BindCustomerAddressList reads obj.flat
         , flat           = ISNULL(ca.Flat, N'')
         , HouseNo        = ISNULL(ca.HouseNo, N'')
         , AddressRemarks = ISNULL(ca.AddressRemark, N'')
         , Latitude       = ISNULL(ca.Lat, N'')
         , Longitude      = ISNULL(ca.Lng, N'')
    FROM       dbo.tblCustomerAddress ca
    INNER JOIN dbo.tblCustomer        c  ON c.id     = ca.CustomerID
    LEFT  JOIN dbo.tblArea            ar ON ar.AreaID = ca.AreaID
    WHERE  ISNULL(ca.IsDeleted, 0) = 0
      AND  ISNULL(c.IsDeleted, 0)  = 0
      AND  ( ( @M IS NOT NULL
               AND RIGHT(REPLACE(REPLACE(REPLACE(ISNULL(c.mobile, ''), ' ', ''), '-', ''), '+', ''), 8) = @M )
          OR ( @E IS NOT NULL AND c.email = @E ) )
    -- Default address first, then most recent: the one a returning customer
    -- most likely wants is the one already at the top of the list.
    ORDER BY ca.IsDefault DESC, ca.AddressID DESC;

    ----------------------------------------------------------------------------
    -- 1 : pickup branches
    --
    -- Built as dynamic SQL purely so that branchNameAra / brandId / SEQ_NUM /
    -- IsDeleted are optional. On a database where one of them is absent the
    -- static version of this statement would not compile, and a procedure that
    -- fails to compile is indistinguishable, from the browser, from a server
    -- that is down - which is the bug this file is fixing.
    --
    -- Scoped to the brand whose menu is open. Without that a customer scanning
    -- one restaurant's QR code is offered another brand's branches.
    ----------------------------------------------------------------------------
    DECLARE @sql   NVARCHAR(MAX);
    DECLARE @NameAra NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'branchNameAra') IS NOT NULL
             THEN N'ISNULL(NULLIF(b.branchNameAra, N''''), ISNULL(b.branchName, N''''))'
             ELSE N'ISNULL(b.branchName, N'''')' END;
    DECLARE @Brand   NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'brandId') IS NOT NULL
             THEN N'ISNULL(b.brandId, 0)' ELSE N'0' END;
    DECLARE @BrandWhere NVARCHAR(400) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'brandId') IS NOT NULL
             THEN N' AND (@pBrandID IS NULL OR @pBrandID = 0 OR b.brandId = @pBrandID)'
             ELSE N'' END;
    DECLARE @DelWhere NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'IsDeleted') IS NOT NULL
             THEN N' AND ISNULL(b.IsDeleted, 0) = 0' ELSE N'' END;
    DECLARE @OrderBy NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'SEQ_NUM') IS NOT NULL
             THEN N'ISNULL(b.SEQ_NUM, 9999), b.branchName' ELSE N'b.branchName' END;

    SET @sql = N'
        SELECT   BranchID      = b.id
               , BranchName    = ISNULL(b.branchName, N'''')
               , BranchNameAra = ' + @NameAra + N'
               , BrandID       = ' + @Brand + N'
               -- A branch has no area column of its own; the area it sits in is
               -- taken from its delivery mapping. Display only.
               , AreaID        = ISNULL(m.AreaID, 0)
               , AreaName      = ISNULL(ar.AreaName,    N'''')
               , AreaNameAra   = ISNULL(ar.AreaNameAra, N'''')
        FROM       dbo.tblbranch b
        OUTER APPLY (SELECT TOP (1) am.AreaID
                     FROM   dbo.TblArea_Mapping am
                     WHERE  am.BranchID = b.id
                     ORDER BY am.AreaID) m
        LEFT  JOIN dbo.tblArea ar ON ar.AreaID = m.AreaID
        WHERE  1 = 1' + @DelWhere + @BrandWhere + N'
        ORDER BY ' + @OrderBy + N';';

    EXEC sp_executesql @sql, N'@pBrandID INT', @pBrandID = @BrandID;
END
GO

PRINT 'sp_GetDeliveryServiceData recreated (defensive version).';
GO


/*==============================================================================
  SECTION 3 - SMOKE TEST

  Two result sets should come back. The second one being empty means the
  procedure is fine and tblbranch simply has no branch for that brand - a data
  problem, not a code one. Pass a real BrandID to check that case properly.
==============================================================================*/
PRINT '===== SECTION 3 : smoke test (no customer, all brands) =====';
EXEC dbo.sp_GetDeliveryServiceData @Mobile = NULL, @Email = NULL, @BrandID = NULL;
GO
