# Publish a built build from Windows: GitHub release asset + <app>/latest.json (the feed the apps
# read). The same as publish.sh, for HSI Installer Assist and HSI BLE Devices built on this PC.
#
#   powershell -ExecutionPolicy Bypass -File publish.ps1 installer-assist|ble-devices windows|android ["release notes"]
#
# Windows = the NSIS setup .exe (npm run dist:win), Android = the release APK (npm run android:apk).
# Publish every platform of one version: each call adds its platform to the same release and feed.
# The package is signed here with the update key in that app's keys\ (or $env:HSI_UPDATER_KEY);
# the key never leaves this PC. Needs the GitHub CLI, signed in: winget install GitHub.cli; gh auth login
#
# Keep this file pure ASCII (Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM).

param(
    [Parameter(Mandatory = $true)][ValidateSet("installer-assist", "ble-devices")][string]$App,
    [Parameter(Mandatory = $true)][ValidateSet("windows", "android")][string]$Platform,
    [string]$Notes = ""
)
$ErrorActionPreference = "Stop"

$ia = if ($env:HSI_INSTALLER_ASSIST) { $env:HSI_INSTALLER_ASSIST } else { "E:\Installer-assist" }
switch ($App) {
    "installer-assist" { $dir = Join-Path $ia "HSI Installer assist"; $target = Join-Path $dir "target";           $name = "HSI Installer Assist"; $apk = "HSI-Installer-Assist" }
    "ble-devices"      { $dir = Join-Path $ia "BLE devices assist";  $target = Join-Path $dir "src-tauri\target"; $name = "HSI BLE Devices";      $apk = "HSI-BLE-Devices" }
}
$ver = (Get-Content (Join-Path $dir "src-tauri\tauri.conf.json") -Raw | ConvertFrom-Json).version
if ($Platform -eq "windows") {
    $src = Join-Path $target "release\bundle\nsis\${name}_${ver}_x64-setup.exe"; $key = "windows-x86_64"; $ext = "exe"
} else {
    $src = Join-Path $dir "dist\$apk-$ver-arm64-release.apk"; $key = "android-aarch64"; $ext = "apk"
}
if (-not (Test-Path $src)) { throw "missing $src - build version $ver first" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "the GitHub CLI is not installed: winget install GitHub.cli, then gh auth login" }

# Sign the package itself (Tauri 2 updates from the installer / APK as built). Always re-sign, so a
# rebuilt file never goes out with an older build's signature.
$k = if ($env:HSI_UPDATER_KEY) { $env:HSI_UPDATER_KEY } else { Join-Path $dir "keys\hsi-updater.key" }
if (-not (Test-Path $k)) { throw "no update key at $k (run platforms\windows\unlock-keys.ps1 first)" }
$pw = if ($env:HSI_UPDATER_KEY_PASSWORD) { $env:HSI_UPDATER_KEY_PASSWORD } else { '""' }
Push-Location $dir
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
$file = "${App}_${ver}_${Platform}.$ext"; $tag = "$App-v$ver"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $tmp | Out-Null
try {
    Copy-Item $src (Join-Path $tmp $file)
    & gh release view $tag --repo $repo *> $null
    if ($LASTEXITCODE -eq 0) {
        & gh release upload $tag (Join-Path $tmp $file) --repo $repo --clobber
    } else {
        $n = if ($Notes) { $Notes } else { "$name $ver" }
        & gh release create $tag (Join-Path $tmp $file) --repo $repo --title "$name $ver" --notes $n
    }
    if ($LASTEXITCODE -ne 0) { throw "gh could not upload $file" }
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# The feed: a new version starts with just this platform; the same version keeps the others.
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force $App | Out-Null
$feed = Join-Path $App "latest.json"
$cur = if (Test-Path $feed) { Get-Content $feed -Raw | ConvertFrom-Json } else { $null }
$plats = [ordered]@{}
if ($cur -and $cur.version -eq $ver) { foreach ($p in $cur.platforms.PSObject.Properties) { $plats[$p.Name] = $p.Value } }
$plats[$key] = [ordered]@{ signature = $sig; url = "https://github.com/$repo/releases/download/$tag/$file" }
$n = if ($Notes) { $Notes } elseif ($cur -and $cur.notes) { $cur.notes } else { $ver }
$json = [ordered]@{ version = $ver; notes = $n; pub_date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"); platforms = $plats } | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $PSScriptRoot $feed), $json + "`n")

& git add $feed
& git commit -qm "$name $ver ($Platform)"
& git push -q
if ($LASTEXITCODE -ne 0) { throw "git push failed - the release has the file but the feed is not updated yet" }
"published $tag ($Platform)"
