# HSI releases

Signed builds of **HSI Site Coordinator** and **HSI Installer** (Linux AppImage), of
**HSI Installer Assist** (Windows, Android) and **HSI BLE Devices** (Android only), of **DALI Admin BLE** (Android), and of the
**HSI Firmware Flasher** (Windows) with its firmware library, and of **MQTT Pro** (Windows, Linux, Android). Each app reads its `<app>/latest.json`
from this repo (`site-coordinator`, `installer`, `installer-assist`, `ble-devices`, `dali-admin`, `firmware-flasher`, `mqtt-pro`)
and offers an update when the version there is newer; every download is checked against the signing
key built into the app. HSI Installer Assist, HSI BLE Devices and the HSI Firmware Flasher share one
update key of their own (`hsi-updater.key`, kept on the build PC in `HSI_KEYS_DIR`, E:\KEYS\_master). DALI Admin BLE uses the same key.

Download: see [Releases](../../releases). Run an AppImage with `chmod +x file.AppImage && ./file.AppImage`
(Ubuntu 22.04/24.04 also needs `sudo apt install libfuse2`). The app lists itself in the app menu on first run.

Windows: run the `*_x64-setup.exe` from the release. Windows shows a SmartScreen warning ("Run anyway")
until the build is signed with a code-signing certificate.

Android (HSI Installer Assist, HSI BLE Devices): install the `.apk` from the release, or let the app
update itself (Settings / Updates -> Check for updates; Android asks to allow "Install unknown apps"
once). iOS cannot update from here: Apple allows only the App Store or TestFlight.

