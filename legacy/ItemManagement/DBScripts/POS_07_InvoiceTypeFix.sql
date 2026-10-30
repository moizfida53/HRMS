/**********************************************************************************
  POS_07_InvoiceTypeFix.sql
  ------------------------------------------------------------------------------
  TWO CORRECTNESS PROBLEMS FOUND IN THE POS_05 VERIFICATION OUTPUT.

  --------------------------------------------------------------------------
  PROBLEM 1 - tblInvoiceType_Master holds the REAL head-office channel list
  --------------------------------------------------------------------------
      ID  Name             ShowInCallCentre
      1   On Line Order    1
      2   Dine In          0
      3   Take Away        1
      4   Call Centre      1
      5   Talabat          1

  This is not the placeholder set POS_03 would have seeded (which used IDs 10
  and 11), so real data arrived after that script ran. Consequences:

    a) Web.config still says InvoiceTypeID = 10. Nothing has ID 10. Every QR
       menu order would be stamped with a channel that does not exist, and
       every report grouped by channel would drop them on the floor.

    b) sp_POS_ProcessOrder resolves a NULL @InvoiceTypeID by looking for
       'QR Menu Online' and then falling back to '%Call Centre%'. There is no
       'QR Menu Online' row, so QR orders would be filed as CALL CENTRE --
       silently, and indistinguishably from real call-centre orders.

  'On Line Order' (ID 1) IS the QR menu channel. Section 1 repoints everything
  at it. 'Talabat' at ID 5 confirms these are the genuine HO values: tblInvoice
  already carries CashTalabat and KnetTalabat columns that only make sense
  alongside it.

  --------------------------------------------------------------------------
  PROBLEM 2 - delivery coverage is effectively unconfigured
  --------------------------------------------------------------------------
      Branch 1  Kuwait Magic Pistachio   120 areas
      Branch 2  Assima Mall                1 area
      Branch 3  Gate Mall                  0
      Branch 4  Sulibikate                 0
      Branch 5  Sama Mall                  0
      Branch 6  City Centre                0
      Branch 7  Sabah Al Ahmad             0

  Five of seven branches serve NO delivery area at all, and branch 1 covers
  essentially the whole country. That is the tblArea.BranchID default showing
  through, not a real delivery map. Until it is corrected:
      - the branch-serves-area warning is meaningless
      - branch transfer cannot be validated
      - any "which branch should take this order" logic is wrong

  Section 3 provides the template to fix it. It is data entry, not code, and it
  needs someone who knows the actual delivery boundaries.
**********************************************************************************/

SET NOCOUNT ON;
GO

/*==============================================================================
  SECTION 1 - INVOICE TYPE
==============================================================================*/

DECLARE @OnlineID INT;

SELECT TOP 1 @OnlineID = ID FROM dbo.tblInvoiceType_Master
WHERE  Name IN (N'On Line Order', N'Online Order', N'QR Menu Online')
ORDER BY ID;

IF @OnlineID IS NULL
BEGIN
    INSERT INTO dbo.tblInvoiceType_Master (Name, ShowInCallCentre) VALUES (N'On Line Order', 1);
    SET @OnlineID = CAST(SCOPE_IDENTITY() AS INT);
    PRINT '1.1  No online channel found - created one';
END

PRINT '1.2  >>> SET Web.config  <add key="InvoiceTypeID" value="' + CAST(@OnlineID AS VARCHAR(10)) + '" />';
PRINT '     (it currently says 10, which matches nothing)';

-- Clean up any orders already stamped with a channel that does not exist.
IF EXISTS (SELECT 1 FROM dbo.tblInvoice i
           WHERE i.InvoiceType IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master m WHERE m.ID = i.InvoiceType))
BEGIN
    UPDATE i SET InvoiceType = @OnlineID
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceType IS NOT NULL
      AND  NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master m WHERE m.ID = i.InvoiceType);
    PRINT '1.3  Repaired ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' invoice(s) pointing at a non-existent channel';
END
ELSE PRINT '1.3  No invoices with an invalid channel';
GO


/*==============================================================================
  SECTION 2 - PATCH sp_POS_ProcessOrder's fallback

  Only the channel-resolution block changes. Apply this edit to
  POS_04_ProcessOrder_v2.sql and re-run that file, so the source on disk and
  the database do not drift apart.

  FIND:
      IF @InvoiceTypeID IS NULL
          SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master WHERE Name = N'QR Menu Online';
      IF @InvoiceTypeID IS NULL
          SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master WHERE Name LIKE N'%Call Centre%';

  REPLACE WITH:
      IF @InvoiceTypeID IS NULL
          SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master
          WHERE  Name IN (N'On Line Order', N'Online Order', N'QR Menu Online')
          ORDER BY ID;
      -- Deliberately NO fallback to Call Centre. Filing a QR order as a
      -- call-centre order is worse than failing loudly: it is invisible and it
      -- corrupts every channel report from that moment on.
      IF @InvoiceTypeID IS NULL
          SET @InvoiceTypeID = NULL;   -- proc will insert NULL; grid shows "unknown channel"

  A guard is added below so an invalid channel can never be stored again.
==============================================================================*/

