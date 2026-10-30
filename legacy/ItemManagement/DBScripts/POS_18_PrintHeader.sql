/**********************************************************************************
  POS_18_PrintHeader.sql
  ------------------------------------------------------------------------------
  Adds the few fields the printed receipt needs that the details proc did not
  return: the brand's telephone, its currency label, and the address Lane.

  Only result set 0 (the header) changes.

  Run after POS_14_DetailLines.sql.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_GetOrderDetails') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderDetails;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderDetails
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: header
    SELECT
          i.InvoiceNo, i.TrackingCode, i.RunningOrder, i.InvoiceDate, i.PromisedTime
        , i.DeliveryDate, i.CustomerName, Mobile = i.MobileText, i.CustomerId
        , i.BranchID, BranchName = b.branchName, BranchNameAra = b.branchNameAra
        , i.BrandID, BrandName = br.BrandName, BrandNameAra = br.BrandNameAra
        -- for the receipt footer / totals
        , BrandTelephone = br.Telephone
        , BrandContact   = br.ContactDetails
        , Currency       = ISNULL(NULLIF(br.Currency, N''), N'KD')
        , CurrencyAra    = ISNULL(NULLIF(br.CurrencyArabic, N''), N'د.ك')
        , DecimalPlaces  = ISNULL(br.DecimalPlaces, 3)
        , InvoiceTypeID   = i.InvoiceType
        , InvoiceTypeName = it.Name
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.OrderStatusID, OrderStatusName = st.OrderStatusName, StatusColor = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.BillAmount, i.Discount, i.DiscountCode
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , i.FinalAmount
        -- FinalAmount is a computed column that EXCLUDES DeliveryCharges.
        -- NetPayable is what the customer actually pays.
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PaymentType, PaymentTypeName = pt.PaymentTypeName
        , PaymentTypeNameArb = pt.PaymentTypeNameArb
        , IsCOD = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                                    FROM dbo.tblInvoicePayment p
                                    WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0), 0)
        , i.Comments, i.Complaints
        , i.CancelReasonID, i.CancelComments, i.CancelDisposition
        , i.Driver, i.DriverName, i.DriverAssignDate
        , i.PrintCount, i.LastPrintedOn, i.SourceID, i.Deleted
        , AddressID = ca.AddressID, ca.Block, ca.Street, ca.Lane, ca.Building
        , ca.Floor, ca.Flat, ca.HouseNo, ca.PACI, ca.AddressRemark, ca.Lat, ca.Lng
        , AreaID = ca.AreaID, AreaName = ar.AreaName, AreaNameAra = ar.AreaNameAra
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus        st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN dbo.tblbranch             b  ON b.id             = i.BranchID
    LEFT JOIN dbo.tblBrand              br ON br.BrandID       = i.BrandID
    LEFT JOIN dbo.tblInvoiceType_Master it ON it.ID            = i.InvoiceType
    LEFT JOIN dbo.tblInvoicePaymentType pt ON pt.ID            = i.PaymentType
    LEFT JOIN dbo.tblCustomerAddress    ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea               ar ON ar.AreaID        = ca.AreaID
    WHERE     i.InvoiceNo = @InvoiceNo;

    -- 1: lines
    SELECT
          o.OrderID, o.ItemID, o.LineType, o.ParentOrderID, o.CartItemUniqID
        , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
        , ItemNameAra = it.ITEM_NAME_ARABIC
        , o.Quantity, o.Price
        , Discount    = ISNULL(o.Discount, 0)
        , o.TotalAmount
        , OrderTime   = o.OrderDate
        , o.Comments, o.Extra, o.Prepared, o.Delivered, o.Deleted, o.Waste
    FROM      dbo.tblOrder o
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE     o.InvoiceNo = @InvoiceNo
    ORDER BY  o.OrderID;

    -- 2: status timeline
    SELECT    h.HistoryID, h.FromStatusID, h.ToStatusID
            , FromStatusName = sf.OrderStatusName
            , ToStatusName   = stt.OrderStatusName
            , StatusColor    = stt.ColorHex
            , h.ChangedBy, h.ChangedByName, h.ChangedOn, h.Comments, h.DriverID
    FROM      dbo.tblPOS_OrderStatusHistory h
    LEFT JOIN dbo.tblOrderStatus sf  ON sf.OrderStatusID  = h.FromStatusID
    LEFT JOIN dbo.tblOrderStatus stt ON stt.OrderStatusID = h.ToStatusID
    WHERE     h.InvoiceNo = @InvoiceNo
    ORDER BY  h.HistoryID;

    -- 3: payments
    SELECT    p.id AS PaymentID, p.PaymentTypeID, p.PaymentType, p.Amount
            , p.AmountTendered, p.ChangeGiven, p.ReferenceNo, p.IsRefund
            , p.ReceivedBy, p.ReceivedOn, p.Comments
    FROM      dbo.tblInvoicePayment p
    WHERE     p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0
    ORDER BY  p.id;

    -- 4: transfers
    SELECT    t.TransferID, t.FromBranchID, FromBranch = bf.branchName
            , t.ToBranchID, ToBranch = bt.branchName
            , t.Reason, t.TransferredBy, t.TransferredOn
    FROM      dbo.tblPOS_OrderTransfer t
    LEFT JOIN dbo.tblbranch bf ON bf.id = t.FromBranchID
    LEFT JOIN dbo.tblbranch bt ON bt.id = t.ToBranchID
    WHERE     t.InvoiceNo = @InvoiceNo
    ORDER BY  t.TransferID;

    -- 5: allowed next statuses
    SELECT    tr.ToStatusID, s.OrderStatusName, s.ColorHex, tr.RequiresRole
    FROM      dbo.tblPOS_OrderStatusTransition tr
    JOIN      dbo.tblOrderStatus s ON s.OrderStatusID = tr.ToStatusID
    JOIN      dbo.tblInvoice     i ON i.InvoiceNo     = @InvoiceNo
    WHERE     tr.FromStatusID = i.OrderStatusID
      AND     ((i.OrderType = 1 AND s.AppliesToPickup = 1) OR (i.OrderType <> 1 AND s.AppliesToDelivery = 1))
    ORDER BY  s.SortOrder;
END
GO

PRINT 'sp_POS_GetOrderDetails updated (brand phone, currency, branch Arabic name).';
GO

/* The receipt footer prints tblBrand.Telephone. If it is blank the line is
   omitted, so set it:
     UPDATE dbo.tblBrand SET Telephone = N'243 177 17 - 555 050 21' WHERE BrandID = 1;
*/
