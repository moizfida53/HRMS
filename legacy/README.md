# legacy/

Read-only reference copies of projects being merged into HRMS. Nothing here is built or deployed.

## ItemManagement/

The old QR Menu / Online Ordering / POS project (ASP.NET MVC 4, .NET Framework 4.8),
as it was when the merge started. Modules are ported one at a time into
`src/HRMS.Web/Areas/Items` (see `Areas/Items/Legacy` for the compatibility layer);
port the next module from these files, then delete them once everything is moved.

Left out on purpose:
* secrets - every key, token and password in `Web.config`, `Web.*.config` and
  `Hesabe/HesabeConstants.cs` is `__SET_IN_LOCAL_CONFIG__`; the Mapbox token in the
  delivery-address pages is `__MAPBOX_ACCESS_TOKEN__` and the Google Maps key in
  `TrackingOrder.cshtml` is `__GOOGLE_MAPS_API_KEY__` (also in `wwwroot-qr/MainJs/*/BindCartDetails.js`).
  The real values stay on the old server / your PC - move them to configuration when
  those pages are ported, and rotate any that were ever committed elsewhere
* third-party UI kits under their own licences (`assets` = Metronic, `DashboardContent`,
  `vendor`, `Content`, `Scripts`, `fonts`, jqWidgets `jqx-*`) and the menu photos -
  `tools/Copy-QrMenuAssets.ps1` copies them into `src/HRMS.Web/wwwroot-qr`
* `bin`, `obj`, publish output, `.bak` copies

| Module | Old controller(s) | Status |
|---|---|---|
| Item Management | `CategoryController` + `Views/Category`, `MainJs/Category.js` | **Ported** - `/Category/Index` |
| Menu Colors | `MenuColorsController` + `Views/MenuColors` | **Ported** - `/MenuColors/Index` |
| Settings (Tab Theme, Slide Show, labels) | `TabTheme`, `SlideShow`, `Items` (parts) | Not yet |
| POS (Dine-In, Orders, Dashboard, Payment, Users) | `Areas/POS/*` | **Ported** - `/POS/DineIn`, `/POS/Orders`, `/POS/Dashboard`, `/POS/Users` (live table status over ASP.NET Core SignalR) |
| Printer Setup | `Areas/POS/PrintController` | **Ported** - `/POS/Print` |
| Restaurant hub (offline + printing) | `PrintAgent/` | Not yet |
| Customer QR menu, cart, checkout, payments, order tracking, feedback | `ItemsViewNew`, `ItemsView`, `Payment`, `Hesabe/`, helpers | **Ported** - `/?id=<BrandID>,<BranchID>` |
| Table reservations | `BranchReservation` | **Ported** (customer booking + admin page) |
| Feedback report | `FeedBackReportController` | **Ported** - `/FeedBackReport/Index` |
| Item dashboard, Mobile, WebService.asmx, Waiter login | various | Not yet |
