$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CacheRoot = Join-Path $ProjectRoot '.cache'
$SourceRoot = Join-Path $CacheRoot 'Online3DViewer-0.18.0'
$Archive = Join-Path $CacheRoot 'online3dviewer-0.18.0.zip'
$DistRoot = Join-Path $ProjectRoot 'frontend-dist'
$Marker = Join-Path $DistRoot '.prepared-0.18.0-desktop-open-v2'

if (Test-Path $Marker) {
    Write-Host 'Online3DViewer frontend already prepared.'
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
    $Extracted = Get-ChildItem $CacheRoot -Directory |
        Where-Object { $_.Name -like 'Online3DViewer-*' } |
        Select-Object -First 1

    if ($null -eq $Extracted) {
        throw 'Online3DViewer source archive could not be extracted.'
    }

    if ($Extracted.FullName -ne $SourceRoot) {
        if (Test-Path $SourceRoot) { Remove-Item -Recurse -Force $SourceRoot }
        Rename-Item -Path $Extracted.FullName -NewName 'Online3DViewer-0.18.0'
    }
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

# Do not modify upstream source code. Instead, append a tiny desktop bridge to the
# already-built webpage. On file-association launch it fetches model:// bytes,
# creates a browser File, and sends the exact same HTML5 drop event the upstream
# viewer already handles for normal Explorer drag-and-drop.
$BridgePath = Join-Path $DistRoot 'desktop-open.js'
$Bridge = @'
(() => {
    const params = new URLSearchParams(window.location.search);
    const modelUrl = params.get('open');
    const fileName = params.get('name') || 'model';
    if (!modelUrl) return;

    const dispatchDrop = async () => {
        try {
            const response = await fetch(modelUrl);
            if (!response.ok) throw new Error(`Unable to read model (${response.status})`);

            const blob = await response.blob();
            const file = new File([blob], fileName, { type: 'application/octet-stream' });
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);

            const target = document.body || document.documentElement;
            for (const type of ['dragenter', 'dragover', 'drop']) {
                const event = new DragEvent(type, {
                    bubbles: true,
                    cancelable: true,
                    dataTransfer
                });
                target.dispatchEvent(event);
            }
        } catch (error) {
            console.error('O3D Viewer could not open the associated file.', error);
        }
    };

    // The upstream app binds its drop listeners while loading. Wait until the
    // browser load event, then one tick more, so this behaves like a real user drop.
    window.addEventListener('load', () => window.setTimeout(dispatchDrop, 300), { once: true });
})();
'@
Set-Content -Path $BridgePath -Value $Bridge -NoNewline

$IndexPath = Join-Path $DistRoot 'index.html'
$Index = Get-Content $IndexPath -Raw
$Index = $Index.Replace('<title>Online 3D Viewer</title>', '<title>O3D Viewer</title>')
$Index = $Index.Replace('https://3dviewer.net', 'desktop application')

if ($Index -notmatch 'desktop-open\.js') {
    $Index = $Index.Replace('</body>', "    <script src=`"desktop-open.js`"></script>`r`n</body>")
}
Set-Content -Path $IndexPath -Value $Index -NoNewline

New-Item -ItemType File -Path $Marker -Force | Out-Null
Write-Host "Prepared O3D Viewer frontend at $DistRoot"
