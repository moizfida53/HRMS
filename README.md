# HRMS Kuwait — HR & Payroll

ASP.NET Core 9 MVC application for HR and payroll operations under Kuwait
labour law. This drop contains the full solution skeleton, a working
**sign-in system** (real authentication, not a placeholder), **Module 3,
Organizational Architecture** (a single *Organization Setup* page with eight
tabs), and **Module 4, Workforce** — an Employees list and a tabbed Employee
Profile page covering Personal Info, Employment and Kuwait Compliance.

---

## What is in this drop

| Area | Status |
|---|---|
| Solution structure (Domain / Data / Web) | Complete |
| Corporate Blue & White theme (SCSS → CSS) | Complete |
| App shell — sidebar, topbar, responsive drawer | Complete |
| Professional login page + real authentication | Complete |
| Organization Setup — 8 tabs, full CRUD | Complete |
| Stored procedures — 8 masters + 2 shared + auth | Complete |
| Database security policy (least privilege) | Complete |
| Module 1 Authentication (login/logout/lockout) | Complete — password reset, 2FA and self-service change-password screens are not built yet |
| Module 4 Workforce — Employees list + tabbed Profile | Complete — see *Module 4* below for known gaps (document upload, cascading dropdowns) |
| Module 4 Kuwait Compliance — Civil ID/passport/residency/work permit | Complete, as a tab on the Employee Profile page |
| Payroll Phase 1 — Master Setup (database) | Database complete (scripts 29–32) — screens not built yet; see *Payroll — Phase 1* below |
| Payroll — Payslips (generate, view / print, email, My Payslips) | Complete — scripts 42–44; see *Payslips (live)* below |
| Modules 2, 5–12 | Not started |

The eight Organization Setup tabs are Companies, Branches, Departments,
Sections, Designations, Job Positions, Locations and Cost Centers. Each
supports list, search, status filter, column sort, server-side paging,
create, edit, activate / deactivate, and delete with dependency checks.

Workforce is structured differently on purpose: one Employees list (the same
search/filter/sort/paging grid pattern) and, per employee, **one Employee
Profile page with tabs** (Personal Info, Employment, Kuwait Compliance,
Documents) rather than eight separate masters — because those tabs are
mostly the *same* employee row, not different entities. See *Module 4*
below.

---

## Prerequisites

- .NET SDK 9.0
- SQL Server 2019 or later (Express is fine for development)
- Node.js 18+ — **only** if you intend to edit the SCSS. The compiled CSS is
  committed, so the app runs without Node.

---

## Database setup

Run the scripts in order against your HRMS database:

| # | Script | What it does |
|---|---|---|
| 01 | *your existing schema script* | Base tables, seed data, views |
| 02 | `db/02_Organization_Additions.sql` | Adds `Core.Designations`, `Core.Locations`, `Core.Governorates` |
| 03 | `db/03_Organization_StoredProcedures.sql` | The eight `usp_*_Manage` procedures |
| 04 | `db/04_Shared_StoredProcedures.sql` | `usp_Lookup_Get`, `usp_Master_CheckDuplicate` |
| 05 | `db/05_Security_Grants.sql` | Application login, role, GRANT EXECUTE, DENY on tables |
| 06 | `db/06_Security_Auth_Additions.sql` | Lockout/security-stamp columns on `Security.Users`, `Security.UserLoginHistory`, Organization permissions, seeds one `administrator` login |
| 07 | `db/07_Auth_StoredProcedures.sql` | `Security.usp_Auth_Manage` — login lookup, success/failure recording, lockout, permissions, password change |
| 08 | `db/08_Employee_Kuwait_Additions.sql` | Adds Personal Info + Employment columns to `Employee.Employees`, creates `Kuwait.EmployeeCompliance` |
| 09 | `db/09_Employee_StoredProcedures.sql` | `Employee.usp_Employee_Manage` — LIST/GET/INSERT/UPDATE/DELETE/TOGGLE for the Employee master |
| 10 | `db/10_Kuwait_Compliance_StoredProcedures.sql` | `Kuwait.usp_EmployeeCompliance_Manage` — GET/UPSERT for the 1:1 compliance record |
| 11 | `db/11_Lookup_Extension_Employee.sql` | Reissues `Core.usp_Lookup_Get` with one added branch, `EMPLOYEE` (the Reporting Manager dropdown) |
| 12 | `db/12_Organization_Seed_Data.sql` | Optional. Seeds one company's Branches, Cost Centers, Departments, Sections, Designations, Job Positions and Locations with realistic starting data |
| 13 | `db/13_Employee_Extended_Additions.sql` | Adds Religion, Blood Group, Extension, the Kuwait PACI address breakdown (Neighborhood/Block/Street/Building/Floor/Flat/PACI Number/Landmark) and Notice Period to `Employee.Employees`; creates `Employee.Dependents` |
| 14 | `db/14_Employee_Manage_Extended.sql` | Reissues `Employee.usp_Employee_Manage` with the new columns bound, and DELETE now also clears a departing employee's Dependents rows |
| 15 | `db/15_Employee_Dependent_StoredProcedures.sql` | `Employee.usp_EmployeeDependent_Manage` — LIST/GET/INSERT/UPDATE/DELETE for the Dependents tab, scoped by employee |
| 16 | `db/16_Employee_Manage_EmployeeNo.sql` | Adds `EmployeeNo` as its own required field on `usp_Employee_Manage` (GET/INSERT/UPDATE) - fixes the `NOT NULL` insert failure on a pre-existing base-schema column. Run after 13/14/15. |
| 17 | `db/17_Employee_Extended_Additions_2.sql` | Adds Father's Details (Name/Occupation/Mobile/Deceased/Currently Residing In) plus Passport and Civil ID columns to `Employee.Employees`. Run after 13/14/15/16. Only Father's Details is actually used by the app — its Passport/Civil ID columns were superseded by the Kuwait Compliance tab's own fields before release and are unused (see the app's own note in `Employee.cs`). |
| 18 | `db/18_Employee_Manage_FatherPassportCivilId.sql` | Reissues `Employee.usp_Employee_Manage` with script 17's new columns bound (GET/INSERT/UPDATE) — Father's Details only; Passport/Civil ID parameters are declared but never supplied by the app (same note as script 17). Run after 17. |

Script 02 is **purely additive** — it creates three tables your base schema
does not have and touches nothing you already built. Scripts 13–15 follow the
same rule as 08–11: every `ALTER TABLE ... ADD` is guarded by `IF COL_LENGTH(...)
IS NULL` and `Employee.Dependents` is guarded by `IF OBJECT_ID(...) IS NULL`.
The existing free-text `Employee.Employees.Address` column is **not** dropped
by script 13 — it is simply no longer shown on the Personal Info form once
you deploy this update, replaced there by the structured address fields; any
address text already saved stays in the database untouched. Scripts 06 and 07 are
the same: additive columns/tables plus one new procedure, nothing dropped or
altered on tables you already had. Scripts 08–11 follow the identical rule: every
`ALTER TABLE ... ADD` is guarded by `IF COL_LENGTH(...) IS NULL`, the new
`Kuwait.EmployeeCompliance` table is guarded by `IF OBJECT_ID(...) IS NULL`
(and the `Kuwait` schema itself by `IF NOT EXISTS (SELECT 1 FROM
sys.schemas ...)`), so re-running them is always safe and nothing you
already had is dropped or altered. `Employee.Employees` and its `IsDeleted`
flag already existed in your base schema (Organization Setup's
employee-count columns depend on them) — script 08 only adds the columns
the Employee Profile screen needed that were not already there.

> **Before running script 05**, change the password on the `hrms_app` login
> and confirm the database name at the top of the file.

> **Fixed in this drop:** script 03 previously failed on SQL Server with
> `Msg 134: The variable name '@CompanyId' has already been declared` on six
> of the eight procedures (Branch, Department, Designation, JobPosition,
> Location, CostCenter). The generator declared `@CompanyId` twice — once in
> the shared LIST-filter preamble, once again as an editable column for the
> entities whose own row stores a `CompanyId`. The duplicate declaration is
> removed; each procedure now declares `@CompanyId` exactly once and every
> `INSERT`/`UPDATE`/filter reference still binds to it correctly. Re-download
> script 03 from this drop before re-running it — every one of the 8
> procedures was re-checked programmatically for parameter-name collisions
> after the fix, not just the six that were reported broken.

### Optional starter data

`db/12_Organization_Seed_Data.sql` fills in a realistic, generic Kuwait
company structure — 5 branches, a 2-level cost center hierarchy, 12
departments, 19 sections, 32 designations (office and blue-collar roles
alike, since Kuwait Civil ID/work-permit paperwork covers both the same
way), 20 job positions and 7 locations — so you have something to click
through and attach employees to right away instead of starting from an
empty Organization Setup screen. It needs at least one row in
`Core.Companies` to already exist (create one via Organization Setup first);
if you have more than one company, set `@CompanyCode` near the top of the
script before running it. Like every other script here it only inserts
rows that do not already exist, so it is safe to re-run, and everything it
adds can be freely renamed or deleted afterwards through the Organization
Setup screens — it is starting data, not a fixed requirement.

