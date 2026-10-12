# Publish a built build from Windows: GitHub release asset + <app>/latest.json (the feed the apps
# read). The same as publish.sh, for the apps built on this PC.
#
#   powershell -ExecutionPolicy Bypass -File publish.ps1 installer-assist|ble-devices windows|android ["notes"]
#   powershell -ExecutionPolicy Bypass -File publish.ps1 firmware-flasher windows|firmware ["notes"]
#
# installer-assist / ble-devices: Windows = the NSIS setup .exe (npm run dist:win), Android = the
#   release APK (npm run android:apk:release). Every platform of one version goes into the same
#   release and feed entry.
# firmware-flasher: windows = dist\HSI_90111_Programmer.exe (build.bat; version in
#   flasher\__init__.py); firmware = the flasher's COMMITTED firmware library, packed here by
#   tools\make_firmware_bundle.py (version = its last commit). The two are separate entries of one
#   feed: publishing one keeps the other.
#
# Everything is signed here with hsi-updater.key from HSI_KEYS_DIR (E:\KEYS), $env:HSI_UPDATER_KEY,
# or the app's keys\; the key never leaves this PC. Run it on main (it pushes the feed there).
# Needs the GitHub CLI, signed in: gh auth login.
#
# Keep this file pure ASCII (Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM).

param(
    [Parameter(Mandatory = $true)][ValidateSet("installer-assist", "ble-devices", "firmware-flasher")][string]$App,
    [Parameter(Mandatory = $true)][ValidateSet("windows", "android", "firmware")][string]$Platform,
    [string]$Notes = ""
)
$ErrorActionPreference = "Stop"

$ia = if ($env:HSI_INSTALLER_ASSIST) { $env:HSI_INSTALLER_ASSIST } else { "E:\Installer-assist" }
$flasher = if ($env:HSI_FIRMWARE_FLASHER) { $env:HSI_FIRMWARE_FLASHER } else { "E:\HSI-Firmware-Flasher" }
$keysDir = if ($env:HSI_KEYS_DIR) { $env:HSI_KEYS_DIR } else { [Environment]::GetEnvironmentVariable("HSI_KEYS_DIR", "User") }
$signDir = Join-Path $ia "HSI Installer assist"     # any folder with the Tauri CLI installed (npm ci)
$fw = $null
switch ($App) {
    "installer-assist" { $dir = Join-Path $ia "HSI Installer assist"; $target = Join-Path $dir "target";           $name = "HSI Installer Assist"; $apk = "HSI-Installer-Assist"; $signDir = $dir }
    "ble-devices"      { $dir = Join-Path $ia "BLE devices assist";  $target = Join-Path $dir "src-tauri\target"; $name = "HSI BLE Devices";      $apk = "HSI-BLE-Devices";      $signDir = $dir }
    "firmware-flasher" { $dir = $flasher; $name = "HSI Firmware Flasher" }
}
if ($App -eq "firmware-flasher") {
    if ($Platform -eq "android") { throw "the flasher is a Windows app: windows or firmware" }
    if ($Platform -eq "windows") {
        $m = [regex]::Match((Get-Content (Join-Path $dir "flasher\__init__.py") -Raw), '__version__\s*=\s*"([^"]+)"')
        if (-not $m.Success) { throw "no __version__ in flasher\__init__.py" }
        $ver = $m.Groups[1].Value
        $src = Join-Path $dir "dist\HSI_90111_Programmer.exe"; $key = "windows-x86_64"; $ext = "exe"
    } else {
        $py = Join-Path $dir ".venv\Scripts\python.exe"
        if (-not (Test-Path $py)) { $py = "python" }
        $src = Join-Path ([IO.Path]::GetTempPath()) "hsi-firmware-bundle.zip"
        $fw = (& $py (Join-Path $dir "tools\make_firmware_bundle.py") $src | Select-Object -Last 1) | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $fw.version) { throw "the firmware bundle was not made (see above)" }
        $ver = $fw.version; $ext = "zip"
    }
} else {
    if ($Platform -eq "firmware") { throw "$App has no firmware bundle: windows or android" }
    $ver = (Get-Content (Join-Path $dir "src-tauri\tauri.conf.json") -Raw | ConvertFrom-Json).version
    if ($Platform -eq "windows") {
        $src = Join-Path $target "release\bundle\nsis\${name}_${ver}_x64-setup.exe"; $key = "windows-x86_64"; $ext = "exe"
    } else {
        $src = Join-Path $dir "dist\$apk-$ver-arm64-release.apk"; $key = "android-aarch64"; $ext = "apk"
    }
}
if (-not (Test-Path $src)) { throw "missing $src - build version $ver first" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "the GitHub CLI is not installed: winget install GitHub.cli, then gh auth login" }
$branch = (& git -C $PSScriptRoot rev-parse --abbrev-ref HEAD)
if ($branch -ne "main") { throw "run this on main (here: $branch) - the apps read the feed from main" }

