# Dashboard port — what does not match, and what I did about it

The dashboard you sent comes from the Call Centre project. Its stored procedures
cannot run against this database: they reference tables that do not exist here,
columns that are named differently, and an architecture (one database per branch)
that this project does not have.

This is the table-by-table comparison, the decisions taken, and the two things
that still need a decision from you.

---

## 1. The blocker: the procedures the page actually calls were not in the file

`DashboardController.cs` calls **nine** procedures. The SQL file you sent contains
**six**, and only three of them overlap:

| Called by the controller | In the file you sent |
|---|---|
| `sp_DashbordSalesData` — the whole Sales tab | **missing** |
| `sp_DashbordPaymentTypesData` | **missing** |
| `sp_DashbordDiscountWiseItemsData` | **missing** |
| `sp_DashbordDeletedReUseWiseItemsData` | **missing** |
| `sp_DashbordDeletedWasteWiseItemsData` | **missing** |
| `sp_GetDashboardLateOrdersData` | yes |
| `sp_GetDashboardTopItemsSummaryData` | yes |
| `sp_DashboardFilter` | yes |
| `sp_GetEndDatesForRptDashboard` | yes |

The file also contains `sp_GetDashboardData` and `sp_GetStoreManagerDashboardData`,
which nothing in the controller or the JS calls — they look like an earlier
version of the same page.

`sp_DashbordSalesData` is the important one: it fills every panel on the landing
tab. I rebuilt it from how `DashboardController.cs` and `Dashboard.js` consume it
— the controller reads result sets **by index**, and the JS reads columns by name,
so between them they specify it exactly:

| Index | Used for | Columns the JS reads |
|---|---|---|
| 0 | Total Sales tile | `TotalSales`, `OrderCount` |
| 1 | Total Discount tile | `TotalDiscount`, `OrderCount` |
| 2 | Payment types table | `Name`, `orders`, `Total` |
| 3 | Sales line chart | `BranchName`, `InvoiceDate`, `NetTotal`, `TotalCount` |
| 4 | Sales pivot | `BranchName`, `keyName`, `KeyValue`, `InvoiceDate` |
| 5 | Order types table | `Name`, `TotalOrders`, `TotalSales` |
| 6 | Cancellation (reuse) tile | `TotalDelItems`, `CountDelItems` |
| 7 | Cancellation (waste) tile | `TotalWasteItems`, `CountWasteItems` |
| 9 | Hourly chart | `Name`, `HoursBreak`, `TotalSales`, `TotalCount` |
| 10 | Top items table | `itemName`, `SoldItems`, `Total` |
| 12 | Branch sales chart | `BranchName`, `OrderTotalAmt`, `OrderCount` |
| 14 | Late orders table | `BranchName`, `LateOrderCount`, `TotalOrders` |
| 15 | Currency | `Currency` |

Indexes 8, 11 and 13 are returned empty. They have to exist: the controller reads
by position, so removing one shifts every table after it and the page fills with
the wrong numbers under the right headings — which is worse than an error.

**Types are load-bearing.** The controller does `x.Field<int>("TotalCount")` and
`x.Field<Decimal>("TotalSales")`. A `BIGINT` count or a `MONEY` total throws
`InvalidCastException` instead of showing a wrong number, so every count is cast
to `INT` and every amount to `DECIMAL(18,3)`.

---

## 2. Architecture: one database, not many

The Call Centre keeps **a database per branch** (`tblBranch.BranchDBName`). Every
heavy procedure opens a cursor over the branch list and builds dynamic SQL against
`[BranchDB].dbo.tblInvoice`.

This project has **one** database with a `BranchID` column. So the cursors, the
dynamic SQL, `@BranchDBName` and `dbo.split_stringWithDelim` (which does not exist
here) are all gone. `STRING_SPLIT` does the CSV work; it is already used elsewhere
in this project's procedures.

---

## 3. Table and column differences

