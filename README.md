# HSI releases

Signed builds of **HSI Site Coordinator** and **HSI Installer** (Linux AppImage). The apps read
`site-coordinator/latest.json` / `installer/latest.json` from this repo and offer an update when the
version there is newer; every download is checked against the signing key built into the app.

Download: see [Releases](../../releases). Run an AppImage with `chmod +x file.AppImage && ./file.AppImage`
(Ubuntu 22.04/24.04 also needs `sudo apt install libfuse2`). The app lists itself in the app menu on first run.

Windows: run the `*_x64-setup.exe` from the release. Windows shows a SmartScreen warning ("Run anyway")
until the build is signed with a code-signing certificate.

Maintainers: build with the signing key in the environment
(`TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/hsi-updater.key)"`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD=…`), then
`./publish.sh site-coordinator|installer linux|windows ["notes"]`. Run it once per platform of the same version.
