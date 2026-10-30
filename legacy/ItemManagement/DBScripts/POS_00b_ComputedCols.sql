/**********************************************************************************
  POS_00b_ComputedCols.sql   -- 5 second query, needed before POS_02 is finalised

  The dump showed three COMPUTED columns but not their formulas:
      tblInvoice.FinalAmount   decimal(19,3)
      tblInvoice.Change        decimal(21,3)
      tblOrder.TotalAmount     decimal(30,3)

  Their definitions decide whether sp_POS_ProcessOrder must add DeliveryCharges
  into BillAmount or leave it separate, and whether line Discount is already
  subtracted in TotalAmount. Run this and save the output to
  DBScripts\ComputedCols.txt
**********************************************************************************/
SET NOCOUNT ON;

SELECT  t.name AS TableName,
        c.name AS ColumnName,
        cc.definition,
        cc.is_persisted
FROM    sys.computed_columns cc
JOIN    sys.columns c ON c.object_id = cc.object_id AND c.column_id = cc.column_id
JOIN    sys.tables  t ON t.object_id = cc.object_id
ORDER BY t.name, c.column_id;

-- Also: confirm how tblItems.ID vs tblItems.HID relate, since the current
-- SubmitOrder sends HID as the item identifier (see notes in the handover).
SELECT TOP 20 ID, HID, ITEM_NAME, PRICE, isExtra, Ischoice, IsActive
FROM   dbo.tblItems
ORDER BY ID;
