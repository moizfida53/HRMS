# QR Menu → Direct DB Order Insert + POS Admin Panel
## Architecture & Implementation Plan

**Project:** `ItemManagment` (ASP.NET MVC 4, .NET Framework 4.8, ADO.NET + stored procs)
**Database:** `Pistachio_v4` on `.\TMM`
**Date:** 12 Aug 2026

---

## 1. What exists today

The order submission path has exactly one choke point, which makes this change small and safe:

| Layer | File | Detail |
|---|---|---|
| UI (new) | `Views/ItemsViewNew/CheckoutViews/Payment.cshtml` :580 | `SubmitOrderAjaxcall()` → POST `/ItemsView/SubmitOrder` |
| UI (new) | `MainJs/ItemsViewNew/BindCartDetails.js` :3911 | `SubmitOrder()` → POST `/ItemsView/SubmitOrder` |
| UI (old) | `MainJs/ItemsView/BindCartDetails.js` :1106 | POST `/ItemsView/SubmitOrder` |
| Server | `Controllers/ItemsViewController.cs` :548 | `SubmitOrder(...)` |
| Server | same, :603–631 | Builds payload → `WebClient.UploadString(CallCenterUrl + "/DmToCallCenterServices/ProcessOrderHD")` |

Everything funnels into **one action method**. Replacing the HTTP call with a stored-proc call changes ~40 lines and no front-end code.