HSI Firmware Flasher: `firmware-flasher/latest.json` has two parts that are published separately - the
app (`version` / `platforms`, the single `.exe`) and the firmware library (`firmware`: a zip of the
flasher's `firmware/` folder, versioned by its last commit). The flasher offers either one; a library
update keeps the firmware entries a technician added by hand. HSI Installer Assist reads the same library
for its Firmware tab's "Use latest build" (OTA) wherever the workshop PC's HSI BUILDS folder is not there.
Publishing a library keeps the newest three library releases and deletes older ones (nothing else).

Maintainers: build with the signing key in the environment
(`TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/hsi-updater.key)"`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD=…`), then
`./publish.sh site-coordinator|installer linux|windows ["notes"]`. Run it once per platform of the same version.

HSI Installer Assist (Windows + Android) / HSI BLE Devices (Android only): build as usual (the
Installer-assist repo's README), then on Windows
`powershell -ExecutionPolicy Bypass -File publish.ps1 installer-assist windows|android ["notes"]` or
`publish.ps1 ble-devices android ["notes"]` (the repo at `$env:HSI_INSTALLER_ASSIST`, default
`E:\Installer-assist`; needs `gh auth login`), or the same arguments to `./publish.sh` (the repo at
`$HSI_INSTALLER_ASSIST`, default `~/workspace/Rust/Installer-assist`). Both scripts refuse other platforms
for these two apps. Raise the version in `src-tauri/tauri.conf.json` first: an app only offers a newer
version, and Android only installs a higher one.

HSI Firmware Flasher: `publish.ps1 firmware-flasher windows` (after `build.bat`; version in
`flasher/__init__.py`) and `publish.ps1 firmware-flasher firmware` (after the firmware is committed; the
script packs it with `tools/make_firmware_bundle.py` and refuses uncommitted firmware); `publish.sh` takes the
same, the repo at `$HSI_FIRMWARE_FLASHER` (default `E:\HSI-Firmware-Flasher` / `~/workspace/Rust/HSI-Firmware-Flasher`).

DALI Admin BLE (Android only): the repo is `$env:HSI_DALI_ADMIN` (default
`E:\Dali Admin BLE\Dali_Admin_BLE_Android_V3_16_03_2026`); the version is `versionName` in `app/build.gradle.kts`
(`5.2` becomes `5.2.0`). Build and sign the release APK with the Play upload key there, then
`powershell -ExecutionPolicy Bypass -File publish.ps1 dali-admin android "notes" -Apk <signed.apk>` (or
`./publish.sh dali-admin android "notes" <signed.apk>`). The script only adds the update signature, writes
`dali-admin/latest.json`, creates release `dali-admin-v<ver>` with `DALI-Admin-BLE_<ver>_android.apk`, and
refuses a version whose release already exists.

All the apps above except MQTT Pro are signed by the scripts with `hsi-updater.key` from `$HSI_UPDATER_KEY`, else
`$HSI_KEYS_DIR/hsi-updater.key`, else the app's `keys/`. Run the scripts on `main`: that is where the apps
read the feed.

## How updates work

Every app here updates itself the same way. Nothing runs on a server: the apps read a small JSON file from this repo
and download the new build from a GitHub release.

1. **The feed.** Each app has `<app>/latest.json` in this repo, read from
   `https://raw.githubusercontent.com/HSI-Lighting/release/main/<app>/latest.json`
   (`site-coordinator`, `installer`, `dali-admin`, `mqtt-pro`). It holds the newest version, its notes, and one entry per platform:

   ```json
   { "version": "1.0.1", "notes": "What changed", "pub_date": "2026-10-10T12:00:00Z",
     "platforms": {
       "windows-x86_64": { "signature": "<base64 of the .sig file>",
                           "url": "https://github.com/HSI-Lighting/release/releases/download/mqtt-pro-v1.0.1/mqtt-pro_1.0.1_windows.exe" } } }
   ```

   Platform keys: `windows-x86_64`, `linux-x86_64`, `android-aarch64`.
2. **The release.** The file itself is an asset of the release tagged `<app>-vX.Y.Z` (for example `mqtt-pro-v1.0.1`),
   named `<app>_X.Y.Z_<platform>.<ext>`.
3. **The check.** The app looks at the feed about 8 seconds after it starts and then every 6 hours. An update is
   offered only if the feed's version is **greater** than the running one (three numbers, `1.0.9 < 1.0.10`), so a
   wrong or old feed can never downgrade anyone (for MQTT Pro even a genuine old signature is refused, see above). Users can also press *Check for updates* in the app.
4. **The check of the download.** The `signature` is a minisign signature of the exact bytes of the file, made with
   the app's private key; the matching public key is built into the app. For MQTT Pro the signed comment also names
   the version and platform (`mqtt-pro 1.0.1 windows-x86_64`) and the app compares it with the feed entry. A download that does not match is deleted
   and never installed. Downloads must be HTTPS (redirects included) and are capped at 500 MB.
5. **The install.** Windows and Linux (Site Coordinator, Installer, MQTT Pro desktop): the app replaces itself and
   restarts (MQTT Pro starts the new copy first and puts the old one back if the new one quits within 3 seconds). MQTT Pro on Windows renames the running exe to `*.old`, puts the new one in place, starts it and deletes
   the `.old` file on the next start; if its folder is not writable (for example Program Files without admin
   rights) it offers *Open download page* instead. Android: the app downloads the APK, verifies it, then opens the
   system installer; the user taps *Install* (Android asks once to allow installs from MQTT Pro).
6. **GitHub caches** `raw.githubusercontent.com` for a few minutes, so a new release can show up in the apps with a short delay.

Each product has its own key. Site Coordinator and Installer use the Tauri key (`~/.tauri/hsi-updater.key`); MQTT Pro
uses its own key kept on the maintainer PC in `E:\KEYS\MQTT Pro` (`mqtt-pro-updater.key` + password, never committed). If a
private key or its password is lost, installed copies of that app can no longer be updated and must be reinstalled by
hand, because they only trust their built-in public key.

## Publishing MQTT Pro

1. Set the version (`1.0.1`) in `Cargo.toml` (`[workspace.package]`) and in `android/app/build.gradle`
   (`versionName "1.0.1"`, and raise `versionCode` by one). All platforms share one version number.
2. Build the three files from the MQTT-MONITOR repo: the Windows exe and Linux binary
   (`cargo build --release -p mqtt-pro-rs`, Linux via WSL), and the Android APK (`gradlew assembleRelease`, signed
   with the app's APK key; Android refuses to update an APK signed with a different key).
3. Sign each file with the update key; this writes `<file>.sig` next to it:

   ```
   cargo run --release -p mqtt-sign -- path/to/MQTT-Pro.exe 1.0.1 windows-x86_64
   ```

   The last two arguments are the version and the platform key (`windows-x86_64`, `linux-x86_64`,
   `android-aarch64`). They are written into the signature, and the apps refuse a file whose signature was made for a
   different version or platform: an old signed file can never be passed off as a new release, and one platform's file
   can never be installed on another. `mqtt-sign` also checks the result against the public key built into the app,
   so signing with the wrong key fails on your PC rather than on every installed copy. `publish.sh` re-checks all this.

   (`mqtt-sign` reads `E:\KEYS\MQTT Pro\mqtt-pro-updater.key` and its password file; override with `MQTT_SIGN_KEY`,
   `MQTT_SIGN_PASSWORD` / `MQTT_SIGN_PASSWORD_FILE`. It prints only `wrote <file>.sig`.)
4. Publish one platform at a time; the second and third call add their platform to the same release and feed:

   ```
   ./publish.sh mqtt-pro windows 1.0.1 path/to/MQTT-Pro.exe "What changed"
   ./publish.sh mqtt-pro linux   1.0.1 path/to/MQTT-Pro-linux
   ./publish.sh mqtt-pro android 1.0.1 path/to/app-release.apk
   ```

   `publish.sh` uploads the file to the `mqtt-pro-v1.0.1` release, merges the platform into `mqtt-pro/latest.json`,
   commits and pushes it. Within a few minutes running copies offer the update.
