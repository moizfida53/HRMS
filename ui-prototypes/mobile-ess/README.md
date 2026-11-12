# Employee Self Service (ESS) – Mobile Proposal

> **Implemented (Nov 2026).** The real module now lives in the application at **`/ess`**
> (`src/HRMS.Web/Areas/Ess`, `wwwroot/js/ess.js`, `wwwroot/scss/_ess.scss`, `db/146_Employee_Self_Service.sql`),
> in the TMM theme and logo. This folder keeps the original proposal and static mockup for reference.
>
> **Go-live checklist**
> 1. Run `db/146_Employee_Self_Service.sql` on the database.
> 2. Organization > Locations: enter the **Latitude / Longitude** of each branch location.
>    The employee punches at their *Work Location* (Employee > Employment) or any location of their *Branch*.
>    The overall radius is 50 m (`appsettings.json` > `SelfService:PunchRadiusMeters`; phone GPS is rarely better than 10-25 m near a building, so keep it at 30 m or more); a location can have its own in `Core.Locations.PunchRadiusM`.
> 3. Security > Manage Users: give each employee a user **linked to the employee** (any role, even one with no rights).
> 4. Give the employee an **attendance pattern** (Time & Attendance), so late / short / absent days are worked out.
> 5. Publish over **HTTPS** (phones only allow GPS on HTTPS). Employees open `https://<your-site>/ess`, sign in,
>    and tap *Add to Home Screen* (Android) or *Share > Add to Home Screen* (iPhone).
>
> Every punch attempt, accepted or refused, is logged in `Attendance.MobilePunches` (position, distance, accuracy, IP).


Status: **proposal + static prototype only** – nothing here is wired into `HRMS.Web` or deployed.
Open `index.html` in a browser (use DevTools device mode for phone sizes). The yellow bar at
the top is a prototype-only control to switch Login/App and simulate GPS states.

## 1. Recommendation: PWA first (installable web app), native wrapper later only if needed

| Option | iOS + Android | Effort | Store approval | GPS 15 m check | Verdict |
|---|---|---|---|---|---|
| **PWA inside existing HRMS.Web** (`/ess` area, Razor + Bootstrap) | Yes, one codebase | Lowest – reuses auth, repos, SCSS tokens, RTL | None | Yes (browser Geolocation API, HTTPS, foreground only) | **Recommended** |
| Capacitor wrapper around the same PWA | Yes | +1–2 weeks | Apple + Google | Yes + native plugins (mock-location detection, better accuracy) | Phase 2 if fraud is a problem |
| React Native / Flutter / .NET MAUI native app | Yes | Highest – second UI + API layer | Required | Best | Overkill for 5 screens |

For this feature set (punch, attendance, leave balance and history, a leave request form, a read-only profile), a native app gives you almost nothing a PWA can't. A PWA can use:

* **Geolocation**: `navigator.geolocation.watchPosition({ enableHighAccuracy: true })`, which works on iOS Safari and Android Chrome over HTTPS.
* **Home-screen install ("shortcut")**:
  * **Android/Chrome:** capture the `beforeinstallprompt` event and show your own **"Add to Home Screen"** button. One tap installs it with your icon, full screen and no browser bar.
  * **iPhone/Safari:** Apple **does not allow a button to install**. Detect iOS and show a 2-step hint ("Share → Add to Home Screen"). Since iOS 16.4, opening the site from Chrome/Edge on iPhone also offers the option. After installing, it opens full screen like an app.
* **Offline shell** via a small service worker (cache CSS/JS/icons). Don't cache API data or allow offline punches.

## 2. Separate mobile login: yes, same auth backend

* New route `/ess/login` using a lean `_EssLayout.cshtml`. It does **not** inherit the admin sidebar layout.
* Same `AccountController` logic/stored procedures (`07_Auth_StoredProcedures.sql`), but with an **`ess` role/claim** so employees can only reach `/ess/*` and admins aren't redirected there.
* Login with Employee No. / Civil ID + password. Use a longer sliding cookie for ESS (e.g. 30 days, "Keep me signed in"). The existing `__Host-` secure cookie setup already suits a PWA.
* Set the `manifest.webmanifest` `start_url` to `/ess`, so the home-screen icon goes straight to the app (or to login if the session has expired).

## 3. GPS punch: how to make the 15 m rule reliable

The data model already supports it: `Location` has `BranchId`, `Latitude` and `Longitude`.

1. Add `GeoFenceRadiusM` (default 15) to `Location`. Optionally add `Employee.PrimaryLocationId`, or a mapping table if staff can punch at several sites.
2. **Client:** run `watchPosition` while the Punch screen is open. Show three states, as in the prototype: *Locating…*, *Inside (x m)*, *Outside (x m)*. The button is enabled only when inside.
3. **Server is the authority, not the browser.** `POST /ess/api/punch { lat, lng, accuracy, timestamp }`. On the server:
   * compute the Haversine distance to the assigned location(s);
   * **reject if `distance > radius`**;
   * **reject if `accuracy > ~30 m`** (otherwise a 15 m fence is meaningless);
   * reject duplicate punches and enforce In→Out order and shift windows;
   * store lat/lng/accuracy/distance/IP/user-agent with each punch for audit.
