#!/usr/bin/env bash
# Publish a built, signed build: GitHub release asset + <app>/latest.json (the feed the apps read).
#   ./publish.sh site-coordinator|installer|installer-assist|ble-devices linux|windows|macos|android ["release notes"]
# Linux = the AppImage, Windows = the NSIS setup .exe, macOS = the .app.tar.gz (built with
# bundle.createUpdaterArtifacts), Android = the release APK (installer-assist / ble-devices only).
# Publish every platform of one version: each call adds its platform to the same release and feed.
# Build first with the signing key in the environment (see README); the key never leaves this PC.
# installer-assist / ble-devices (both in the Installer-assist repo, $HSI_INSTALLER_ASSIST): the
# package is signed here with hsi-updater.key ($HSI_UPDATER_KEY, $HSI_KEYS_DIR, or the app's keys/).
#   ./publish.sh mqtt-pro windows|linux|android VERSION FILE ["notes"]
# MQTT Pro (Windows/Linux/Android, E:\KEYS\MQTT Pro\mqtt-pro-updater.key, its own key): FILE is a bare .exe / Linux
# binary / .apk already signed with its tools/mqtt-sign (`mqtt-sign FILE VERSION PLATFORM`, writes FILE.sig);
# see "Publishing MQTT Pro" in the README. Run on Windows with Git Bash (publish.ps1 does not cover it).
#   ./publish.sh firmware-flasher windows|firmware ["notes"]
# HSI Firmware Flasher ($HSI_FIRMWARE_FLASHER): windows = dist/HSI_90111_Programmer.exe (built on
# Windows by build.bat; version in flasher/__init__.py), firmware = its COMMITTED firmware library,
# packed here by tools/make_firmware_bundle.py. Two entries of one feed: publishing one keeps the other.
# On Windows, publish.ps1 does the same.
set -euo pipefail
app=${1:?site-coordinator|installer|installer-assist|ble-devices|firmware-flasher|mqtt-pro}; plat=${2:?linux|windows|macos|android|firmware}; notes=${3:-}
if [ "$app" = mqtt-pro ]; then ver=${3:?version}; src=${4:?signed file}; notes=${5:-}; fi
W=~/workspace/Rust
IA=${HSI_INSTALLER_ASSIST:-$W/Installer-assist}
FL=${HSI_FIRMWARE_FLASHER:-$W/HSI-Firmware-Flasher}
dir=; signdir=; fwjson=
case $app in
  site-coordinator) conf=$W/HSI_Site_Coordinator/apps/desktop/src-tauri/tauri.conf.json; root=$W/HSI_Site_Coordinator/target; name="HSI Site Coordinator" ;;
  installer)        conf=$W/HSI_Admin_Panel_NodeFlow/tauri-app/tauri.conf.json;          root=$W/HSI_Admin_Panel_NodeFlow/tauri-app/target; name="HSI Installer" ;;
  installer-assist) dir="$IA/HSI Installer assist"; conf="$dir/src-tauri/tauri.conf.json"; root="$dir/target";           name="HSI Device Configurator"; apk=HSI-Device-Configurator ;;
  ble-devices)      dir="$IA/BLE devices assist";  conf="$dir/src-tauri/tauri.conf.json"; root="$dir/src-tauri/target"; name="HSI BLE Device Config";      apk=HSI-BLE-Device-Config ;;
  mqtt-pro)         name="MQTT Pro" ;;
  firmware-flasher) dir="$FL"; name="HSI Firmware Flasher"; signdir="$IA/HSI Installer assist" ;;   # signdir: has the Tauri CLI
  *) echo "unknown app $app" >&2; exit 1 ;;