Other call-centre dependencies that will also need a local equivalent eventually (out of scope for phase 1, listed so they aren't forgotten):

- `AddressConfirmController` → `GetInvoiceAddress`, `UpdateInvoiceAddress`
- `ItemsViewNewController` :727 → `GetInvoiceDriverStatus`
- `ItemsViewNewController` :761 → `GetDeliveryServiceData`

Data access convention already in the codebase: `Jar.Helper.DB.ExecuteStoredProcDataSet("sp_Name", SqlParameter[])`, with `DB.ToDataTable(list)` for table-valued parameters (see `sp_GetCartItemList` usage). The new work follows this exactly — no ORM, no new dependency.

---

## 2. BLOCKER — schema needed first

`tblInvoice` / `tblOrder` are not scripted anywhere in the source tree, and this session cannot reach `.\TMM` over the network (the file bridge shares folders, not TCP; port 1433 is unreachable from here). So the insert proc cannot be written against real columns yet.

**Unblock in ~2 minutes:** `DBScripts\POS_00_DumpSchema.sql` has been written into the project folder. Run it and save the output as `DBScripts\SchemaDump.txt` — that folder is already shared with this session, so nothing needs pasting into chat.

```
sqlcmd -S .\TMM -d Pistachio_v4 -U sa -P "f$97227330" ^
  -i "D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project\DBScripts\POS_00_DumpSchema.sql" ^
  -o "D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project\DBScripts\SchemaDump.txt" -W -s"|" -y0 -Y0
```

(Or open it in SSMS, `Ctrl+T`, `F5`, copy results, save to that path.)

The script reports columns, keys, foreign keys, row counts, lookup-table **contents** (real status / payment-type IDs — these drive the POS buttons), and **any existing procs that already touch `tblInvoice`/`tblOrder`**. That last section matters: if the call-centre app shares this database, `ProcessOrderHD` may already be backed by a proc worth reusing rather than reinventing.

> Section 7 dumps sample rows including customer names and phone numbers. Review before sharing more widely.

---

## 3. Phase 1 — Replace the API call with a direct insert

### 3.1 Stored procedure `sp_POS_ProcessOrder`

One proc, one transaction, one round trip. Signature (column names to be finalised from the schema dump):

```
sp_POS_ProcessOrder
    @BranchID          INT,
    @BrandID           INT,
    @InvoiceTypeID     INT,          -- 10 = Call Centre, per Web.config
    @OrderTypeID       INT,          -- 1 = Pickup, 2 = Delivery
    @CustomerID        INT     = NULL,
    @CustomerName      NVARCHAR(200),
    @Mobile            NVARCHAR(30),
    @AddressID         INT     = NULL,
    @AddressText       NVARCHAR(MAX) = NULL,
    @AreaID            INT     = NULL,
    @DeliveryDate      DATETIME = NULL,
    @PaymentTypeID     INT,
    @DiscountTypeID    INT     = 0,
    @InvoiceDiscount   DECIMAL(18,3) = 0,
    @DiscountCode      NVARCHAR(50)  = NULL,
    @DeliveryCharges   DECIMAL(18,3) = 0,
    @WaiterID          INT     = 0,
    @IsOnlineOrder     BIT     = 1,
    @Comments          NVARCHAR(MAX) = NULL,
    @dtOrderItems      TVP_POS_OrderItem READONLY,
    @InvoiceNo         NVARCHAR(50) OUTPUT,
    @InvoiceID         INT          OUTPUT
```

Table type `TVP_POS_OrderItem` mirrors the existing `ItemViewOrder` model so `DB.ToDataTable()` works unchanged:
`ItemID, ParentItemID, CartItemUniqID, Quantity, Price, Comments, HID, BID, WaiterID`

Body outline:

1. `SET XACT_ABORT ON; BEGIN TRAN`
2. Resolve / upsert customer and address (only if the schema requires FK rows).
3. **Generate `InvoiceNo` safely.** This is the single biggest correctness risk under concurrent orders. Use a dedicated sequence/counter table with `UPDATE ... WITH (UPDLOCK, HOLDLOCK)` and `OUTPUT`, or a `SEQUENCE` object — never `MAX(InvoiceNo)+1`. Must match the numbering format the call centre already produced (visible in the sample rows).
4. **Re-price server-side.** Never trust prices posted from the browser: join `@dtOrderItems` to the item master and compute line totals, tax and discount in SQL. The current API-based flow has the same weakness; fixing it here closes a real order-tampering hole.
5. Insert header into `tblInvoice`, capture identity.
6. Insert lines into `tblOrder` (single set-based `INSERT ... SELECT`, no cursor).
7. Insert initial status row = `Received` (see §4.1).
8. `COMMIT`, return `@InvoiceNo` / `@InvoiceID`.
9. `TRY/CATCH` → `ROLLBACK` + `THROW`.

Idempotency: accept an optional `@ClientOrderGuid` and a unique index on it, so a double-tap on *Process Order* or a retried request returns the original invoice instead of creating a duplicate. Cheap now, painful to retrofit.

### 3.2 Controller change

In `ItemsViewController.SubmitOrder`, replace the `WebClient` block (lines ~603–631) with a `DB.ExecuteStoredProc` call using output parameters. Keep the **response shape identical** (`result` object with `Message` / invoice number) so the three existing JS callers need zero changes.

Keep the old code path behind a config switch during rollout:

```xml
<add key="OrderMode" value="LocalDB" />   <!-- LocalDB | CallCenter -->
```

so a bad night can be reverted by an appSetting edit rather than a redeploy.

### 3.3 Phase 1 acceptance

- Pickup order → correct `tblInvoice` + `tblOrder` rows, invoice number matches existing format
- Delivery order with address → address and delivery charge persisted
- COD vs online payment → correct `PaymentTypeID`
- Discount code applied → discount recorded, totals reconcile
- 20 concurrent submissions → 20 distinct invoice numbers, zero duplicates
- Forced failure mid-proc → no orphan header row

---

## 4. Phase 2 — POS Admin Panel

New MVC **Area**: `Areas/POS/`. Own `_LayoutPOS.cshtml`, own routes (`/POS/...`), shares `Helper/DB.cs`, `Web.config` and session with the menu app. Nothing in the existing app changes.

```
Areas/POS/
  POSAreaRegistration.cs
  Controllers/    OrdersController.cs, CustomersController.cs,
                  PrintController.cs, ReportsController.cs, AuthController.cs
  Views/          Orders/Index.cshtml, Orders/_Details.cshtml,
                  Orders/_Print_A4.cshtml, Orders/_Print_Thermal.cshtml,
                  Shared/_LayoutPOS.cshtml
  Models/         OrderListRequest.cs, OrderListRow.cs, ...
Areas/POS/Scripts/  pos.orders.js, pos.print.js, pos.filters.js
DBScripts/          POS_01_Tables.sql, POS_02_Types.sql, POS_03_Procs.sql
```

### 4.1 Order status model

Requested statuses: `Received`, `Preparing`, `Delivering/Ready`, `With Driver`, `On the Way`, `Delivered`, `Cancelled`, `Refunded`.

Rather than overwrite a single column, add an append-only history table — this is what makes SLA reporting, driver performance and dispute resolution possible later, and it costs nothing now:

```sql
tblPOS_OrderStatus_Master (StatusID, StatusName, StatusName_AR, SortOrder,
                           ColorHex, IsTerminal, AppliesToDelivery, AppliesToPickup)

tblPOS_OrderStatusHistory (HistoryID, InvoiceID, StatusID, ChangedBy,
                           ChangedOn, Comments, DriverID NULL)
```

`tblInvoice` keeps a denormalised `CurrentStatusID` (updated in the same transaction) so the grid never has to aggregate history — that is the difference between a 20 ms and a 900 ms list query.

Allowed transitions enforced **in the proc**, not just the UI, so a stale browser tab can't move a delivered order back to Preparing. Pickup orders skip driver states.

### 4.2 Orders grid — built for speed

This is where "fast transaction" is won or lost. Design rules:

- **Server-side paging, sorting and filtering.** DataTables in `serverSide: true` mode → one proc `sp_POS_GetOrders` taking `@Skip, @Take, @SortCol, @SortDir` plus all filters, returning page rows + total count. Never `SELECT *` then filter in C#.
- **Covering index** on `tblInvoice (BranchID, InvoiceDate, CurrentStatusID) INCLUDE (InvoiceNo, CustomerName, Mobile, NetTotal, PaymentTypeID)`. Without this the grid degrades the moment the table passes a few hundred thousand rows.
- **Default filter is narrow**: today + this branch + non-terminal statuses. Past/Future are explicit tabs (matching the reference POS screenshot). Never open on "all orders, all time".
- **Delta polling, not full reload.** Poll `sp_POS_GetOrderChanges @SinceRowVersion` every 5–10 s and patch only changed rows in the DOM. Add a `rowversion` column to `tblInvoice` for this. Optional upgrade: SignalR push, which removes polling entirely.
- **Bulk actions** on checkbox selection — status change, print, transfer — in a single proc call with a TVP of invoice IDs, not N round trips.
- **Keyboard first**: `/` focus search, `↑↓` row nav, `Enter` details, `P` print, `1–8` set status. Counter staff work faster on keys than on a mouse; this is the single highest-impact speed feature.
- Optimistic UI with rollback on error, and a debounced search box (300 ms).

### 4.3 Common search filter

One filter bar, all server-side: free text (invoice no / tracking code / customer name / mobile), date range, branch (multi), status (multi), order type, payment type, payment status, source, driver, amount range. Saved filter presets per user, and the active filter encoded in the URL query string so a supervisor can send a colleague a link to exactly what they're looking at.

### 4.4 Order details

Slide-over panel, not a page navigation — keeps the grid state and is noticeably faster. Shows header, customer with click-to-call and WhatsApp link (the reference POS has this), full line items with choices/extras/comments, totals breakdown, payment state, status timeline from history, and an audit trail of who did what.

### 4.5 Printing — A4 and thermal

Two Razor partials rendered to a print-only page:

- **A4** — full invoice, branded header, logo, itemised table, tax breakdown, footer, QR code linking to order tracking.
- **Thermal 80 mm** — `@media print { @page { size: 80mm auto; margin: 0 } }`, monospace, condensed. Also produce a **58 mm** variant; the width should be a branch setting, not hard-coded.
- **Kitchen ticket** — a third, separate template: items and modifiers only, no prices, large type. Kitchens do not need customer addresses.

Delivery mechanism, in order of preference:
1. Browser print with a hidden iframe and `window.print()` — zero install, works everywhere, needs one "Destination" selection per session.
2. **Auto-print agent** (recommended for real counter use) — a small local Windows service polling a print queue table and pushing ESC/POS bytes straight to the printer. Eliminates the print dialog entirely. This is the difference between 1 click and 4 clicks per order, ~200 times a day.
3. PDF generation server-side for re-print and email/WhatsApp receipts.

Track `PrintCount` and `LastPrintedOn` per invoice and mark re-prints as **REPRINT** on the ticket — a standard control against duplicate-order fraud in kitchens.

### 4.6 Transfer order to another branch

Popup: target branch, reason, comments. Proc `sp_POS_TransferOrder` re-validates that the target branch actually serves the delivery area and stocks every item on the order, writes a `tblPOS_OrderTransfer` audit row, moves the invoice, and appends a status-history entry. Blocked once the order is with a driver.

### 4.7 Payment (COD → Pay icon)

Pay icon shows only when `PaymentTypeID = COD` and the order is unpaid. Popup offers Cash, KNET, Credit Card, Link (payment link sent by SMS/WhatsApp), Wallet, Split. Supports **partial and split payments**, so the schema is a child table, not a column:

```sql
tblPOS_InvoicePayment (PaymentID, InvoiceID, PaymentTypeID, Amount,
                       ReferenceNo, ReceivedBy, ReceivedOn, IsRefund)
```

Cash entry gets an amount-tendered field with automatic change calculation and quick-denomination buttons (KD 1 / 5 / 10 / 20). Invoice payment status derives from `SUM(Amount)` vs `NetTotal`. Hesabe integration already exists in the repo (`Hesabe/`) and can back the payment-link option.

### 4.8 Cancellation

Popup requires a comment and a **Waste / Reuse** selection, as specified. Waste vs Reuse drives an inventory adjustment row, which is what makes the waste report in §5 meaningful. Cancellation after preparation starts should require a supervisor PIN — otherwise cancellation becomes the standard way to hide mistakes. Refund is a separate action on an already-paid order and writes a negative row into `tblPOS_InvoicePayment`.

### 4.9 Customers tab

Server-side grid: name, mobile, orders count, total spend, average order value, last order date, addresses, flags. Row click → order history, saved addresses, notes. Actions: edit, merge duplicates (very common with phone-number-keyed customers), block, add note. Same paging/index discipline as the orders grid.

---

## 5. Suggested additions

Ordered by value-per-effort, based on what the reference POS lacks.

### High value, low effort
| Feature | Why |
|---|---|
| **Live ops dashboard** | Open orders by status, orders breaching prep SLA, average prep time, today's revenue vs yesterday. One screen on a wall monitor. |
| **SLA timers on every row** | Colour-coded age since Received. Turns a passive list into an active queue. Highest single impact on kitchen speed. |
| **Audit trail on everything** | Who changed status, who cancelled, who reprinted. Already needed for the cancellation control above; near-free once status history exists. |
| **Order tracking page for customers** | Public page keyed by tracking code. Directly cuts "where is my order" calls. |
| **Auto-print on new order** | Removes a human step from every single order. |
| **New-order sound + browser notification** | The reference POS has a bell icon; make it reliable and per-branch. |
| **Role-based permissions** | Cashier / Supervisor / Manager / Driver. Cancellation, refund and transfer are supervisor-only. |

### Reports (Phase 3)
- Sales summary — by day / branch / hour / order type / payment type
- Item performance — best and worst sellers, with modifier attach rate
- Peak-hour heatmap → staffing and prep-capacity decisions
- Cancellation & waste report — split by Waste / Reuse, by reason, by user
- Driver performance — deliveries, average delivery time, on-time %
- Customer cohorts — new vs returning, RFM segments, churn candidates
- Discount & coupon effectiveness — revenue lift vs margin given away
- Delivery-area heatmap — where orders come from, informs the next branch
- End-of-day Z-report — cash declared vs system, per cashier
- Scheduled email/WhatsApp of the daily summary to owners

### Operational depth (Phase 4)
- **Driver dispatch board** — assign orders to drivers, batch nearby deliveries, live map. Biggest lever on delivery cost.
- **Kitchen Display System** — replaces paper tickets, bump-bar workflow, per-station routing.
- **Item 86 / stock-out** — one tap makes an item unavailable across the QR menu instantly.
- **Branch capacity throttling** — auto-extend promised times or pause ordering when the queue exceeds N orders. Prevents the failure mode where a busy branch accepts orders it cannot cook.
- **Prep-time engine** — promised time from live queue depth instead of a fixed number.
- **Offline-tolerant POS** — queue actions in IndexedDB, sync on reconnect. Counter keeps working through a network blip.
- **WhatsApp order lifecycle notifications** — confirmed / preparing / out for delivery / delivered.
- **Loyalty and store credit**, **scheduled/pre-orders**, **table-side QR ordering tie-in** (the `Waiter` and `BranchReservation` controllers already exist and can feed the same grid).

---

## 6. Performance budget

Targets to design against, not aspirations to check afterwards:

| Action | Target |
|---|---|
| Order list, page of 50 | < 150 ms server, < 400 ms to painted |
| Status change (single) | < 100 ms, optimistic UI so it feels instant |
| Order details open | < 200 ms |
| Print render | < 300 ms |
| Process Order (customer side) | < 500 ms end to end |
| New-order visibility in POS | < 10 s polling, < 1 s with SignalR |

Supporting decisions: every grid query server-side and covering-indexed; delta polling rather than full refresh; connection pooling verified in `DB.cs`; `SET NOCOUNT ON` in every proc; output caching on lookup lists (branches, statuses, payment types) since they change perhaps monthly; gzip and bundling on the POS Area's static assets; archive invoices older than N months into a `tblInvoice_Archive` so the hot table stays small.

---

## 7. Sequencing

| Phase | Scope | Depends on |
|---|---|---|
| **0** | Run `POS_00_DumpSchema.sql`, review output | — |
| **1** | `sp_POS_ProcessOrder` + TVP + controller swap + `OrderMode` switch | Phase 0 |
| **2a** | POS Area skeleton, auth, layout, orders grid with server-side paging + filters | Phase 1 |
| **2b** | Details panel, status changes with history, cancel, transfer, payment popup | 2a |
| **2c** | Printing — A4, thermal 80/58 mm, kitchen ticket, reprint tracking | 2a |
| **2d** | Customers tab | 2a |
| **3** | Reports + live dashboard | 2b |
| **4** | Auto-print agent, SignalR, dispatch board, KDS | 3 |

Phases 2a–2d are independent once 2a lands and can be worked in parallel.

---

## 8. Open questions

1. **Does the call centre still need these orders?** If the call-centre system reads the same `Pistachio_v4` database, switching to a direct insert is transparent to it. If it has its own database, cutting the API means call-centre staff stop seeing QR orders — confirm before Phase 1 goes live.
2. **Multi-tenant?** Several brands appear in `Web.config` history (Pistachio, Exotic, Wazzan). Should the POS filter by `BrandID` for a logged-in user, and is there one database per brand or one shared?
3. **POS authentication** — reuse `LoginController` / `tblWaiter`, or a separate POS user table with roles? Recommendation: separate, with roles, since POS permissions differ from menu-admin permissions.
4. **Printer reality** — which thermal printers are in the branches, and is installing a small Windows print agent on counter PCs acceptable?
5. **Tax** — is VAT/service charge computed in the invoice today, and at header or line level?
6. **Arabic** — the reference POS shows Arabic customer names. Confirm the POS UI needs full RTL, and that thermal templates render Arabic correctly on the target printers.
