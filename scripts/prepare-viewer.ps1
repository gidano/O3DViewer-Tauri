$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CacheRoot = Join-Path $ProjectRoot '.cache'
$SourceRoot = Join-Path $CacheRoot 'Online3DViewer-0.18.0'
$Archive = Join-Path $CacheRoot 'online3dviewer-0.18.0.zip'
$DistRoot = Join-Path $ProjectRoot 'frontend-dist'
$Marker = Join-Path $DistRoot '.prepared-0.18.0-file-open-v1'

if (Test-Path $Marker) {
    Write-Host 'Online3DViewer 0.18.0 frontend already prepared.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

if (-not (Test-Path $SourceRoot)) {
    if (-not (Test-Path $Archive)) {
        Write-Host 'Downloading Online3DViewer 0.18.0 source...'
        Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://github.com/kovacsv/Online3DViewer/archive/refs/tags/0.18.0.zip' `
            -OutFile $Archive
    }
    Expand-Archive -Path $Archive -DestinationPath $CacheRoot -Force
    $Extracted = Get-ChildItem $CacheRoot -Directory | Where-Object { $_.Name -like 'Online3DViewer-*' } | Select-Object -First 1
    if ($null -eq $Extracted) { throw 'Online3DViewer source archive could not be extracted.' }
    if ($Extracted.FullName -ne $SourceRoot) {
        Rename-Item -Path $Extracted.FullName -NewName 'Online3DViewer-0.18.0'
    }
}

# Patch the upstream website only in the temporary build cache. The desktop wrapper starts
# the page with ?open=model://... when Windows supplies a file path via an association.
$UpstreamIndexJs = Join-Path $SourceRoot 'source/website/index.js'
$UpstreamIndexJsText = Get-Content $UpstreamIndexJs -Raw
$OriginalStart = 'website.Load (); }); } export function StartEmbed ()'
$PatchedStart = @'
website.Load ();
        const desktopOpenUrl = new URLSearchParams (window.location.search).get ('open');
        if (desktopOpenUrl !== null && desktopOpenUrl.length > 0) {
            website.LoadModelFromUrlList ([desktopOpenUrl]);
        }
    }); } export function StartEmbed ()
'@
if ($UpstreamIndexJsText.Contains($OriginalStart)) {
    $UpstreamIndexJsText = $UpstreamIndexJsText.Replace($OriginalStart, $PatchedStart.Trim())
    Set-Content -Path $UpstreamIndexJs -Value $UpstreamIndexJsText -NoNewline
} elseif (-not $UpstreamIndexJsText.Contains('desktopOpenUrl')) {
    throw 'Could not apply the desktop file-open patch to Online3DViewer source.'
}

Push-Location $SourceRoot
try {
    Write-Host 'Installing upstream build dependencies...'

    npm ci
    Write-Host 'Creating upstream production package...'
    npm run create_package
} finally {
    Pop-Location
}

$UpstreamWebsite = Join-Path $SourceRoot 'build/package/website'
if (-not (Test-Path $UpstreamWebsite)) {
    throw "Online3DViewer production website was not created at $UpstreamWebsite"
}

Remove-Item -Recurse -Force $DistRoot -ErrorAction SilentlyContinue
Copy-Item $UpstreamWebsite $DistRoot -Recurse -Force
Copy-Item "$SourceRoot/LICENSE.md" "$DistRoot/ONLINE3DVIEWER_LICENSE.md" -Force

$IndexPath = Join-Path $DistRoot 'index.html'
$Index = Get-Content $IndexPath -Raw
$Index = $Index.Replace('<title>Online 3D Viewer</title>', '<title>O3D Viewer</title>')
$Index = $Index.Replace('https://3dviewer.net', 'desktop application')
Set-Content -Path $IndexPath -Value $Index -NoNewline

New-Item -ItemType File -Path $Marker -Force | Out-Null
Write-Host "Prepared O3D Viewer frontend at $DistRoot"
