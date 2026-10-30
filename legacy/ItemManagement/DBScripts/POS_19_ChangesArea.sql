/**********************************************************************************
  POS_19_ChangesArea.sql
  ------------------------------------------------------------------------------
  The new-order alert shows customer, mobile and AREA. The delta-poll proc did
  not return the area, so it is added here.

  Run after POS_06_GridProcs.sql.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_GetOrderChanges') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderChanges;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderChanges
      @SinceRowVer BINARY(8)    = NULL
    , @BranchIDs   VARCHAR(200) = NULL
    , @MaxRows     INT          = 200
AS
BEGIN
    SET NOCOUNT ON;

    -- MIN_ACTIVE_ROWVERSION, not @@DBTS: a transaction that has stamped a row
    -- but not yet committed would otherwise be skipped by this poll and never
    -- returned again - the order would simply never appear in the POS.
    DECLARE @Upper BINARY(8) = MIN_ACTIVE_ROWVERSION();

    IF @SinceRowVer IS NULL
    BEGIN
        -- First poll only establishes the watermark, so every order already on
        -- screen is not announced as new.
        SELECT CurrentRowVer = @Upper;
        SELECT TOP 0 InvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END

    DECLARE @Branches TABLE (BranchID INT PRIMARY KEY);
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'') IS NOT NULL
        INSERT INTO @Branches
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END;

    SELECT CurrentRowVer = @Upper;

    SELECT TOP (@MaxRows)
          i.InvoiceNo
        , i.RowVer
        , i.TrackingCode
        , i.RunningOrder
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , i.CustomerName
        , Mobile          = i.MobileText
        , AreaName        = ar.AreaName
        , AreaNameAra     = ar.AreaNameAra
        , i.BranchID
        , BranchName      = b.branchName
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.BillAmount
        , i.FinalAmount
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PrintCount
        , i.Deleted
        , i.InvoiceDate
        -- "New" is a hint for the client, which also keeps its own list of
        -- invoices it has already announced. Without that, a status change a
        -- minute after the order was placed would sound the alarm again.
        , IsNewOrder      = CASE WHEN i.InvoiceDate > DATEADD(MINUTE,-3,GETDATE()) THEN 1 ELSE 0 END
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus     st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN dbo.tblbranch          b  ON b.id             = i.BranchID
    LEFT JOIN dbo.tblCustomerAddress ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea            ar ON ar.AreaID        = ca.AreaID
    WHERE     i.RowVer > @SinceRowVer
      AND     i.RowVer < @Upper
      AND     (@AnyBranch = 1 OR i.BranchID IN (SELECT BranchID FROM @Branches))
    ORDER BY  i.RowVer;
END
GO

PRINT 'sp_POS_GetOrderChanges updated (AreaName, BranchName, OrderTypeName).';
GO