| Call Centre | Here | Consequence if left alone |
|---|---|---|
| `tblInvoice.id` | `tblInvoice.InvoiceNo` | every join fails |
| `tblOrder.InvoiceId` | `tblOrder.InvoiceNo` | `Invalid column name 'InvoiceId'` |
| `tblBranch.BranchID` | `tblbranch.id` | filter and every chart fail |
| `tblBranch.BranchName` | `tblbranch.branchName` | (case-insensitive, but the column name differs) |
| `tblBranch.StoreID` | *(none)* | dropped from the branch charts |
| `tblBranch.BranchDBName` | *(none)* | cursors removed entirely |
| `tblWaste` / `tblWasteDetails` | *(none)* | waste figures come from `tblOrder.Waste` only — see §5 |
| `tblFranchise_GroupMaster` | `tblBrand` | "Franchise Sales" chart is brand sales |
| `tbl_StatusDetails` | `tblPOS_OrderStatusHistory` | late-order timings rebuilt — see §6 |
| `dbo.split_stringWithDelim` | `STRING_SPLIT` | rewritten |
| `tblInvoice.InvoiceTypeID` | `tblInvoice.InvoiceType` | filter silently matched nothing |
| `tblDiscount_Type` | same | works as-is |
| `tblItems`, `tblCategory` | same | works as-is |

`tblEndDay` exists here, so nothing breaks on it — but see the next point, which
is the one that decides whether the page shows anything at all.

---

## 4. The one that matters: date scoping

Every original query scopes by **end-of-day session**, not by date:

```sql
where inv.EndDayID in (select id from tblEndDay where cast(StartDate as date) between @FromDate and @ToDate)
```

That is correct for a till that gets cashed up nightly. But orders taken through
this QR menu are written with `EndDayID` **NULL**, and nothing in this project ever
sets it. Ported literally, every panel would read **zero, on every date**, and the
page would look broken rather than empty.

So the scope here is `i.InvoiceDate` between the two dates. When the user picks
specific operating days from the dropdown, those dates are matched against
`CAST(i.InvoiceDate AS DATE)`.

Consequence: `sp_GetEndDatesForRptDashboard` now lists **days on which orders
exist**, not end-day sessions. Same two column names (`StartDate`,
`StartDateName`), so the controller and the JS are unchanged.

If you later start running end-of-day here, this is the one place to revisit.

---

## 5. Waste is now order-line waste only

The original adds two figures together: deleted order lines flagged `Waste = 1`,
**plus** standalone waste from `tblWaste` / `tblWasteDetails` — stock thrown away
that was never on an order.

Neither table exists here, and there is no screen that would populate them. The
waste tile therefore counts order-line waste only. It is not wrong, it is
narrower, and the number will be lower than the same tile in the Call Centre.

---

## 6. Late orders

The original reads per-branch `tbl_StatusDetails` with hard-coded status IDs
2–6 for Kitchen / Ready / Dispatched / Collected / Delivered.

Two problems here: that table does not exist, and status IDs in this database are
per-installation and have been renamed. So the timings come from
`tblPOS_OrderStatusHistory`, and each step is found by its **position in
`tblOrderStatus.SortOrder`** — the workflow order, which is what those columns
actually mean — rather than by a literal ID. An order counts as late when the gap
between the invoice and the row that closed it exceeds the minutes on screen.
Orders still open are not late; they are not finished.

---

## 7. What still needs you

**Currency.** Result set 15 is hard-coded to `'KD'`. The Call Centre read it from
a country table because it served Kuwait and KSA. One literal to change in
`sp_DashbordSalesData` if this brand trades in something else.

**The Country dropdown.** `Dashboard.js` hard-codes Kuwait and KSA and posts
`@CountryId` everywhere. Every procedure accepts it and ignores it, so nothing
breaks — but the dropdown is now decorative. Removing it is a JS change
(`bindCountryDropdown`, and the `CountryId` line in each AJAX payload); leaving it
costs nothing.

**Cancelled status.** `sp_DashbordSalesData` counts every non-deleted invoice as
sales. If you want cancelled orders excluded from the sales figures, tell me which
status ID means cancelled in your data — you moved cancellation to **6** in
POS_27, but the seed in POS_03 has 6 = Delivered and 7 = Cancelled, and I would
rather not guess at money.

---

## 8. To run it

1. Run `DBScripts/POS_31_Dashboard.sql`. Section 0 prints a preflight — read it
   first; a `MISSING` there is a panel that will read zero rather than error.
2. Copy the five `.cshtml` files into `Views/Dashboard/`, and `Dashboard.js` into
   your scripts folder.
3. `DashboardController.cs` needs its namespace changed from `CoffeeShop` to this
   project's, and `[SessionExpire]` swapped for this project's auth attribute.
   Nothing else in it has to change — that is what the ignored `@CountryId` and
   the preserved result-set order are for.
