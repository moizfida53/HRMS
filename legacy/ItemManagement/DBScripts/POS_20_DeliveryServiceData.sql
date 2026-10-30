/**********************************************************************************
  POS_20_DeliveryServiceData.sql
  ------------------------------------------------------------------------------
  Feeds the checkout "Delivery / Pickup" step.

  The page was calling the Call Centre web service for this
  (/DmToCallCenterServices/GetDeliveryServiceData). With the order flow moved
  into this database that call returns nothing, which is why the Pickup tab
  showed no branches at all - the list is not hard-coded anywhere, it is
  entirely driven by that response.

  Two result sets, in this order:
      0 - the customer's saved addresses (matched on mobile, or email)
      1 - branches available for pickup

  Column names matter: the JS reads obj.flat in lower case and calls .trim() on
  most string fields, so every string is coalesced to '' rather than left NULL.

  Run after POS_01_Schema.sql.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

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
    DECLARE @M NVARCHAR(50) = NULLIF(LTRIM(RTRIM(ISNULL(@Mobile, ''))), '');
    DECLARE @E NVARCHAR(100) = NULLIF(LTRIM(RTRIM(ISNULL(@Email, ''))), '');

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
    INNER JOIN dbo.tblCustomer        c  ON c.id        = ca.CustomerID
    LEFT  JOIN dbo.tblArea            ar ON ar.AreaID    = ca.AreaID
    WHERE  ISNULL(ca.IsDeleted, 0) = 0
      AND  ISNULL(c.IsDeleted, 0) = 0
      AND  ( ( @M IS NOT NULL
               AND RIGHT(REPLACE(REPLACE(REPLACE(ISNULL(c.mobile, ''), ' ', ''), '-', ''), '+', ''), 8) = @M )
          OR ( @E IS NOT NULL AND c.email = @E ) )
    -- Default address first, then most recent: the one a returning customer
    -- most likely wants is the one already at the top of the list.
    ORDER BY ca.IsDefault DESC, ca.AddressID DESC;

    ----------------------------------------------------------------------------
    -- 1 : pickup branches
    --
    -- Scoped to the brand whose menu is open. Without that a customer scanning
    -- one restaurant's QR code is offered another brand's branches.
    ----------------------------------------------------------------------------
    SELECT   BranchID      = b.id
           , BranchName    = ISNULL(b.branchName,    N'')
           , BranchNameAra = ISNULL(NULLIF(b.branchNameAra, N''), b.branchName)
           , BrandID       = b.brandId
           -- A branch has no area column of its own; the area it sits in is
           -- taken from its delivery mapping. Display only.
           , AreaID        = ISNULL(m.AreaID, 0)
           , AreaName      = ISNULL(ar.AreaName,    N'')
           , AreaNameAra   = ISNULL(ar.AreaNameAra, N'')
    FROM       dbo.tblbranch b
    OUTER APPLY (SELECT TOP (1) am.AreaID
                 FROM   dbo.TblArea_Mapping am
                 WHERE  am.BranchID = b.id
                 ORDER BY am.AreaID) m
    LEFT  JOIN dbo.tblArea ar ON ar.AreaID = m.AreaID
    WHERE  ISNULL(b.IsDeleted, 0) = 0
      AND  (@BrandID IS NULL OR @BrandID = 0 OR b.brandId = @BrandID)
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;
END
GO

PRINT 'sp_GetDeliveryServiceData created.';
GO
