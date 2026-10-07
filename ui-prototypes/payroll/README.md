# Payroll module - UI prototypes

Static HTML mock-ups of every Payroll screen, for review before they are built
into the app. Open **index.html** in a browser (double-click is fine; Google
Fonts needs internet, everything else is local).

- Built on the app's own `hrms.css`, Bootstrap 5.3, `site.js` and the
  `_Layout.cshtml` sidebar / top bar, copied into `assets/` - so the look is
  exactly the live theme.
- The sidebar's **Payroll** group replaces today's four "Soon" items with one
  link per section; each section page uses the same tab rail as Organization
  Setup for its sub-screens.
- Add/edit forms open in a Bootstrap modal, like the Organization Setup forms.
- Data is invented sample data; nothing is saved. Buttons open the real modals,
  drawers, tabs and wizard steps so each flow can be clicked through.

## When these become real views

- `assets/payroll.css` = the Employee Profile's inline styles (moved to a shared
  partial) + the new payroll components (`pr-*` classes). Move it to
  `wwwroot/scss/_payroll.scss` and swap the hex values for the tokens named in
  its comments.
- New icons used (add to `Helpers/IconHelper.cs`): refresh, send, percent,
  receipt, bank, book, calculator, history, file, printer, x-circle, undo, upload.
- These files are reference only - they are not served by the application.

## Arabic and desktop zoom (update)

- **العربية / English** toggle in the top bar of every screen. Like the app,
  it stores the choice and reloads the page; Arabic pages are right-to-left
  with Bootstrap's RTL stylesheet and Arabic fonts. The Arabic wording is in
  `assets/i18n-ar.js` (English → Arabic); when each payroll screen is built,
  its labels go into `Core.UiLabels` (see the main README, "Bilingual UI").
  Person names, codes, IBANs and e-mail addresses are data and stay as typed.
- Layout follows the room each component really has (CSS container queries),
  so the screens hold up at 125-200 % browser zoom: KPI strips re-flow
  without orphan tiles, optional table columns (`col-p2` / `col-p3`) step
  aside as a table narrows, and the bottom action bar stops being sticky on
  short windows. Checked at 1920 / 1536 / 1366 / 1280 / 1097 / 960 / 390 px
  in both languages: no page or table scrolls sideways.

## Payroll runs: naming, description and stages (update 2)

- **Run name is generated**: `DTC-2026-10-05` = company code - year - month -
  number of the payroll for that company and month (from 01; every calendar
  shares the counter; cancelled runs keep their number). Create Payroll shows
  it read-only together with how many payrolls the month already has.
- **Description** (reason for the payroll): optional only for the first regular
  payroll of the month, required otherwise. A second *Regular* payroll for the
  same calendar and period is blocked - use *Off-cycle*.
- **Stages**: Registered → Validation → Awaiting Approval (HR, then Finance)
  → Closed, or Cancelled. Payroll Register / Validation / Approval work on the
  payroll selected at the top and their tabs appear only when the payroll has
  reached that stage. Opening a later stage directly redirects to the current one.
- **Payroll Calendar** lists every payroll with its stage; open one to continue.
- The flow is clickable: Complete registration → (mark errors fixed) Submit →
  Approve twice → Closed; Cancel payroll at any stage before approval; Create
  Payroll adds a new one. Stage changes are kept in the browser - use
  "Reset prototype" on the Payroll Calendar to start over.

## Pay items as line items (update 3)

- **One Pay Items screen** replaces Salary Management, Earnings & Deductions
  and Loans & Advances (13 tabs). Every amount an employee is paid or has
  deducted is one line: **Class** (Salary, Earning, Deduction, Loan / advance),
  **Item type**, amount, when it applies (every month / one time / in
  instalments) and a **Comment**. Filter by employee and class; picking an
  employee shows their monthly salary and loan balance.
- The item types are kept in Payroll Settings → **Pay Item Types** (add,
  rename, Arabic name, PIFSS / EOS flags, GL account).
- **Create Payroll, step 2 (Employees)** now lists every employee with
  salary, earnings, deductions and estimated net. Open an employee to see
  each line with its class, type, comment and source, and add an Earning or
  Deduction line (type + amount + comment) for this payroll only. Tick several
  employees to add the same line to all of them. Employees without salary
  items are flagged.
- The old `sm-*`, `ed-*` and `la-*` pages now just forward to Pay Items.