### Employee Profile extensions and Dependents

Scripts 13–15 extend the Employee Profile screen:

- **Personal Info** gains Religion and Blood Group (Identity section), and
  the single free-text Address field is replaced by a structured Kuwait
  PACI-style breakdown in a new Address section: Neighborhood, Block,
  Street Name, Building/Villa Number, Floor Number, Flat Number, PACI
  Number and Landmark. Neighborhood and Block are plain text, not
  dropdowns — there is no existing master table for Kuwait's neighborhoods
  and blocks (unlike Governorate, which already has one), so add one and
  switch these over later if picklists turn out to matter more than free
  entry.
- **Employment** gains Notice Period (Days) in the Employment Terms
  section.
- **Contact** gains an Extension field alongside Mobile Number.
- A new **Dependents** tab (disabled until the employee is first saved,
  same as Kuwait Compliance and Documents) lists a spouse, children or
  other dependents with an Add/Edit modal and health-insurance coverage
  toggle. Unlike Kuwait Compliance, which is a 1:1 record, Dependents is a
  real one-to-many list with its own LIST/GET/INSERT/UPDATE/DELETE
  procedure scoped by employee — there is no company-wide dependents grid.

Note: `Kuwait.EmployeeCompliance` already had its own `BloodType` and
`PaciNumber`/`PaciAddress` fields on the Kuwait Compliance tab (driving
license / government PACI-file context). The new `BloodGroup` and
`PaciNumber` on `Employee.Employees` are deliberately separate columns for
the general Personal Info record, edited from a different form — they will
usually agree with the Compliance tab's values in practice but are not the
same column.

### First sign-in

Script 06 seeds one login so you can get into the application before any
other users exist:

| Username | Password | Notes |
|---|---|---|
| `administrator` | `Admin@12345` | `MustChangePassword` is set — change this immediately in a real environment. The self-service change-password screen is not built yet (see *Not built yet* below), so for now the flag only shows a reminder banner after sign-in; rotate the password directly via `Security.usp_Auth_Manage @Action='CHANGE_PASSWORD'` until that screen exists. |

This account is a member of the seeded `SYSADMIN` role, which is granted
every permission in the system, including the new `ORGANIZATION_*`
permissions used by Module 3.

---

## Application setup

Set the connection string outside source control.

**Development** — user secrets:

```bash
cd src/HRMS.Web
dotnet user-secrets init
dotnet user-secrets set "Database:ConnectionString" \
  "Server=.;Database=HRMS_Kuwait;User Id=hrms_app;Password=YourPassword;Encrypt=True;TrustServerCertificate=True"
```

**Production** — environment variable or Key Vault:

```
Database__ConnectionString=Server=...;Database=HRMS_Kuwait;User Id=hrms_app;Password=...;Encrypt=True
```

The lockout policy is configured in `appsettings.json` under `Authentication`
and can be overridden per environment the same way:

```json
"Authentication": {
  "MaxFailedAttempts": 5,
  "LockoutMinutes": 15,
  "SessionMinutes": 60,
  "PersistentDays": 14
}
```

Then:

```bash
dotnet run --project src/HRMS.Web
```

The first page is the sign-in screen. An unauthenticated request to any URL
redirects there with a `returnUrl`; a signed-in user is sent on to
Organization Setup.

### Editing the theme

```bash
cd src/HRMS.Web
npm install
npm run css:watch     # rebuilds wwwroot/css/hrms.css on save
```

Responsive (container queries) and Arabic/RTL rules live in `_responsive.scss`
and `_rtl.scss` - see "Responsive layout" and "Bilingual UI" below.

SCSS sources live in `wwwroot/scss/`. `_tokens.scss` is the single source of
truth for every colour, spacing step, radius and shadow — nothing else in the
stylesheet contains a raw hex value.

---

## Module 4 — Workforce (Employees & Kuwait Compliance)

One **Employees** list (`/employees`) — the same search / status filter /
column sort / server-side paging grid as Organization Setup — and, per
employee, one **Employee Profile** page (`/employees/profile/{id}`) with
four tabs:

- **Personal Info** — name (English + Arabic), gender, date of birth,
  marital status, nationality, religion, blood group, contact details
  (mobile, extension, personal/work email), a structured Kuwait PACI
  address (Neighborhood/Block/Street/Building/Floor/Flat/PACI Number/
  Landmark), emergency contact, and Father's Details (name,
  occupation, mobile, deceased, currently residing in). Passport and
  Civil ID are intentionally NOT collected here — they live only on
  the Kuwait Compliance tab below, to avoid two places to edit the
  same information (an earlier version of this tab briefly had its
  own copies of these fields; removed as redundant).
- **Employment** — company, branch, department, section, cost center, work
  location, job position, designation, grade, reporting manager, hire /
  probation / termination dates, employment type, and **Employment
  Status** (`Active`, `Probation`, `OnLeave`, `Suspended`, `Terminated`,
  `Resigned`).
- **Kuwait Compliance** — Civil ID, passport, residency (iqama) and
  sponsor, Ministry of Labour file / work permit, PACI address, driving
  licence and blood type/health certificate — each with its own expiry
  date, since expiry tracking is the point of this tab.
- **Documents** — every active document type from `Documents.DocumentTypes`,
  grouped under its **Document Section** (`Documents.DocumentSections`,
  ordered by `Seq_num`) in one table, each row with its own upload slot
  (PDF/JPG/PNG, 5 MB, checked by content signature, not just extension).
  Types flagged `Attachment_Mandatory = 1` show a red *Mandatory* badge and
  are listed in a "missing" banner until a file is attached. Uploads save
  immediately; replacing a file keeps the old one as history (soft delete).
  Files are stored on disk under `DocumentStorage:RootPath`
  (default `App_Data/uploads`, outside `wwwroot`) and served only through
  `/employees/documents/{employeeId}/file/{id}` for signed-in users. See
  `db/19` and `db/22`.

Personal Info and Employment save together in a single call, because they
are the same `Employee.Employees` row — the page uses one `<form
id="employee-form">` that both tab-panes attach to via the HTML5
`form="employee-form"` attribute (not nested inside it — a `<form>` cannot
contain another `<form>`, and Bootstrap's tab plugin expects `.tab-pane`
elements to stay plain siblings). Kuwait Compliance is a genuinely separate
1:1 record, so it has its own form and its own **Save Compliance Details**
button, and its tab (along with Documents) is disabled until the employee
has been saved at least once — there is nothing to attach a compliance
record to before that.

### Add Employee wizard and Edit collapsible sections

**Add Employee** (`/employees/add`) is a separate screen from the Profile
page above, not another tab state — a 4-step wizard (Personal → Employment
→ Contact → Review) that walks through the same fields as the Profile
tabs, one screen at a time, with a numbered stepper at the top and a
read-only Review step before the final **Create Employee**. It posts to the
same `/employees/save` endpoint as the Profile page and lands on the new
employee's Profile page afterwards, where Kuwait Compliance becomes
available. Still the light Corporate Blue & White theme throughout — the
wizard is a layout pattern, not a re-skin.

On the **Profile** page's Personal Info, Employment and Kuwait Compliance
tabs, each field group (Identity, Contact, Emergency Contact, Organization,
Role, Employment Terms, Civil ID, Passport, Residency & Sponsorship, MOL &
Work Permit, PACI Civil Address, Driving & Medical) is now a collapsible
section with a shaded header, so a tab with many fields can be scanned
section-by-section instead of all at once. The Basic Employee Info strip at
the top of the page (avatar/initials, name, status, Department and
Designation) stays visible above the tabs regardless of which section is
expanded.

Two small layout changes applied to both the wizard and the Profile tabs:
Gender, Date of Birth, Marital Status and Nationality now sit on one row,
and Mobile Number, Personal Email and Work Email now sit on one row.

### Known gaps in this module

- **Dropdowns are not cascading yet.** Organization Setup's Company →
  Branch/Department and Department → Section cascades (re-querying
  `/organization/lookup` on change) were not carried over to the Employee
  Profile form — every dropdown is populated with the full list up front.
  Functionally complete, just not filtered as you type; wiring the same
  cascade behaviour in is a small, well-understood follow-up.
- **No live duplicate-code check on blur**, unlike the Organization Setup
  forms. `Employee.usp_Employee_Manage`'s INSERT/UPDATE actions still
  enforce the `EmployeeCode` uniqueness check server-side (`DUPLICATE_CODE`
  surfaces as a normal save error) — this only skips the instant
  before-you-submit feedback, which would need `EMPLOYEE` added to
  `Core.usp_Master_CheckDuplicate` and its C# allowlist.