-- Reject invalid channels at the table, not just in the proc.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblInvoice_InvoiceType')
BEGIN
    -- Only safe because every existing row was repaired in section 1.
    IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoice i
                   WHERE i.InvoiceType IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master m WHERE m.ID = i.InvoiceType))
    BEGIN
        ALTER TABLE dbo.tblInvoice WITH CHECK
            ADD CONSTRAINT FK_tblInvoice_InvoiceType
            FOREIGN KEY (InvoiceType) REFERENCES dbo.tblInvoiceType_Master (ID);
        PRINT '2.1  FK_tblInvoice_InvoiceType added - an invalid channel is now impossible';
    END
    ELSE PRINT '2.1  !! Invalid channel values remain - FK not added';
END
ELSE PRINT '2.1  FK_tblInvoice_InvoiceType already exists';
GO

-- Same protection for payment type and order status.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblInvoice_PaymentType')
   AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoice i
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType p WHERE p.ID = i.PaymentType))
BEGIN
    ALTER TABLE dbo.tblInvoice WITH CHECK
        ADD CONSTRAINT FK_tblInvoice_PaymentType
        FOREIGN KEY (PaymentType) REFERENCES dbo.tblInvoicePaymentType (ID);
    PRINT '2.2  FK_tblInvoice_PaymentType added';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_tblInvoice_OrderStatus')
   AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoice i
                   WHERE i.OrderStatusID IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM dbo.tblOrderStatus s WHERE s.OrderStatusID = i.OrderStatusID))
BEGIN
    ALTER TABLE dbo.tblInvoice WITH CHECK
        ADD CONSTRAINT FK_tblInvoice_OrderStatus
        FOREIGN KEY (OrderStatusID) REFERENCES dbo.tblOrderStatus (OrderStatusID);
    PRINT '2.3  FK_tblInvoice_OrderStatus added';
END
GO


/*==============================================================================
  SECTION 3 - DELIVERY AREA COVERAGE  (data entry required)

  Uncomment and edit. TblArea_Mapping is many-to-many on purpose: overlapping
  coverage is normal, and the POS picks the nearest or least-loaded branch.
==============================================================================*/

/*
-- Step 1: see the areas, and who currently covers them
SELECT   a.AreaID, a.AreaName, a.AreaNameAra, a.DeliveryCharges,
         CoveredBy = STUFF((SELECT ', ' + b.branchName
                            FROM dbo.TblArea_Mapping m
                            JOIN dbo.tblbranch b ON b.id = m.BranchID
                            WHERE m.AreaID = a.AreaID
                            FOR XML PATH('')),1,2,'')
FROM     dbo.tblArea a
ORDER BY a.AreaName;

-- Step 2: clear the placeholder mapping
DELETE FROM dbo.TblArea_Mapping;

-- Step 3: assign areas to branches, e.g.
INSERT INTO dbo.TblArea_Mapping (AreaID, BranchID)
SELECT a.AreaID, 4                                    -- Sulibikate
FROM   dbo.tblArea a
WHERE  a.AreaName IN (N'Sulaibikhat', N'Doha', N'Jahra');

INSERT INTO dbo.TblArea_Mapping (AreaID, BranchID)
SELECT a.AreaID, 2                                    -- Assima Mall
FROM   dbo.tblArea a
WHERE  a.AreaName IN (N'Sharq', N'Kuwait City', N'Dasman');

-- Step 4: confirm no area is left with nobody serving it
SELECT   a.AreaID, a.AreaName
FROM     dbo.tblArea a
WHERE    NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping m WHERE m.AreaID = a.AreaID)
ORDER BY a.AreaName;
*/

-- Current coverage
SELECT   b.id AS BranchID, b.branchName, AreasServed = COUNT(m.AreaID)
FROM     dbo.tblbranch b
LEFT JOIN dbo.TblArea_Mapping m ON m.BranchID = b.id
GROUP BY b.id, b.branchName
ORDER BY b.id;

SELECT   UncoveredAreas = COUNT(*)
FROM     dbo.tblArea a
WHERE    NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping m WHERE m.AreaID = a.AreaID);

PRINT '';
PRINT '################ POS_07 COMPLETE ################';
GO
