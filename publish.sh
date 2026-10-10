#!/usr/bin/env bash
# Publish a built, signed build: GitHub release asset + <app>/latest.json (the feed the apps read).
#   ./publish.sh site-coordinator|installer|installer-assist|ble-devices linux|windows|macos|android ["release notes"]
# Linux = the AppImage, Windows = the NSIS setup .exe, macOS = the .app.tar.gz (built with
# bundle.createUpdaterArtifacts), Android = the release APK (installer-assist / ble-devices only).
# Publish every platform of one version: each call adds its platform to the same release and feed.
# Build first with the signing key in the environment (see README); the key never leaves this PC.
# installer-assist / ble-devices (both in the Installer-assist repo, $HSI_INSTALLER_ASSIST): the
# package is signed here with the update key in that app's keys/ (or $HSI_UPDATER_KEY).
# On Windows, publish.ps1 does the same.
set -euo pipefail
app=${1:?site-coordinator|installer|installer-assist|ble-devices}; plat=${2:?linux|windows|macos|android}; notes=${3:-}
W=~/workspace/Rust
IA=${HSI_INSTALLER_ASSIST:-$W/Installer-assist}
dir=
case $app in
  site-coordinator) conf=$W/HSI_Site_Coordinator/apps/desktop/src-tauri/tauri.conf.json; root=$W/HSI_Site_Coordinator/target; name="HSI Site Coordinator" ;;
  installer)        conf=$W/HSI_Admin_Panel_NodeFlow/tauri-app/tauri.conf.json;          root=$W/HSI_Admin_Panel_NodeFlow/tauri-app/target; name="HSI Installer" ;;
  installer-assist) dir="$IA/HSI Installer assist"; conf="$dir/src-tauri/tauri.conf.json"; root="$dir/target";           name="HSI Installer Assist"; apk=HSI-Installer-Assist ;;
  ble-devices)      dir="$IA/BLE devices assist";  conf="$dir/src-tauri/tauri.conf.json"; root="$dir/src-tauri/target"; name="HSI BLE Devices";      apk=HSI-BLE-Devices ;;
  *) echo "unknown app $app" >&2; exit 1 ;;
esac
ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$conf")
case $plat in
  linux)   src="$root/release/bundle/appimage/${name}_${ver}_amd64.AppImage"; key=linux-x86_64;   ext=AppImage ;;
  windows) src="$root/x86_64-pc-windows-msvc/release/bundle/nsis/${name}_${ver}_x64-setup.exe"; key=windows-x86_64; ext=exe
           [ -f "$src" ] || src="$root/release/bundle/nsis/${name}_${ver}_x64-setup.exe" ;;   # built on Windows itself
  macos)   src="$root/release/bundle/macos/${name}.app.tar.gz"; ext=app.tar.gz
           case $(uname -m) in arm64|aarch64) key=darwin-aarch64 ;; *) key=darwin-x86_64 ;; esac ;;
  android) [ -n "$dir" ] || { echo "$app has no Android build" >&2; exit 1; }
           src="$dir/dist/${apk}-${ver}-arm64-release.apk"; key=android-aarch64; ext=apk ;;
  *) echo "unknown platform $plat" >&2; exit 1 ;;
esac
# Our two apps: sign the package itself (Tauri 2 updates from the installer / AppImage / APK as
# built). Always re-sign, so a rebuilt file never goes out with an older build's signature.
# macOS's .app.tar.gz is signed by the build (createUpdaterArtifacts), not here.
if [ -n "$dir" ] && [ "$plat" != macos ] && [ -f "$src" ]; then
  k=${HSI_UPDATER_KEY:-$dir/keys/hsi-updater.key}
  [ -f "$k" ] || { echo "no update key at $k (run unlock-keys first)" >&2; exit 1; }
  (cd "$dir" && npx --no-install tauri signer sign -f "$k" -p "${HSI_UPDATER_KEY_PASSWORD:-}" "$src" >/dev/null)
fi
[ -f "$src" ] && [ -f "$src.sig" ] || { echo "missing $src (+ .sig): build version $ver first" >&2; exit 1; }
file="${app}_${ver}_${plat}.${ext}"; tag="$app-v$ver"
cd "$(dirname "$0")"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$src" "$tmp/$file"
if gh release view "$tag" --repo HSI-Lighting/release >/dev/null 2>&1; then
  gh release upload "$tag" "$tmp/$file" --repo HSI-Lighting/release --clobber
else
  gh release create "$tag" "$tmp/$file" --repo HSI-Lighting/release --title "$name $ver" --notes "${notes:-$name $ver}"
fi
mkdir -p "$app"
python3 - "$app" "$ver" "$notes" "$tag" "$file" "$src.sig" "$key" <<'PY'
import json,sys,os,datetime
app,ver,notes,tag,file,sig,key=sys.argv[1:]
f=f"{app}/latest.json"
cur=json.load(open(f)) if os.path.exists(f) else {}
plats=cur.get("platforms",{}) if cur.get("version")==ver else {}   # a new version starts with just this platform
plats[key]={"signature":open(sig).read().strip(),"url":f"https://github.com/HSI-Lighting/release/releases/download/{tag}/{file}"}
json.dump({"version":ver,"notes":notes or cur.get("notes") or ver,"pub_date":datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),"platforms":plats},open(f,"w"),indent=2)
PY
git add "$app/latest.json" && git commit -qm "$name $ver ($plat)" && git push -q
echo "published $tag ($plat)"
