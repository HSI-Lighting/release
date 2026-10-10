#!/usr/bin/env bash
# Publish a built, signed build: GitHub release asset + <app>/latest.json (the feed the apps read).
#   ./publish.sh site-coordinator|installer linux|windows ["release notes"]
# Linux = the AppImage, Windows = the NSIS setup .exe. Publish both platforms of one version:
# the second call adds its platform to the same release and feed. Build first with the signing key
# in the environment (see README); the key never leaves this PC.
set -euo pipefail
app=${1:?site-coordinator|installer}; plat=${2:?linux|windows}; notes=${3:-}
W=~/workspace/Rust
case $app in
  site-coordinator) conf=$W/HSI_Site_Coordinator/apps/desktop/src-tauri/tauri.conf.json; root=$W/HSI_Site_Coordinator/target; name="HSI Site Coordinator" ;;
  installer)        conf=$W/HSI_Admin_Panel_NodeFlow/tauri-app/tauri.conf.json;          root=$W/HSI_Admin_Panel_NodeFlow/tauri-app/target; name="HSI Installer" ;;
  *) echo "unknown app $app" >&2; exit 1 ;;
esac
ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$conf")
case $plat in
  linux)   src="$root/release/bundle/appimage/${name}_${ver}_amd64.AppImage"; key=linux-x86_64;   ext=AppImage ;;
  windows) src="$root/x86_64-pc-windows-msvc/release/bundle/nsis/${name}_${ver}_x64-setup.exe"; key=windows-x86_64; ext=exe ;;
  *) echo "unknown platform $plat" >&2; exit 1 ;;
esac
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
