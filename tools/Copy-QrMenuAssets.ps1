<#
  Copies the Items Management (QR Menu) files that are deliberately NOT in Git
  from the old project into src/HRMS.Web/wwwroot-qr:
    - third-party UI kits (Metronic "assets", DashboardContent, vendor, Content,
      Scripts, fonts, jqWidgets jqx-* files) - their licences do not allow a public repo
    - menu photos and uploads (images, ThumbnailImages, AdvertisementImages, Video)

  Run once per machine (dev PC and server), and again whenever photos are added
  on the old site:

    powershell -ExecutionPolicy Bypass -File tools\Copy-QrMenuAssets.ps1 `
        -OldProject "D:\Main Source Code\QR_Menu_SourceCode\eCommerce\ItemManagment\Project"

  On the server, point -Target at the published site's wwwroot-qr folder instead.
#>
param(
    [Parameter(Mandatory = $true)] [string] $OldProject,
    [string] $Target = (Join-Path $PSScriptRoot "..\src\HRMS.Web\wwwroot-qr")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OldProject)) { throw "Old project folder not found: $OldProject" }
New-Item -ItemType Directory -Force -Path $Target | Out-Null

$folders = "assets", "DashboardContent", "vendor", "Content", "Scripts", "fonts",
           "images", "ThumbnailImages", "AdvertisementImages", "Video"

foreach ($f in $folders) {
    $src = Join-Path $OldProject $f
    if (Test-Path $src) {
        Write-Host "Copying $f ..."
        # /E all sub-folders, /XO skip files that are older than the target copy
        robocopy $src (Join-Path $Target $f) /E /XO /NFL /NDL /NJH /NJS /NP | Out-Null
    } else {
        Write-Host "  (skipped, not found: $f)"
    }
}

# jqWidgets files that sit inside the committed css/js folders
foreach ($f in "css", "js", "Content") {
    $src = Join-Path $OldProject $f
    if (Test-Path $src) {
        Get-ChildItem $src -Recurse -File -Filter "jqx*" | ForEach-Object {
            $rel = $_.FullName.Substring($OldProject.Length).TrimStart('\')
            $dst = Join-Path $Target $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
            Copy-Item $_.FullName $dst -Force
        }
    }
}

Write-Host "Done. Files are in $Target"