- **No photo upload.** `PhotoPath` exists as a column but
  has no upload UI (the Documents tab now handles document uploads - see above). A working
  upload (Passport/Civil ID scans, JPG/PNG/PDF, 5 MB max, saved under
  `wwwroot/uploads/employees/documents/`) was built and then removed
  from the Personal Info tab as part of undoing the Passport/Civil ID
  duplication below — the `SaveUploadedDocumentAsync` pattern in
  `EmployeesController`'s git history is worth reusing if a photo or
  Documents-tab upload gets built for real later.
- **No `[Authorize(Policy = ...)]` gate**, same as Organization Setup —
  any authenticated user can reach `/employees` today.

## Payroll — Phase 1 (Master Setup)

Database layer for the Payroll Master Setup screen. Everything is
**data-driven**: components, calendars, salary structures, statutory rates
and banks are rows, so they can be added, deactivated or (soft-)deleted
from the UI with no code change.

| # | Script | What it does |
|---|---|---|
| 29 | `db/29_Payroll_Master_Tables.sql` | Creates the 13 `Payroll.*` master tables (soft-delete columns, filtered unique indexes). Starts with a pre-flight check that stops without changing anything if a same-named table with a different structure already exists in the `Payroll` schema. |
| 30 | `db/30_Payroll_Master_StoredProcedures.sql` | `Payroll.ufn_IbanIsValid` + 9 `usp_*_Manage` procedures (same envelope as Organization Setup) + `usp_PayComponent_SeedDefaults` |
| 31 | `db/31_Lookup_Payroll.sql` | Reissues `Core.usp_Lookup_Get` (body from script 28, unchanged) with the payroll dropdowns added |
| 32 | `db/32_Payroll_Seed_Data.sql` | Payroll permissions (granted to SYSADMIN), the minimum earnings/deductions for every existing company, Kuwaiti banks, statutory defaults |

Run 29 → 32 in order, after 28. All four are idempotent. They need
compatibility level 130+ (SQL Server 2016+) for `OPENJSON`, and must be run
with `QUOTED_IDENTIFIER ON` (the SSMS default; with `sqlcmd` add `-I`).

### Tables

| Area | Table(s) | Notes |
|---|---|---|
| Payroll Calendar | `PayrollCalendars`, `PayrollPeriods`, `PayrollPeriodStatusHistory` | Frequency Monthly / Bi-weekly / Weekly. Monthly: cut-off day + payment day (+ "next month" flag); weekly / bi-weekly: offsets in days from period end. Working-days basis (fixed 26/30, calendar, working). One default calendar per company. |
| Salary & deduction components | `PayComponents` | **One table for both** (`ComponentType` = EARNING / DEDUCTION), per company. Properties: Fixed / Variable, calculation method (Amount, Percentage, Days, Hours, Formula) and base, Taxable, PIFSS, End-of-service, Overtime, Leave-salary, Recurring / One-time, Prorated, GL account, Cost center, display order. |
| Salary structures | `SalaryStructures`, `SalaryStructureComponents` | Grade templates matched to Designation / Job Position / Grade with effective dates; each line can override the component's method / base / amount / %. |
| Statutory (effective-dated) | `PifssContributionRates`, `IndemnityRuleSets` (+ `IndemnityServiceSlabs`, `IndemnityEntitlementFactors`), `OvertimeRates` | Nothing hard-coded. Every row has `IsVerified`. |
| Banks | `Banks`, `CompanyBankAccounts` | SWIFT, IBAN bank code, WPS bank code; company debit account with IBAN (mod-97 checked), WPS employer code, PAM file no., one default per company. |

### Rules enforced in the procedures

- **Period status workflow** (`usp_PayrollPeriod_Manage @Action='SET_STATUS'`):
  OPEN → PROCESSING → APPROVED → POSTED → CLOSED, with PROCESSING → OPEN and
  APPROVED → PROCESSING as re-open steps. Periods are processed in order
  (an earlier period must be POSTED/CLOSED first). Every change is written to
  `PayrollPeriodStatusHistory`. Only OPEN periods can be edited or deleted.
  Once any period has left OPEN, the calendar's company, frequency and
  start date are locked.
- `@Action='GENERATE'` creates a year's periods for a calendar and skips any
  that already exist. Monthly calendars may start on day 1–28; a start day of
  21 gives 21 Sep – 20 Oct = "October".
- **Standard components** carry a `SystemCode` (BASIC, OVERTIME, LOAN,
  SALARY_ADVANCE, ABSENCE, UNPAID_LEAVE, PIFSS_EE) because the payroll engine
  must recognise them. They can be renamed and re-flagged and deactivated, but
  not deleted, and their code / type are fixed. **Basic Salary** cannot be
  deactivated. Every other component (Housing, Transport, Food, Telephone,
  Other Allowances, Bonus, Commission, Incentives, Insurance, Other Deductions
  and anything you add) is fully editable and deletable.
- A component used in a salary structure cannot be deleted or switched between
  Earning and Deduction. The PIFSS / indemnity / overtime / leave flags are
  earnings-only.
- **Salary structures** are saved header + lines in one call (`@LinesJson`),
  must include Basic Salary, and two active structures for the same
  Designation / Position / Grade cannot overlap in time.
  `@Action='RESOLVE'` returns the best match for a new hire
  (Job Position > Designation > Grade, then latest effective date).
- **Statutory rows** cannot overlap in time for the same key. To change a rate,
  end-date the current row and add a new one, so history is kept.
- New company? `usp_PayComponent_Manage @Action='SEED', @CompanyId=…`
  loads the standard components for it.

### ⚠ Statutory seed values must be confirmed

Script 32 seeds PIFSS (employee 8 % up to KWD 2,750 + 2.5 % up to KWD 1,500,
employer 11.5 % up to KWD 2,750 — per PwC Worldwide Tax Summaries), the Labour
Law 6/2010 indemnity rules (15 days/year for the first 5 years, 1 month/year
after, cap 18 months; resignation 0 / 50 / 66.67 / 100 %) and overtime
multipliers (1.25 / 1.50 / 2.00). **All are `IsVerified = 0`.** Have the
client's finance / legal team confirm them, then tick Verified. The Phase 2
engine should refuse to run with unverified rows in force. Bank WPS codes are
left blank on purpose; take them from each bank's WPS file specification.

### Not in this phase

The Employee Salary tab (assigning a structure/package to an employee, salary
history, employee bank/IBAN moving off `Employee.EmployeePayroll`), the
payroll engine, payslips and WPS files are Phase 2+ (Payroll Processing is now done — see the next section). The screens for the
masters above are the next step.

---

## Payroll — Phase 2 (Payroll Processing, live)

The whole **Payroll** menu is now in the app. **Payroll Processing** and **Pay Items** work end to
end; every other payroll page is embedded as a **design preview** (sample data,
a banner at the top says nothing is saved) and will be made functional one page
at a time.

### Database — run after 29–33, in this order

| # | Script | What it does |
|---|---|---|
| 34 | `db/34_Payroll_Processing_Tables.sql` | `Payroll.EmployeePayItems` (salary, earnings, deductions, loans as line items), `Payroll.PayrollRuns`, `PayrollRunEmployees`, `PayrollRunLines`, `PayrollRunIssues`, `PayrollRunHistory`; the `ItemClass` column on `Payroll.PayComponents`; moves each employee's basic + other allowances from `Employee.EmployeePayroll` into monthly salary items (comment "Moved from the employee profile"); adds the PAYROLL_RUN_* permissions to SYSADMIN |
| 35 | `db/35_Payroll_Processing_StoredProcedures.sql` | `usp_PayrollRun_Calculate` (the engine), `usp_PayrollRun_Validate`, `usp_PayrollRun_Manage`, `usp_PayrollRunEmployee_Manage`, `usp_PayrollRunIssue_Manage` |
| 36 | `db/36_Payroll_Labels.sql` | English + Arabic labels of every payroll page (`pr.*`, `prv.*` previews, `js.pr*`, `msg.pr_*`) into `Core.UiLabels`. Re-runnable: it only inserts new keys and fills empty Arabic — your edits are kept |

All three are idempotent (safe to run twice). Nothing is physically deleted —
every table has the `Deleted` bit and goes through `usp_SoftDelete_Apply`.

> **Legacy table:** if your base schema already has an (empty) `Payroll.PayrollRuns`,
> script 34 renames it to `Payroll.PayrollRuns_Legacy` (its constraints and
> triggers get `_Legacy` too) and creates the new table. If that legacy table
> **has rows**, script 34 stops with a message instead — tell us and we will
> migrate them.

> **Sign out and in again** after script 34 — the new permissions
> (PAYROLL_RUN_VIEW / PROCESS / APPROVE_HR / APPROVE_FINANCE / CANCEL / REOPEN)
> are read at sign-in.