esac
signdir=${signdir:-$dir}
# HSI Device Configurator (was HSI Installer Assist) is built for Windows + Android, HSI BLE Device Config (was HSI BLE Devices) for Android only.
case "$app/$plat" in
  installer-assist/windows|installer-assist/android|ble-devices/android) ;;
  installer-assist/*|ble-devices/*) echo "$app is not published for $plat (installer-assist: windows|android, ble-devices: android)" >&2; exit 1 ;;
esac
if [ "$app" = firmware-flasher ]; then
  case $plat in
    windows)  ver=$(python3 -c 'import re,sys;print(re.search(r"__version__\s*=\s*\"([^\"]+)\"",open(sys.argv[1]).read()).group(1))' "$FL/flasher/__init__.py")
              src="$FL/dist/HSI_90111_Programmer.exe"; key=windows-x86_64; ext=exe ;;
    firmware) src=$(mktemp -d)/firmware-bundle.zip
              fwjson=$(python3 "$FL/tools/make_firmware_bundle.py" "$src" | tail -1)
              ver=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["version"])' "$fwjson"); key=; ext=zip ;;
    *) echo "the flasher publishes windows or firmware" >&2; exit 1 ;;
  esac
elif [ "$app" = mqtt-pro ]; then
  case $plat in
    windows) key=windows-x86_64; ext=exe ;;
    linux)   key=linux-x86_64;   ext=linux ;;
    android) key=android-aarch64; ext=apk ;;
    *) echo "mqtt-pro publishes windows, linux or android" >&2; exit 1 ;;
  esac
else
[ "$plat" != firmware ] || { echo "$app has no firmware bundle" >&2; exit 1; }
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
fi
# Our apps: sign the package itself (Tauri 2 updates from the installer / AppImage / APK as built;
# the flasher checks the same signature). Always re-sign, so a rebuilt file never goes out with an
# older build's signature. macOS's .app.tar.gz is signed by the build (createUpdaterArtifacts).
if [ -n "$dir" ] && [ "$plat" != macos ] && [ -f "$src" ]; then
  k=${HSI_UPDATER_KEY:-${HSI_KEYS_DIR:+$HSI_KEYS_DIR/hsi-updater.key}}; k=${k:-$dir/keys/hsi-updater.key}
  [ -f "$k" ] || { echo "no update key at $k (set HSI_KEYS_DIR or unlock the keys first)" >&2; exit 1; }
  (cd "$signdir" && npx --no-install tauri signer sign -f "$k" -p "${HSI_UPDATER_KEY_PASSWORD:-}" "$src" >/dev/null)
fi
[ -f "$src" ] && [ -f "$src.sig" ] || { echo "missing $src (+ .sig): build version $ver first" >&2; exit 1; }
if [ "$app" = mqtt-pro ]; then
  # the signature must be made for exactly this version + platform (mqtt-sign <file> <version> <platform-key>)
  # and must be newer than the file, so a stale .sig from a rebuilt file is caught here, not on every client
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.0.1" >&2; exit 1; }
  [ "$src.sig" -nt "$src" ] || { echo "$src.sig is older than $src: sign it again" >&2; exit 1; }
  python3 - "$src.sig" "mqtt-pro $ver $key" <<'PY' || { echo "$src.sig was not signed for mqtt-pro $ver $key: run mqtt-sign <file> $ver $key" >&2; exit 1; }
import base64,sys
text=base64.b64decode(open(sys.argv[1]).read().strip()).decode()
lines=[l for l in text.splitlines() if l.startswith("trusted comment: ")]
sys.exit(0 if lines and lines[0][len("trusted comment: "):]==sys.argv[2] else 1)
PY
fi
if [ -n "$fwjson" ]; then file="${app}-firmware_${ver}.zip"; tag="$app-firmware-$ver"; title="$name firmware library $ver"
else file="${apk:-$app}_${ver}_${plat}.${ext}"; tag="$app-v$ver"; title="$name $ver"; fi   # download named after the app; tag + feed keep the key
[ "$app" = mqtt-pro ] && [ "$plat" = linux ] && file="${app}_${ver}_linux"   # MQTT Pro's Linux build is a bare binary
cd "$(dirname "$0")"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "run this on main - the apps read the feed from main" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$src" "$tmp/$file"
if gh release view "$tag" --repo HSI-Lighting/release >/dev/null 2>&1; then
  gh release upload "$tag" "$tmp/$file" --repo HSI-Lighting/release --clobber
else
  gh release create "$tag" "$tmp/$file" --repo HSI-Lighting/release --title "$title" --notes "${notes:-$title}"
fi
git pull -q --ff-only
mkdir -p "$app"
python3 - "$app" "$ver" "$notes" "$tag" "$file" "$src.sig" "$key" "$fwjson" <<'PY'
import json,sys,os,datetime
app,ver,notes,tag,file,sig,key,fwjson=sys.argv[1:]
f=f"{app}/latest.json"
cur=json.load(open(f)) if os.path.exists(f) else {}
now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
url=f"https://github.com/HSI-Lighting/release/releases/download/{tag}/{file}"
if fwjson:   # the flasher's firmware library: its own entry; the app entry is kept
    b=json.loads(fwjson)
    out={k:v for k,v in cur.items() if k!="firmware"}
    out["firmware"]={"version":ver,"notes":notes or f"Firmware library {ver} ({b['entries']} firmware)","pub_date":now,
                     "entries":b["entries"],"size":b.get("size",0),"url":url,"signature":open(sig).read().strip()}
else:
    plats=cur.get("platforms",{}) if cur.get("version")==ver else {}   # a new version starts with just this platform
    plats[key]={"signature":open(sig).read().strip(),"url":url}
    out={"version":ver,"notes":notes or cur.get("notes") or ver,"pub_date":now,"platforms":plats}
    if "firmware" in cur: out["firmware"]=cur["firmware"]
json.dump(out,open(f,"w"),indent=2)
PY
git add "$app/latest.json" && git commit -qm "$title ($plat)" && git push -q
echo "published $tag ($plat)"
# Firmware libraries: the feed names only the newest, so keep the last three and delete older
# library releases. Only after the feed points at the new one. Nothing else.
if [ -n "$fwjson" ]; then
  gh release list --repo HSI-Lighting/release --limit 200 --json tagName,createdAt     --jq "[.[] | select(.tagName | startswith(\"$app-firmware-\"))] | sort_by(.createdAt) | reverse | .[3:] | .[].tagName" |
  while read -r t; do
    gh release delete "$t" --repo HSI-Lighting/release --yes --cleanup-tag >/dev/null 2>&1       && echo "  removed old library release $t" || echo "  could not remove $t (left in place)"
  done
fi
