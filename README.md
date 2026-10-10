# HSI releases

Signed builds of **HSI Site Coordinator** and **HSI Installer** (Linux AppImage). The apps read
`site-coordinator/latest.json` / `installer/latest.json` from this repo and offer an update when the
version there is newer; every download is checked against the signing key built into the app.

Download: see [Releases](../../releases). Run an AppImage with `chmod +x file.AppImage && ./file.AppImage`
(Ubuntu 22.04/24.04 also needs `sudo apt install libfuse2`). The app lists itself in the app menu on first run.

Maintainers: `./publish.sh site-coordinator|installer` after building with the signing key.