### Sections (sidebar: Payroll > Payroll Processing)

| Section | URL | Count in the sidebar |
|---|---|---|
| Payrolls | `/payroll/payrolls` | open payrolls (Registered, Validation, Awaiting approval) |
| Payroll Calendar | `/payroll/calendars` | active payroll calendars |
| Period | `/payroll/pay-periods?calendar=&year=` | open periods (Open / Processing) of this year, all active calendars |
| Payroll History | `/payroll/history` | — |

**Payrolls** lists the open payrolls (filter by stage or period to see the
others). Opening a payroll goes to the page of **its own stage only** —
Register, Validation or Approval (a closed payroll on Approval, a cancelled one
on Register); the other stage pages are not offered, and a link to a stage the
payroll is not at redirects to the right one. Create Payroll is the button on
Payrolls. Payroll History filters by Year and **Period** (the period list
follows the year). The old combined page `/payroll/calendar` redirects to Payrolls. The
counts are cached for 20 seconds per user and refreshed at once after any
payroll or payslip action. Run `db/45_Payroll_Processing_Sections_Labels.sql`
for the new labels.

### How a payroll moves

Draft (Create wizard, never listed) → **Registered** → **Validation** →
**Awaiting Approval** (Level 1 HR, Level 2 Finance) → **Closed**; or **Cancelled**
at any stage before Closed (it keeps its number). Register / Validation /
Approval tabs appear only once the payroll selected at the top has reached that
stage; the last payroll opened is remembered.

* **Name** `<CompanyCode>-YYYY-MM-NN`, numbered per company and month across
  calendars, given when the wizard finishes. A description is required unless it
  is the first regular payroll of the month.
* **One live regular payroll** per calendar period. **Off-cycle** payrolls pay only
  the lines added in them and are allowed after the regular one is closed.
* The period follows the payroll: Open → Processing (regular created) → Approved
  (regular closed); Reopen moves it back to Processing.
* **Engine:** active employees in scope, salary items prorated by paid days,
  earnings / deductions / loans (once, monthly or instalments), PIFSS employee
  share for Kuwaitis (capped base). Employees with no salary items fall back to
  their profile salary (warning V02).
* **Validation:** errors block submission (no salary, negative net, no employees);
  warnings must be acknowledged (no IBAN, unverified PIFSS rates, no cost center,
  deductions > 50 %, net change > 25 %, permit/residency expiring, zero net,
  suspended/on leave). Acknowledgements survive a re-validation.
* **Approval:** whoever submitted cannot approve, and the Level 1 approver cannot
  approve Level 2 — except users with the SYSADMIN role. Return sends it back to
  Validation with a comment; Reject cancels it.

### Files

`Controllers/PayrollController.cs`, `Models/Payroll/PayrollViewModels.cs`,
`Domain/Payroll/*`, `Data/Repositories/PayrollRepositories.cs`,
`Views/Payroll/*` (processing) and `Views/Payroll/Preview/*` (previews, generated
from the approved prototypes), `wwwroot/js/payroll.js`, `wwwroot/js/payroll-preview.js`,
`wwwroot/scss/_payroll.scss` (compiled into `css/hrms.css` / `hrms.min.css`).
Preview pages are served at `/payroll/preview/{page}`.

### Pay Items (live)

One list of everything an employee is paid or has deducted - **Salary**,
**Earning**, **Deduction**, **Loan / advance** - one line per item, always
with a comment. Payroll picks up every active item that applies to its month.

Run after 34-36, in this order, then run `36_Payroll_Labels.sql` again (new labels):

| # | Script | What it does |
|---|---|---|
| 37 | `db/37_PayItems_Tables.sql` | Approval fields on `Payroll.EmployeePayItems`, `Payroll.EmployeePayItemHistory`, permissions PAYROLL_ITEM_VIEW / CREATE / EDIT / DELETE (to SYSADMIN) |
| 38 | `db/38_PayItems_StoredProcedures.sql` | `usp_PayItem_Save` (the rules), `usp_PayItem_Manage`, `usp_PayItem_Import` |

> **Sign out and in again** after script 37 so the new permissions are loaded.

Rules:

* **Salary** - every month from a month; needs approval (HR, then Finance -
  the payroll approval permissions). A change is saved as a *new* amount from a
  later month; the current amount is paid until the change is approved and
  starts, then it ends the month before. Deleting an approved change gives the
  old amount back.
* **Earning** - one time or every month (optionally until a month).
  **Deduction** - one time, every month or in instalments.
* **Loan / advance** - total and number of instalments (instalment calculated,
  last one takes the remainder); numbered LN-0001 / SA-0001; needs approval; an
  approved loan keeps its terms (end it or delete it while unpaid).
* Whoever submits an item cannot approve it, and the HR approver cannot give
  the Finance approval - except users with the SYSADMIN role.
* An item already paid by a payroll keeps its amount and months; only the
  comment and the last month can change. It cannot be deleted - **End** it.
* A one-time item cannot go into a month whose regular payroll is closed. When
  that month's payroll is already calculated the save message says to
  recalculate it on the Payroll Register.
* **Excel**: Export (current filters), Download template, Import (.xlsx or
  .csv; every row is checked and nothing is saved unless all rows are valid -
  the rows with problems are listed). No extra NuGet package is needed
  (`Helpers/XlsxFile.cs`).

Files: `Controllers/PayItemsController.cs`, `Models/Payroll/PayItemViewModels.cs`,
`Domain/Payroll/PayItem.cs`, `Data/Repositories/PayItemRepository.cs`,
`Views/PayItems/*`, `Helpers/XlsxFile.cs`, Pay Items section of `wwwroot/js/payroll.js`
and `wwwroot/scss/_payroll.scss`. The page is `/payroll/pay-items` (`?emp=<id>`
opens one employee).

### Searchable dropdowns

Any `<select data-searchable>` gets a search box inside its list (type to
filter, arrow keys + Enter, Escape closes; works in Arabic). The `<select>`
itself stays the source of truth, so forms and page scripts are unchanged —
`HRMS.searchable(select)` and `HRMS.filterOptions(select, keep)` in
`wwwroot/js/site.js`, styles `.hrms-combo` in `_components.scss`. Used by the
Payslips Year / Period / Payroll / Department pickers and the Payroll History
filters.

### Payslips (live)

**Payroll > Payslips** opens in the sidebar into three sub-sections (like Payroll
Processing), each with its figure — payslips **to generate** (closed payrolls,
not generated or outdated), payslips **generated**, and emails **to send** (up to
date, not sent or failed, with an address). Every employee also gets
**My Payslips** in the sidebar:

