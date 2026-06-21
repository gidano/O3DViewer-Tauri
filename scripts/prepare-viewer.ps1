$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CacheRoot = Join-Path $ProjectRoot '.cache'
$SourceRoot = Join-Path $CacheRoot 'Online3DViewer-0.18.0'
$Archive = Join-Path $CacheRoot 'online3dviewer-0.18.0.zip'
$DistRoot = Join-Path $ProjectRoot 'frontend-dist'
$Marker = Join-Path $DistRoot '.prepared-0.18.0'

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
    # GitHub's ZIP sometimes already extracts to the desired folder name.
    # Rename only when the source and target are genuinely different paths.
    if ($Extracted.FullName -ne $SourceRoot) {
        Rename-Item -Path $Extracted.FullName -NewName 'Online3DViewer-0.18.0'
    }
}

Push-Location $SourceRoot
try {
    Write-Host 'Installing upstream build dependencies...'
    npm ci
    Write-Host 'Building the upstream website...'
    npm run build_website
} finally {
    Pop-Location
}

Remove-Item -Recurse -Force $DistRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null

Copy-Item "$SourceRoot/website/index.html" "$DistRoot/index.html"
Copy-Item "$SourceRoot/website/assets" "$DistRoot/assets" -Recurse
Copy-Item "$SourceRoot/build" "$DistRoot/build" -Recurse
Copy-Item "$SourceRoot/libs" "$DistRoot/libs" -Recurse
Copy-Item "$SourceRoot/LICENSE.md" "$DistRoot/ONLINE3DVIEWER_LICENSE.md"

$IndexPath = Join-Path $DistRoot 'index.html'
$Index = Get-Content $IndexPath -Raw
$Index = $Index.Replace('../build/website_dev/', 'build/website/')
$Index = $Index.Replace('<title>Online 3D Viewer</title>', '<title>O3D Viewer</title>')
$Index = $Index.Replace('https://3dviewer.net', 'offline desktop application')
Set-Content -Path $IndexPath -Value $Index -NoNewline

New-Item -ItemType File -Path $Marker -Force | Out-Null
Write-Host "Prepared offline viewer frontend at $DistRoot"
