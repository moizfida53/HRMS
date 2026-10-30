# QR Menu (Items Management) database merge

The old QR Menu / POS database (`Pistachio_v4`) merged into `HRMS_Kuwait`.
Run once, in SSMS, on `HRMS_Kuwait`, with `Pistachio_v4` on the same SQL Server instance.
Back up `HRMS_Kuwait` first.

| Step | Script | What it does |
|---|---|---|
| 01 | `01_Merge_ItemsManagement.sql` | Creates the 88 tables, 22 table types, 3 functions and 221 procedures of `Pistachio_v4` in `[dbo]` and copies every row (identity values kept). Stops before changing anything if a name already exists. |
| 02 | `02_Consolidate_Users_Roles_Labels.sql` | Moves `tblcompany` → `Core.Companies`, `tblUser` → `Security.Users`, `tblRole` + `tblPOS_Role_Master` → `Security.Roles` (+ POS permissions), `tblPOS_AuditLog` → `Security.AuditLogs`, `tblLabelName` → `Core.UiLabels`; drops `tblPrinter`; rewrites the 31 procedures that used them. `tblbranch` stays as it is. |
| after 02 | (manual) | If step 02 reports "Old tables NOT dropped" only because of `dbo.sp_Get_DelegateRoleList` (an unrelated old HRMS procedure), drop them by hand: `DROP TABLE dbo.tblPOS_AuditLog, dbo.tblLabelName, dbo.tblPrinter, dbo.tblUser, dbo.tblRole, dbo.tblPOS_Role_Master, dbo.tblcompany;` |

Notes
* The Items Management objects stay in `[dbo]`; the HRMS DDL triggers (`TR_HRMS_NoPhysicalDelete`, `TR_HRMS_SoftDelete_OnCreateTable`) skip `[dbo]`.
* QR Menu role numbers are kept in `Security.Roles.LegacyRoleId` - the QR code compares them as numbers.
* A QR user whose username already existed in HRMS was renamed `<name>_qr<old id>` (e.g. `admin` → `admin_qr1`).
* QR users sign in on the HRMS sign-in page with their old password; it is upgraded to the HRMS hash on first sign-in.