4. **Be realistic about 15 m.** Phone GPS indoors is often 10–50 m. Recommendations:
   * Make the radius **configurable per branch** (15 m default, 30–50 m for indoor or high-rise sites).
   * Tell users to wait a few seconds for accuracy to improve (the prototype hint does this).
   * Optional anti-spoofing extras: branch Wi-Fi public IP allow-list, a selfie at punch time, or the Capacitor wrapper with mock-location detection on Android.
5. **Required code change:** `SecurityHeadersMiddleware.cs` currently sends `Permissions-Policy: geolocation=()`, which **blocks GPS for the whole site**. For ESS pages it must become `geolocation=(self)`.

## 4. Screens / scope (matches your list)

| Tab | Content | Notes |
|---|---|---|
| **Punch** | Live clock, geofence status, big Punch In/Out button, today's In/Out/Worked, annual-leave ring, month Present/Absent/Short | Home screen |
| **Attendance** | Month picker, 4 counters (Present/Absent/Short/Leave), colour calendar, daily log | Log shows as stacked rows on phones and a Bootstrap table from `md` up |
| **Leave** | **Annual leave only**: entitled/taken/pending/balance + history with status pills + **Request** form | No sick or other leave types shown. Bottom sheet on phones, centred dialog on tablet/desktop |
| **Profile** | Read-only personal and employment fields, sensitive values masked | No inputs rendered at all, only `<dl>`; a "contact HR" note |

## 5. Responsive layout (as built in `index.html`)

| Breakpoint | Shell | Content |
|---|---|---|
| `< 360px` (small phones) | Bottom tab bar | Punch button shrinks 168 → 140 px, clock font scales down |
| `xs/sm < 768px` | Sticky navy top bar + **fixed bottom tab bar** (safe-area aware for iPhone notch/home bar) | Single column, FAB "Request leave", leave form as **bottom sheet** (Bootstrap offcanvas) |
| `md 768–1199px` | **Icon side rail** (96 px) replaces the bottom bar | 2-column Bootstrap grid (calendar + log side by side), leave form becomes a centred dialog |
| `xl ≥ 1200px` | Rail expands to **labelled sidebar** (220 px) | Punch card `col-lg-5` + summary `col-lg-7`, content max-width 1180 px |

Mobile UX details already in the prototype: 16 px inputs (stop iOS auto-zoom), ≥ 44–52 px touch targets,
`100dvh`, `env(safe-area-inset-*)`, `prefers-reduced-motion`, and `inset-inline`/`border-inline-*` logical
properties so the **existing `bootstrap.rtl` + Arabic** setup works without extra CSS.

## 6. Suggested implementation shape (when you're ready) – .NET 10 branch

The `Attendance` and `Leave` schemas and the `AttendanceController` / `LeaveController` already exist,
so ESS is mostly a **thin employee-scoped layer** over them. No new leave or attendance engine is needed.

| ESS feature | Reuse | Add |
|---|---|---|
| Punch In/Out | `[Attendance].[Records]`, `usp_AttRecord_Manage` (the same table the import feeds) | `Source = 'ESS'`, Lat/Lng/Accuracy/DistanceM columns; `[Organization].[Locations].GeoFenceRadiusM` |
| Present / Absent / Short | `usp_AttSheet` / `usp_AttSummary_Manage` (Short column from 138/139) | Filter to the signed-in employee only |
| Annual balance + history | `[Leave].[LeaveLedger]`, `usp_LeaveBalance_Manage`, `[Leave].[LeaveRequests]` | Filter to the Annual leave type only (hide sick and other types) |
| Submit annual leave | `usp_LeaveRequest_Manage` (with `LeaveRequestHistory`) | Force LeaveType = Annual and Status = Pending; EmployeeId taken from the login claim, never from the form |
| Profile | existing Employee select procs | Read-only view model |

```
src/HRMS.Web/
  Areas/Ess/Controllers/   EssAccountController, EssHomeController, EssApiController (punch, leave)
  Areas/Ess/Views/         _EssLayout.cshtml, Login, Index (tabs as partials)
  wwwroot/scss/_ess.scss   prototype styles moved onto _tokens.scss variables
  wwwroot/manifest.webmanifest, wwwroot/ess-sw.js, icons 192/512 + apple-touch-icon 180
db/
  1xx_Ess_Geofence.sql            Locations.GeoFenceRadiusM, Records geo columns, ESS role
  1xx_Ess_StoredProcedures.sql    usp_Ess_Punch (Haversine + radius + accuracy check), thin ESS wrappers
```

This follows the same pattern as the existing `Areas/Items` and `Areas/POS`. If you later want a React or Angular
front end for ESS, the same `EssApiController` JSON endpoints can serve it unchanged.