| Page | URL | What it does |
|---|---|---|
| Generate Payslips | `/payroll/payslips/generate` | Pick a payroll, choose everyone or one department and the language (**Bilingual** English + Arabic on one page, **English**, or **Arabic** right-to-left), then **Generate**. A checklist shows whether the payroll is closed, how many payslips are generated / outdated, and who has no email address. |
| Employee Payslips | `/payroll/payslips/employees` | Every employee of every payroll (or one payroll) with payslip and email status — **Year**, **Period** and **Payroll** pickers (Period follows Year, Payroll follows both; with no payroll chosen the list shows the whole year / period), search, department and status filters, paging. Opens any payslip to view or print. |
| Email Payslips | `/payroll/payslips/email` | The same Year / Period / Payroll pickers (a year or period opens its latest closed payroll); delivery figures (sent, queued, failed, no email address), **Send to all not yet sent**, and Send / Resend per employee. |
| Payslip | `/payroll/payslips/{runId}/{employeeId}` | The payslip itself — **Print / Save PDF** (the browser's print dialog, one A4 page), and an EN / ع / both switch to preview the other languages. |
| My Payslips | `/payroll/payslips/my` | The signed-in employee's own payslips (latest one on top). Needs only a user linked to the employee (`Security.Users.EmployeeId`), no permission — and it ignores the company filter. |

Run after 34–41, in this order:

| # | Script | What it does |
|---|---|---|
| 42 | `db/42_Payslip_Tables.sql` | `Payroll.Payslips` (one row per employee and payroll: number, language, the net it showed, email delivery, views); permissions PAYROLL_SLIP_VIEW / GENERATE / EMAIL (to SYSADMIN) |
| 43 | `db/43_Payslip_StoredProcedures.sql` | `Payroll.usp_Payslip_Manage` — RUNS / SUMMARY / LIST / GET / GENERATE / QUEUE_EMAIL / VIEWED / NAV_COUNTS (sidebar figures), and EMAIL_CLAIM / EMAIL_RESULT for the email sender |
| 44 | `db/44_Payslip_Labels.sql` | English + Arabic labels (`ps.*`, `js.ps_*`, `msg.ps_*`) — same re-run rules as 36 / 41 |

> **Sign out and in again** after script 42 so the new permissions are loaded.

Rules:

* A payslip shows **the payroll's own figures** — the lines and the employee
  snapshot of `Payroll.PayrollRunLines` / `PayrollRunEmployees`. Nothing is
  calculated again and a payslip cannot be edited; to change one, reopen and
  recalculate the payroll.
* Payslips are **generated and emailed only for a Closed payroll**. Payrolls in
  validation or awaiting approval are listed so their payslips can be
  previewed (watermarked *Not final*). Employees excluded from the payroll, and
  employees an off-cycle payroll pays nothing, have no payslip.
* Number `<RunCode>-<EmployeeNo>` (e.g. `DTC-2026-09-01-E1001`). Generating again
  refreshes the language and figures and keeps the number and email history.
* **Outdated:** when a payroll is reopened, recalculated and closed again, a
  payslip whose net changed (or that is older than the new close) is shown as
  outdated — it cannot be emailed until it is generated again. A full
  regeneration withdraws the payslips of employees no longer in the payroll.
* The payslip masks the Civil ID (last 4 digits) and the IBAN (`KW74 •••• 3388`),
  and prints the net in words (English).
* **Email** goes to the work email, else the personal email. It **carries no
  salary figures**: it says the payslip is ready and links to My Payslips,
  where the employee signs in. A background service (`Services/PayslipEmailSender.cs`)
  sends the queue every 30 seconds and records Sent / Failed (with the server's
  reason); an email stuck while sending is retried after 15 minutes.

Email settings — `Payslips:Email` in `appsettings.json` (off by default; queued
emails simply wait until it is switched on, and the Email page says so):

```json
"Payslips": {
  "Email": {
    "Enabled": true,
    "Host": "smtp.office365.com",
    "Port": 587,
    "EnableSsl": true,
    "UserName": "payroll@yourcompany.com",
    "FromAddress": "payroll@yourcompany.com",
    "FromName": "HR & Payroll",
    "AppBaseUrl": "https://hrms.yourcompany.com"
  }
}
```

Keep the SMTP password out of the file: `dotnet user-secrets set "Payslips:Email:Password" "..."`
in development, the environment variable `Payslips__Email__Password` in production.

Not built yet: a server-side PDF attachment (and the "password = last digits of
the Civil ID" PDF from the prototype). It needs a PDF library that can shape
Arabic text, which is a licensing decision for you; until then employees save
the PDF from the print dialog, and nothing confidential is emailed.

Files: `Controllers/PayslipsController.cs`, `Models/Payroll/PayslipViewModels.cs`,
`Domain/Payroll/Payslip.cs`, `Data/Repositories/PayslipRepository.cs`,
`Services/PayslipEmailSender.cs`, `Views/Payslips/*`, `wwwroot/js/payslips.js`,
`wwwroot/scss/_payslips.scss`. The old payslip preview pages
(`/payroll/preview/slip-*`) now redirect to the live pages.

> **Stylesheet fix in this drop:** `wwwroot/scss/hrms.scss` was missing
> `@use "settlement"`, so the compiled `css/hrms.css` had none of the Final
> Settlement styles. It is added (with `@use "payslips"`) and the CSS rebuilt.


### Payroll Settings (live)

**Setup > Payroll Settings** (it sits under **Setup** in the sidebar, after the
organization masters) opens into eight sub-sections.
Every screen is a list with search / filters / a record count, and an add / edit
dialog; nothing is ever physically deleted (soft delete).

| Page | URL | What it keeps |
|---|---|---|
| Payroll Rules | `/payroll/settings/rules` | Kuwait statutory settings, effective-dated and marked *verified*: PIFSS contribution rates, end-of-service indemnity (service slabs + entitlement by separation type), overtime multipliers (statutory default + company overrides). A banner counts the rows still *not verified*. |
| Pay Item Types | `/payroll/settings/item-types` | `Payroll.PayComponents` — earnings and deductions, how each is calculated, PIFSS / indemnity / overtime flags, GL code; **Add standard types** seeds the missing standard set for a company. |
| Deduction Rules | `/payroll/settings/deduction-rules` | The maximum total deductions (% of gross), what happens when it is exceeded (defer in reverse priority order / warn only), and the recovery order (move up / down). One **default** for every company (seeded: 50 %, defer); a company — or one payroll calendar of it — can have its own. Statutory deductions are always taken. |
| Proration Rules | `/payroll/settings/proration` | Per payroll calendar: the day basis (fixed days / calendar days / working days — saved on the calendar itself) and which events are prorated (joiners, leavers, mid-period revisions, unpaid leave, rest days). A calendar shows the defaults until it is first saved. |
| Approval Workflow | `/payroll/settings/approval` | Per process (payroll run, salary revision, loan, salary advance, payroll adjustment, final settlement): level 1 and level 2 approver roles, a delegate for each, the amount above which level 2 is needed, self-approval. A default route per process (seeded with no roles — pick your own roles) and company routes that replace it. |
| Banks & Accounts | `/payroll/settings/banks` | The bank master (SWIFT, IBAN bank code, WPS code) and each company's salary accounts (IBAN checked with mod-97, one default per company, WPS employer code, PAM file number). |
| Bank Formats | `/payroll/settings/bank-formats` | The salary (WPS) file layout per bank: CSV / delimited text / fixed width, header and trailer, file name pattern, and the fields in order (source, fixed value, width, padding, alignment) with a **live sample** of the file. One **default** format (seeded `WPS_CSV`) serves every bank without its own; one active format per bank. |
| GL Mapping | `/payroll/settings/gl-mapping` | The debit / credit GL accounts of a pay item type, for one cost center or any (the most specific row wins; a pay item type's own GL code stays the default). |

The defaults (no company) of Deduction Rules and Approval Workflow apply to every
company: they can be edited — by users not tied to one company — but not
deactivated or deleted.

Run after 29–45, in this order:

| # | Script | What it does |
|---|---|---|
| 47 | `db/47_Payroll_Settings_Tables.sql` | `Payroll.DeductionPolicies` + `DeductionPriorities`, `ProrationRules`, `ApprovalProcesses`, `BankFileFormats` + `BankFileFormatFields`, `GLMappings` (soft-delete guard of db/28 applied), and the starting defaults |
| 48 | `db/48_Payroll_Settings_StoredProcedures.sql` | `usp_DeductionPolicy_Manage` (+ LINES, CALENDARS), `usp_ProrationRule_Manage`, `usp_ApprovalProcess_Manage` (+ ROLES, USERS), `usp_BankFileFormat_Manage` (+ LINES, BANKS), `usp_GLMapping_Manage` (+ COMPONENTS) — lines are saved with their header in one call (JSON) |
| 46 | `db/46_Payroll_Settings_Labels.sql` | English + Arabic labels of all eight screens (`st.*`, `js.st_*`, `msg.st_*`) — safe to re-run |

Payroll Rules, Pay Item Types and Banks & Accounts use the procedures of db/30
(no new script). The permissions are the existing PAYROLL_SETUP_VIEW / EDIT /
CREATE / DELETE.

> **Not wired into the calculation yet.** The payroll engine (db/35) does not
> read Deduction Rules, Proration Rules (nor the calendar's day basis),
> Approval Workflow, Bank Formats or GL Mapping yet — they are stored,
> validated and audited configuration, and each of those screens says so.
> Applying them (deduction cap and deferral, proration, approval routing,
> generating the WPS file, GL posting) is the next engine change.

Files: `Controllers/PayrollSettingsController*.cs` (one partial per screen group),
`Models/Payroll/SettingsViewModels.cs`, `Domain/Payroll/{PayItemTypeSetting,StatutoryRules,Banks,PayrollRules}.cs`,
`Data/Repositories/{PayrollSettingsRepository,PayrollRulesRepository}.cs`,
`Views/PayrollSettings/*`, `wwwroot/js/payroll-settings.js` (one script for every
screen), `wwwroot/scss/_settings.scss`. The old settings preview pages now open
the live screens.


### Bank Processing, Accounting and Payroll Reports (live)

All three work on **closed payrolls** only. Bank Processing and Accounting open in
the sidebar into sub-sections (with their figures); every page has a **Year /
Month** filter row (the month list follows the year) with the record count in the
same row. Payroll Reports keeps its **tab rail**.

| Page | URL | What it does |
|---|---|---|
| Bank File | `/payroll/bank/file` | Pick the payroll (Year / Month / Payroll), review it **per bank** (employees, amount, WPS code ready / missing, bank-specific or default format) and the **cash / cheque** employees (no IBAN - never in the file). Choose the banks (all, or one), the debit account, the format and the value date, then **Generate and download**. The file is built from the bank format (Payroll Settings > Bank Formats: CSV / delimited / fixed width, header, trailer, field order, widths, padding) and **kept as generated** - every download is the same file. Generating it again asks for a **reason** and replaces the previous file; it is refused once payments of that file are recorded as paid or failed. Failed payments re-issued by bank get a **re-issue file**. |
| Payment Register | `/payroll/bank/register` | Every payment (Year / Month / status / method / search, key figures): **Mark paid** (reference, paid date), **Mark failed** (reason), **Re-issue by bank** or **Pay by cash / cheque** - per row or for the ticked rows. |
| Payment History | `/payroll/bank/history` | Every file generated: download again, **Mark sent** (bank upload reference), **Mark file paid** (all its payments still awaiting the bank), its payments. |
| Payroll Journal | `/payroll/accounting/journal` | The closed payrolls of the period (status and search filters) with their journal number and status. **View** opens the journal in a popup - or, before it exists, its preview with **Create journal** (`JV-yyyy-mm-nn`); export, mark posted and reverse are in the popup too. GL Posting's **View** opens the same popup. Each payroll line posts both sides from **GL Mapping** (Payroll Settings): an earning *Dr* its debit account (cost center) / *Cr* its credit account; a deduction *Dr* its debit account / *Cr* its credit account. With no mapping, the pay item type's own GL code is used and the other side goes to the company's **salaries payable** account (Default accounts, on this page; `210100` until set). A side with no account at all posts to `UNMAPPED-<code>` and is flagged. Debits always equal credits; the payable account nets to the payroll's net pay. |
| GL Posting | `/payroll/accounting/posting` | No ERP link yet: **Export Excel** (CSV, Excel opens it), enter it in the books, **Mark posted** with the reference. **Reverse** (with a reason) frees the payroll for a new journal. |
| Cost Center Allocation | `/payroll/accounting/allocation` | An employee's cost split across cost centers from a date (shares add up to 100 %; a new split ends the previous one). The journal splits the employee's earnings by the split in force at the month end, else uses the employee's (or department's) cost center. |
| Payroll Reports | `/payroll/reports/{payroll,salary,deduction,overtime,compliance}` | One tab per family; the tab's reports on the left, the chosen one on the right with Year / Month (a month, or the whole year) and department filters, totals, **Export Excel** and **Print**. |

The reports:

| Tab | Reports |
|---|---|
| Payroll | Payroll register · Summary by department · Variance month on month (new / left / changed) · Employer cost (gross + employer PIFSS) |
| Salary | Salary by grade · Revision history (pay item amount changes) · Headcount and cost trend (12 months) |
| Deduction | Deductions by component · Deductions per employee · Loans outstanding (instalments, recovered, balance) |
| Overtime | Overtime by employee · Overtime by department (amounts - hours are not recorded on the payroll yet) |
| Compliance | PIFSS contribution (employee + employer share, Kuwaiti staff, Civil ID masked) · WPS submission (files per period) · Audit (payroll actions) |

Employer PIFSS uses the rates in force at the month end (Payroll Rules) on the
PIFSS-applicable salary items, capped at the ceiling - the same rule the payroll
uses for the employee share.

Run after 47-48, in this order:

| # | Script | What it does |
|---|---|---|
| 49 | `db/49_Bank_Accounting_Tables.sql` | `Payroll.BankFiles`, `BankPayments`, `JournalBatches`, `JournalLines`, `AccountingDefaults`, `CostAllocations` + `CostAllocationLines`; permissions PAYROLL_BANK_VIEW / PAYROLL_BANK_PROCESS, PAYROLL_GL_VIEW / PAYROLL_GL_POST, PAYROLL_REPORT_VIEW (to SYSADMIN) |
| 50 | `db/50_Bank_Accounting_StoredProcedures.sql` | `ufn_RunPayees`, `ufn_PayrollJournal`, `usp_BankFile_Manage`, `usp_BankPayment_Manage`, `usp_Journal_Manage`, `usp_CostAllocation_Manage`, `usp_PayrollFinance_NavCounts` |
| 51 | `db/51_Payroll_Reports_StoredProcedures.sql` | `usp_PayrollReport` (15 reports), `usp_PayrollReport_Periods` |
| 52 | `db/52_Bank_Accounting_Reports_Labels.sql` | English + Arabic labels (`fin.*`, `js.fin_*`, `msg.fin_*`, sidebar figures) - safe to re-run |

> **Sign out and in again** after script 49 so the new permissions are loaded.

Not built yet: reading a bank's **response file** (paid / rejected lines) - the
register is updated by hand (per payment, per file); and a direct ERP / GL
interface - journals go out as Excel.

Files: `Controllers/{BankProcessing,Accounting,PayrollReports}Controller.cs`,
`Controllers/PayrollFinanceControllerBase.cs`, `Services/BankFileBuilder.cs`,
`Models/Payroll/FinanceViewModels.cs` (the report catalogue), `Domain/Payroll/PayrollFinance.cs`,
`Data/Repositories/PayrollFinanceRepository.cs`, `Views/{BankProcessing,Accounting,PayrollReports,PayrollFinance}/*`,
`Views/Shared/_PayrollSubNav.cshtml` (a section's sub-sections in the sidebar),
`wwwroot/js/payroll-finance.js`, `wwwroot/scss/_finance.scss`. The old previews of
these pages now open the live screens.


### Payroll Dashboard (live)

`/payroll/dashboard` (Payroll > Payroll Dashboard) shows **one payroll month** at a
glance; the month picker in the top bar lists every month with a pay period or a
payroll (default: the latest one up to today). Visible with any payroll view
permission (run, setup, payslips, bank, GL or reports); figures follow the
company selector.

| Block | What it shows |
|---|---|
| Key figures | Current period (calendar, cut-off), run status of the month's main payroll, employees in run (vs last month, joiners / leavers), net payroll (vs last month), employer cost (gross + employer PIFSS share) |
| Net payroll - last 12 months | Bars per month, the chosen month highlighted; KWD or KWD thousands |
| Needs attention | Only what is open, each linking to its screen: validation errors, failed bank payments, warnings, work permits expiring this month, unverified payroll rules, pay items / loans awaiting approval, closed payrolls without a bank file or journal, journals not posted |
| Gross cost by department | Top 8 departments of the month |
| Payroll calendar | The pay periods around the month with their status |
| Quick actions | Links the user's permissions allow |

| # | Script | What it does |
|---|---|---|
| 53 | `db/53_Payroll_Dashboard.sql` | `Payroll.usp_PayrollDashboard` (`@Action` MONTHS, SUMMARY, TREND, DEPT, CALENDAR, ATTENTION) |
| 54 | `db/54_Payroll_Dashboard_Labels.sql` | English + Arabic labels (`dash.*`) - safe to re-run |

Files: `Controllers/PayrollDashboardController.cs`, `Domain/Payroll/PayrollDashboard.cs`,
`Data/Repositories/PayrollFinanceRepository.cs` (`Dashboard*Async`),
`Models/Payroll/FinanceViewModels.cs` (`PayrollDashboardModel`),
`Views/PayrollDashboard/Index.cshtml`, `wwwroot/js/payroll-dashboard.js`,
`wwwroot/scss/_dashboard-payroll.scss`. The old preview now opens the live page.


### Sidebar: auto-minimize and auto-collapse

On desktop (992 px and wider) the sidebar **auto-minimizes** to an icon rail
(72 px) so the page gets the width. It **expands over the page** when the pointer
rests on it, when the **mouse wheel** turns over it, or when the keyboard tabs into
it, and minimizes again shortly after the pointer leaves (not while the account
menu is open). The pin button in its header **keeps it open** instead - the choice
is remembered per browser (`localStorage` key `hrms:nav-mode`).

Sections **auto-collapse**: opening a group (Workforce, Payroll, System, Setup) or a
sub-section (Payroll Processing, Payslips, ...) closes the others at its level, and
when the sidebar minimizes it folds back to the current page's section only. On the
rail every section shows its icon; the current one is highlighted.

Below 992 px nothing changes - the sidebar is the slide-in drawer of the menu
button. Files: `wwwroot/scss/_sidebar.scss` (the look and the rail),
`wwwroot/js/site.js` (behaviour), `wwwroot/js/nav-mode.js` (loaded in `<head>` so the
rail never flashes open - the Content-Security-Policy allows no inline script).

---

## Bilingual UI (English / Arabic) — labels in the database

Every piece of text the application shows — labels, buttons, menus, column
headers, placeholders, validation messages, stored-procedure messages and the
text used by the page scripts — is a row in **`Core.UiLabels`**, in English
and Arabic. Correcting a label is an `UPDATE`, never a code change, and the
running site picks it up within ~30 seconds (no restart).

| # | Script | What it does |
|---|---|---|
| 33 | `db/33_Localization.sql` | `Core.UiLabels` (+ soft delete), `Security.Users.PreferredLanguage` (`'en'`/`'ar'`), `Core.usp_UiLabel_Get`, `Core.usp_UiLabel_Manage` (LIST/GET/INSERT/UPDATE/DELETE/TOGGLE/CAPTURE), `Security.usp_User_Language`; seeds ~820 labels in English **and** Arabic; harvests any other literal `@ResultMessage` from the database's procedures with an empty Arabic text |

Run it after 28 (and after 29–32 if you use them). Idempotent; a re-run never
overwrites a label you have edited. `sqlcmd`: add `-I -f 65001`.

### How it works

* **Language toggle** — top bar (and the sign-in page): *العربية* / *English*.
  It posts to `/account/language`, saves the choice to
  `Security.Users.PreferredLanguage` and **reloads the page**. At sign-in the
  saved language is applied, so a user always gets their own language on any
  device. Before sign-in the choice lives in the `Hrms-Lang` cookie.
* **Arabic** = `<html lang="ar" dir="rtl">`, Bootstrap's RTL stylesheet
  (`bootstrap.rtl.min.css`), Noto Sans Arabic / Noto Kufi Arabic, mirrored
  arrows. Only the UI culture changes: amounts, Civil IDs and dates keep
  Western digits; month names come from the labels `common.month_1..12`.
* **Views** use the injected `L` service:
  ```cshtml
  @L["org.branch_name"]                         plain label
  @L["common.showing_range", first, last, total] label with {0} {1} {2}
  @L.Tr(Model.ActiveTab.Title)                  English text from C# (looked up by EnglishText)
  @L.Date(row.HireDate)                         "06 Oct 2026" / "06 أكتوبر 2026"
  ```
* **JSON responses** (`ActionResponse.Message` and field errors) are
  translated on the way out by `ActionResponseLocalizationFilter`, matching
  the English sentence against `EnglishText` / `SourceText`. A `SourceText`
  with `{0}` placeholders matches sentences with variable parts, e.g.
  `This account is locked ... Try again in {0} minutes.`
* **DataAnnotations** (`[Display(Name)]`, `ErrorMessage`) and the model
  binder's messages go through the same lookup (`LabelStringLocalizer`).
* **Page scripts** read the `js.*` labels from a JSON block the layout
  writes (CSP-safe): `HRMS.t("js.saving", "Saving…")`.
* **Nothing is ever silently English-only:** a label key the code asks for
  but the table does not have, and any message shown in Arabic without a
  translation, is **captured** into `Core.UiLabels` (module `captured` /
  `msg`, `ArabicText` empty) so it appears in the to-do query below.

### Day-to-day

```sql
-- correct a label (either language)
UPDATE Core.UiLabels SET ArabicText = N'اسم الفرع', ModifiedDate = SYSUTCDATETIME()
WHERE  LabelKey = 'org.branch_name';

-- what still needs Arabic (new procedure messages, captured text)
SELECT LabelKey, Module, EnglishText FROM Core.UiLabels
WHERE  Deleted = 0 AND (ArabicText IS NULL OR ArabicText = N'') ORDER BY Module, LabelKey;
```

### Rule for every future screen

1. No literal UI text in a view, script or controller message: add a key
   (`module.snake_case`, e.g. `payroll.run_status`) and use `@L["..."]` /
   `HRMS.t("js....")`.
2. Add the key with English **and** Arabic to the module's database script
   (same `#Seed` pattern as script 33).
3. Procedure messages stay plain English sentences; add them as labels (or
   let script 33's harvest / the runtime capture list them).

## Responsive layout (desktop zoom levels)

Browser zoom shrinks the CSS viewport — a 1920 px monitor is 1536 px wide at
125 %, 1280 at 150 %, 1097 at 175 % and 960 at 200 % (and only ~620 px tall
at 150 % on a laptop). Layout decisions now follow the room a component
really has, not the viewport:

* `.hrms-content` is a CSS **query container** (`content`); KPI strips,
  panel rows and form grids respond to the content width
  (`cq-up` / `cq-down` mixins, breakpoints in `$cq` in `_tokens.scss`).
* Each `.hrms-table-wrap` is its own container (`table`): optional columns
  marked `col-p3` / `col-p2` step aside below 1240 / 900 px of table width,
  cells tighten, and below 600 px the rows become stacked cards — so a table
  in a half-width panel adapts to the panel.
* KPI strips never leave a lone tile (5 → 3 + 2 → 2 + 2 + 1); labels wrap
  instead of being cut off.
* Short windows get a tighter shell; between 992 and 1279 px the top-bar
  buttons collapse to icons.
* New partials: `_responsive.scss`, `_rtl.scss`. Rebuild with `npm run css`.

Verified with automated overflow checks at 1920 / 1536 / 1366 / 1280 / 1097 /
960 / 390 px in both languages (no page-level horizontal scroll, no clipped
text, no table scrolling sideways on the payroll prototypes).

---

## Architecture

```
HRMS.sln
├── src/
│   ├── HRMS.Domain     entities, DTOs, validation attributes — no dependencies
│   ├── HRMS.Data       Dapper, stored-procedure execution, repositories
│   └── HRMS.Web        MVC controllers, Razor views, SCSS, JavaScript
└── db/                 SQL scripts, run in numeric order
```

### Stored procedures only — no inline SQL

Every database call goes through a stored procedure. The consolidation rule
is **one multi-action procedure per entity**, so this module needs 8
procedures rather than the ~40 a procedure-per-operation design would produce:

```sql
EXEC Core.usp_Company_Manage @Action = 'LIST',   @Search = N'gulf', @PageNumber = 1;
EXEC Core.usp_Company_Manage @Action = 'INSERT', @CompanyCode = N'HO', @CompanyName = N'…';
EXEC Core.usp_Company_Manage @Action = 'TOGGLE', @Id = 4;
```

Two further procedures are genuinely shared across the whole application:

- `Core.usp_Lookup_Get` — every dropdown in the system, keyed by `@LookupType`
- `Core.usp_Master_CheckDuplicate` — the uniqueness check behind every master form

All eight `usp_*_Manage` procedures take an identical parameter envelope
(`@Action`, `@Id`, filters, paging, sorting, `@ResultCode`, `@ResultMessage`).
That is what lets `MasterRepositoryBase<T>` implement LIST, GET, DELETE and
TOGGLE once for all eight entities — each concrete repository only declares
its procedure name, its sortable columns, and how to bind its own fields.

---

## Security notes

Written for a vulnerability assessment. Each item is verifiable.

**SQL injection is unrepresentable, not merely avoided.**
`ISqlExecutor` has no method overload that accepts a SQL string. Every command
is issued with `CommandType.StoredProcedure`. The procedure name is validated
against `^[A-Za-z][A-Za-z0-9_]*\.usp_[A-Za-z0-9_]+$` before it reaches the
driver, so a name carrying whitespace, a semicolon or a comment marker is
rejected. There is no `EXEC` or `sp_executesql` in any procedure.

**Sorting cannot be injected.** `ORDER BY` is resolved by `CASE` expressions
over a fixed list of logical column names. The C# side additionally checks the
requested column against a per-entity allowlist and silently substitutes the
default. This is the hole that normally sinks generic list procedures.

**Search cannot be turned into a wildcard scan.** `@Search` has its LIKE
metacharacters (`\`, `%`, `_`) escaped inside the procedure before use.

**Least privilege at the database.** Script 05 grants the application login
`EXECUTE` on the procedure schemas and `DENY`s `SELECT / INSERT / UPDATE /
DELETE / ALTER / REFERENCES` on every table schema. `DENY` outranks `GRANT`,
so the restriction holds even if the account is later added to `db_datareader`
by mistake. A full application compromise still cannot read a salary or a
Civil ID except through a procedure you have reviewed.

**Transport.** `Encrypt=True` and `TrustServerCertificate=false` are applied
centrally in `SqlConnectionFactory`, so an insecure connection string in a
config file cannot downgrade the channel.

**Error messages do not leak schema.** Provider exceptions — including
connection failures, whose SqlClient message names the server — are wrapped in
`DataAccessException` before leaving the data layer. Parameter values are never
logged, because they routinely carry personal data. Business failures
(duplicate code, row in use) come back as `@ResultCode` / `@ResultMessage`
with fixed strings that never echo user input.

**Web tier.** Anti-forgery validation is applied by a global filter, so it is
opt-out rather than opt-in. Security headers (CSP, `X-Frame-Options`,
`X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`) are set in
one middleware. `script-src` is `'self'` with no `'unsafe-inline'`, which is
what stops a reflected payload from executing. Toast and dropdown text is
inserted with `textContent`, never `innerHTML`. CSV export prefixes cells
beginning with `= + - @` to prevent formula injection in Excel. Every
`text/html` response also carries `Cache-Control: no-store`, so pressing
Back after signing out cannot redisplay a page from the browser's cache.

**Passwords.** Hashed with PBKDF2-HMAC-SHA256, 210,000 iterations, a random
16-byte salt per password, stored as a single self-describing binary value
(format marker + iteration count + salt + subkey) so the iteration count can
be raised later without a migration — `PasswordHasher` transparently
rehashes on the next successful login when it detects an older value.
Verification uses `CryptographicOperations.FixedTimeEquals`, a constant-time
comparison that does not leak how many leading bytes matched. Covered by 14
targeted tests (correct password, wrong password, case sensitivity, empty
input, tampered hash, truncated hash, and round-trip against the exact
seeded `administrator` hash in script 06).

**Sign-in flow.** `Security.usp_Auth_Manage` never compares the password —
it returns the stored hash and the account's lockout state, and the
comparison happens in `SignInService` after the hash is unwrapped. An
unknown username still runs the full hashing routine against a decoy value
(`BurnTime()`) before responding, so a timing attack cannot distinguish
"no such user" from "wrong password" by response latency. Every login
attempt — including ones for a username that does not exist — is written to
`Security.UserLoginHistory`.

**Account lockout and rate limiting are two independent layers.** The
database enforces a per-account lockout (`MaxFailedAttempts` /
`LockoutMinutes` in `appsettings.json`) regardless of which IP the attempts
come from. `Program.cs` additionally rate-limits `/account/login` to 10
requests per minute per IP (`Microsoft.AspNetCore.RateLimiting`), which
slows down a distributed attempt to search the account lockout itself.

**The auth cookie carries claims, not a session id.** Permissions and role
codes are baked into the cookie at sign-in (`ClaimsCurrentUser` reads them
straight from `HttpContext.User`), so an authorization check never costs a
database round trip. A `SecurityStamp` claim is compared against the
database value on password or role change — rotating the stamp invalidates
every outstanding cookie for that user without a server-side session store.

**Open redirect is closed on both the model and the rendered form.**
`returnUrl` is accepted only when `Url.IsLocalUrl()` approves it; anything
else — an absolute URL, a protocol-relative `//host` URL, a `javascript:`
URL — becomes `null`. The GET action additionally clears `ModelState` after
building the view model, because ASP.NET Core's `asp-for` tag helper prefers
the raw query-string value in `ModelState` over the sanitised model property,
which would otherwise let a rejected URL reappear verbatim in the form's
hidden field even though the server had already refused it.

---

## Decisions worth knowing about

**Two tables were added.** Your base schema had no table for Designations
(distinct from `Core.Positions`, which models a seat in the org chart) and
none for Locations. Script 02 adds both, following your naming and constraint
conventions. `Core.Governorates` was added to serve the Kuwait governorate
dropdown from the same shared lookup procedure.

**Grades have no maintenance screen yet.** `Core.Grades` is referenced by the
Designation and Job Position forms, but you specified eight tabs and Grades
was not among them, so it is read-only here. If you want it editable, it is a
ninth tab following exactly the same pattern — say the word.

**Deletes are hard deletes, guarded.** Each `DELETE` action checks for
dependent rows first and returns `IN_USE` rather than failing on a foreign
key. Deactivate (`TOGGLE`) is the soft-delete path, and the UI steers users
there when a delete is refused.

**Export is client-side.** The Export button writes exactly what is on screen
to CSV. A server-side export that can be permission-checked and audited
belongs in the Reports module.

**Authentication is real, not a placeholder.** `ICurrentUser` is now
`ClaimsCurrentUser`, reading identity, role, permissions and the active
company straight from the signed-in cookie. It supplies the top-bar identity
and the `@UserId` audit value passed to every procedure — no controller,
repository or procedure needed to change when the placeholder was replaced.

**Employees are never hard-deleted, on purpose — a deliberate departure
from every other master's convention.** `Employee.Employees` already used
`IsDeleted`, not `IsActive`, as its soft-delete flag before this module
existed; that is preserved rather than "fixed." A brand new, separate
`EmploymentStatus` column (`Active`/`Probation`/`OnLeave`/`Suspended`/
`Terminated`/`Resigned`) carries the business lifecycle instead, because a
resigned or terminated employee is never actually removed — payroll, End of
Service and Kuwait Ministry of Labour records all depend on that row still
existing. The Employees grid's Toggle action flips `IsDeleted` (deactivate /
reactivate) exactly like every other master's Toggle, and is completely
independent of `EmploymentStatus`.

**Kuwait Compliance is its own table, not more columns on `Employees`.**
`Kuwait.EmployeeCompliance` is a 1:1 child (`EmployeeId` is both its primary
key and its foreign key) with its own two-action procedure
(`GET`/`UPSERT` — no `LIST`, no paging, no delete of its own; it is deleted
as part of `Employee.usp_Employee_Manage`'s `DELETE` action). It changes on
a different cadence — Civil ID and residency renewals, sponsor transfers —
and the `Kuwait` schema was already reserved for exactly this in the
original design.

**The Reporting Manager dropdown narrows `EmployeeId` (`BIGINT`) to the
shared `LookupItem.Id` (`int`).** Every other lookup in the system keys off
an `INT` master primary key, so `Core.usp_Lookup_Get`'s new `EMPLOYEE`
branch casts `EmployeeId` for that one shared, reused contract rather than
introducing a parallel `BIGINT`-aware lookup type. The actual save still
binds `@ReportingManagerId` as a full `BIGINT` in
`Employee.usp_Employee_Manage` — the cast only affects this one display
list, and only matters once a company passes roughly two billion employee
rows on an `IDENTITY` column that starts at 1.

**Not built yet, and known to be missing:** self-service change password
(the `MustChangePassword` flag currently only shows a banner), forgot
password / reset by email, two-factor authentication (the column exists on
`Security.Users` but nothing reads it yet), and a per-role
`[Authorize(Policy = ...)]` gate on the Organization Setup controller itself
— today any authenticated user can reach it. Wiring real policies to the
seeded `ORGANIZATION_VIEW/CREATE/EDIT/DELETE` permissions is the natural
next step once you have more than one role in the system.

---

## Verified before delivery

- `dotnet build` — solution builds with zero errors and zero warnings
- `/` redirects anonymously to `/account/login?returnUrl=%2F` (HTTP 302)
- `/account/login` renders (HTTP 200); `/account/denied` renders (HTTP 200)
- `POST /account/logout` without a session redirects to login (HTTP 302) —
  confirmed genuinely gated behind `[Authorize]` after fixing a
  controller-level `[AllowAnonymous]` that the compiler flagged (ASP0026) as
  silently overriding it
- `GET /account/logout` is rejected (HTTP 405 — POST only, so a `<img>` tag
  on another site cannot trigger a sign-out)
- All security headers present on every response, including
  `Cache-Control: no-store` on HTML responses
- Anti-forgery token rendered on the login form
- `returnUrl` reflection tested against four payloads (a legitimate local
  path, an absolute URL, a protocol-relative URL, a `javascript:` URL) — only
  the legitimate one survives into the form's hidden field
- With the database unreachable, the response contains no server name, no
  database name, no provider text and no stack trace — only a friendly page
  with a correlation reference, while full detail goes to the server log
- `PasswordHasher` verified against the exact seeded `administrator` hash
  from script 06 with 14 targeted tests (see *Passwords* above)
- Every one of the 8 procedures in script 03 re-checked programmatically
  after the `@CompanyId` fix: no duplicate parameter declarations remain,
  and scripts 04 and 07 were checked the same way and had none to begin with

- **Module 4:** `dotnet build` — solution builds with zero errors and zero
  warnings, including the compiled Razor views under `Views/Workforce`
- `GET /employees` and `GET /employees/profile/0` both route correctly
  (HTTP 302 to the login page when unauthenticated, confirming the
  `EmployeesController` routes resolve rather than 404ing) — `Employees`
  controller, `Views/Workforce/*` (a deliberate mismatch from the
  `{Controller}` view-folder convention, since the folder is named after
  the module, not the route — every action names its view explicitly)
- `Employee.usp_Employee_Manage`, `Kuwait.usp_EmployeeCompliance_Manage`
  and the extended `Core.usp_Lookup_Get` re-checked programmatically for
  duplicate and undeclared parameters, the same scan used on script 03: none
  found (46, 24 and 4 declared parameters respectively, all unique, all used)
- **Fixed while verifying this drop:** `SqlServerOptions.ConnectionString`'s
  `[Required]` validation message contained a literal `{Environment}` that
  `ValidationAttribute` runs through `string.Format` when a failure is
  reported — an unescaped brace is parsed as a composite format placeholder
  and throws `FormatException: Input string was not in a correct format`
  *instead of* showing the intended message, which crashed the app at
  startup with no connection string configured (exactly the situation the
  message exists to explain). The braces are now escaped (`{{Environment}}`).
  This was pre-existing, unrelated to Module 4, and is now fixed for every
  module.

**Not verified end-to-end:** the actual login round trip against a live
database (this environment has no SQL Server instance to connect to), and
the lockout/rate-limit thresholds under real concurrent load. Run scripts
02–11 against a development database, then sign in as `administrator` before
trusting this in an environment that matters.