# Sign the package itself (Tauri 2 updates from the installer / APK as built; the flasher checks
# the same signature). Always re-sign, so a rebuilt file never goes out with an older signature.
$k = if ($env:HSI_UPDATER_KEY) { $env:HSI_UPDATER_KEY } elseif ($keysDir) { Join-Path $keysDir "hsi-updater.key" } else { Join-Path $dir "keys\hsi-updater.key" }
if (-not (Test-Path $k)) { throw "no update key at $k (set HSI_KEYS_DIR, or unlock the keys first)" }
$pw = if ($env:HSI_UPDATER_KEY_PASSWORD) { $env:HSI_UPDATER_KEY_PASSWORD } else { '""' }
Push-Location $signDir
try {
    & cmd /c "npx --no-install tauri signer sign -f `"$k`" -p $pw `"$src`" >nul"
    if ($LASTEXITCODE -ne 0) { throw "signing $src failed" }
} finally { Pop-Location }
$sig = (Get-Content "$src.sig" -Raw).Trim()

# From here on gh and git report on stderr as a matter of course ("release not found" is the
# normal answer for a new version). Windows PowerShell 5.1 turns that into a terminating error
# under "Stop", so their exit codes are checked instead.
$ErrorActionPreference = "Continue"

$repo = "HSI-Lighting/release"
if ($fw) { $file = "${App}-firmware_${ver}.zip"; $tag = "$App-firmware-$ver"; $title = "$name firmware library $ver" }
else     { $file = "${App}_${ver}_${Platform}.$ext"; $tag = "$App-v$ver"; $title = "$name $ver" }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $tmp | Out-Null
try {
    Copy-Item $src (Join-Path $tmp $file)
    & gh release view $tag --repo $repo *> $null
    if ($LASTEXITCODE -eq 0) {
        & gh release upload $tag (Join-Path $tmp $file) --repo $repo --clobber
    } else {
        $n = if ($Notes) { $Notes } else { $title }
        & gh release create $tag (Join-Path $tmp $file) --repo $repo --title $title --notes $n
    }
    if ($LASTEXITCODE -ne 0) { throw "gh could not upload $file" }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if ($fw) { Remove-Item $src, "$src.sig" -Force -ErrorAction SilentlyContinue }
}

# The feed. App: a new version starts with just this platform; the same version keeps the others.
# The flasher's "firmware" entry and its app entry are kept apart: publishing one keeps the other.
Set-Location $PSScriptRoot
& git pull -q --ff-only
if ($LASTEXITCODE -ne 0) { throw "git pull failed - the release has the file but the feed is not updated yet" }
New-Item -ItemType Directory -Force $App | Out-Null
$feed = Join-Path $App "latest.json"
$cur = if (Test-Path $feed) { Get-Content $feed -Raw | ConvertFrom-Json } else { $null }
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$url = "https://github.com/$repo/releases/download/$tag/$file"
$out = [ordered]@{}
if ($fw) {
    if ($cur) { foreach ($p in $cur.PSObject.Properties) { if ($p.Name -ne "firmware") { $out[$p.Name] = $p.Value } } }
    $n = if ($Notes) { $Notes } else { "Firmware library $ver ($($fw.entries) firmware)" }
    $out["firmware"] = [ordered]@{ version = $ver; notes = $n; pub_date = $now; entries = $fw.entries; size = $fw.size; url = $url; signature = $sig }
} else {
    $plats = [ordered]@{}
    if ($cur -and $cur.version -eq $ver) { foreach ($p in $cur.platforms.PSObject.Properties) { $plats[$p.Name] = $p.Value } }
    $plats[$key] = [ordered]@{ signature = $sig; url = $url }
    $n = if ($Notes) { $Notes } elseif ($cur -and $cur.version -eq $ver -and $cur.notes) { $cur.notes } else { "$name $ver" }
    $out["version"] = $ver; $out["notes"] = $n; $out["pub_date"] = $now; $out["platforms"] = $plats
    if ($cur -and $cur.firmware) { $out["firmware"] = $cur.firmware }
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot $feed), ($out | ConvertTo-Json -Depth 6) + "`n")

& git add $feed
& git commit -qm "$title ($Platform)"
& git push -q
if ($LASTEXITCODE -ne 0) { throw "git push failed - the release has the file but the feed is not updated yet" }
"published $tag ($Platform)"
