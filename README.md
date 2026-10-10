# HSI releases

Signed builds of **HSI Site Coordinator** and **HSI Installer** (Linux AppImage), and of
**HSI Installer Assist** and **HSI BLE Devices** (Windows, macOS, Linux, Android). Each app reads
its `<app>/latest.json` from this repo (`site-coordinator`, `installer`, `installer-assist`,
`ble-devices`) and offers an update when the version there is newer; every download is checked
against the signing key built into the app. HSI Installer Assist and HSI BLE Devices share one
update key of their own (`keys/hsi-updater.key` in the Installer-assist repo, gpg-locked there).

Download: see [Releases](../../releases). Run an AppImage with `chmod +x file.AppImage && ./file.AppImage`
(Ubuntu 22.04/24.04 also needs `sudo apt install libfuse2`). The app lists itself in the app menu on first run.

Windows: run the `*_x64-setup.exe` from the release. Windows shows a SmartScreen warning ("Run anyway")
until the build is signed with a code-signing certificate.

Android (HSI Installer Assist, HSI BLE Devices): install the `.apk` from the release, or let the app
update itself (Settings / Updates -> Check for updates; Android asks to allow "Install unknown apps"
once). iOS cannot update from here: Apple allows only the App Store or TestFlight.

Maintainers: build with the signing key in the environment
(`TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/hsi-updater.key)"`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD=…`), then
`./publish.sh site-coordinator|installer linux|windows ["notes"]`. Run it once per platform of the same version.

HSI Installer Assist / HSI BLE Devices: build as usual (the Installer-assist repo's README), then
`./publish.sh installer-assist|ble-devices linux|windows|macos|android ["notes"]` (Linux/macOS, the repo at
`$HSI_INSTALLER_ASSIST`, default `~/workspace/Rust/Installer-assist`) or, on Windows,
`powershell -ExecutionPolicy Bypass -File publish.ps1 installer-assist|ble-devices windows|android ["notes"]`
(the repo at `$env:HSI_INSTALLER_ASSIST`, default `E:\Installer-assist`; needs `gh auth login`). Both sign the
package with the app's `keys/hsi-updater.key` (unlock-keys first). macOS: build with
`--config '{"bundle":{"createUpdaterArtifacts":true}}'` and the key in `TAURI_SIGNING_PRIVATE_KEY`, which
makes the signed `.app.tar.gz`. Raise the version in `src-tauri/tauri.conf.json` first: an app only offers a
newer version, and Android only installs a higher one.
