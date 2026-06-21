$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CacheRoot = Join-Path $ProjectRoot '.cache'
$DistRoot = Join-Path $ProjectRoot 'frontend-dist'
$Marker = Join-Path $DistRoot '.prepared-0.18.0'
$PackageRoot = Join-Path $CacheRoot 'online-3d-viewer-package'

if (Test-Path $Marker) {
    Write-Host 'Online3DViewer 0.18.0 frontend already prepared.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
Remove-Item -Recurse -Force $PackageRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null

Write-Host 'Downloading the complete Online3DViewer 0.18.0 npm package...'
# The GitHub source ZIP deliberately does not include the large prebuilt libs folder.
# The npm package includes website + build + libs, which is what the desktop app needs.
$Tarball = npm pack online-3d-viewer@0.18.0 --pack-destination $CacheRoot | Select-Object -Last 1
if ([string]::IsNullOrWhiteSpace($Tarball)) { throw 'npm pack did not return a package filename.' }
$TarballPath = Join-Path $CacheRoot $Tarball.Trim()
if (-not (Test-Path $TarballPath)) { throw "Downloaded npm package was not found: $TarballPath" }

Write-Host 'Extracting the complete viewer package...'
tar -xf $TarballPath -C $PackageRoot
$SourceRoot = Join-Path $PackageRoot 'package'
if (-not (Test-Path $SourceRoot)) { throw 'The npm package could not be extracted.' }

foreach ($RequiredPath in @('website', 'build', 'libs', 'LICENSE.md')) {
    if (-not (Test-Path (Join-Path $SourceRoot $RequiredPath))) {
        throw "The downloaded viewer package is incomplete: missing $RequiredPath"
    }
}

Remove-Item -Recurse -Force $DistRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null

Copy-Item "$SourceRoot/website/*" $DistRoot -Recurse
Copy-Item "$SourceRoot/build" "$DistRoot/build" -Recurse
Copy-Item "$SourceRoot/libs" "$DistRoot/libs" -Recurse
Copy-Item "$SourceRoot/LICENSE.md" "$DistRoot/ONLINE3DVIEWER_LICENSE.md"

$IndexPath = Join-Path $DistRoot 'index.html'
$Index = Get-Content $IndexPath -Raw
# The website is normally one directory below build/. In Tauri's frontend folder it is at the root.
$Index = $Index.Replace('../build/website_dev/', 'build/website/')
$Index = $Index.Replace('../build/website/', 'build/website/')
$Index = $Index.Replace('<title>Online 3D Viewer</title>', '<title>O3D Viewer</title>')
$Index = $Index.Replace('https://3dviewer.net', 'offline desktop application')
Set-Content -Path $IndexPath -Value $Index -NoNewline

New-Item -ItemType File -Path $Marker -Force | Out-Null
Write-Host "Prepared complete offline viewer frontend at $DistRoot"
