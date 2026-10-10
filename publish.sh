#!/usr/bin/env bash
# Publish a built, signed AppImage: GitHub release asset + <app>/latest.json (the feed the apps read).
#   ./publish.sh site-coordinator|installer ["release notes"]
# Build first with TAURI_SIGNING_PRIVATE_KEY_PATH set (~/.tauri/hsi-updater.key); the key never leaves this PC.
set -euo pipefail
app=${1:?site-coordinator|installer}; notes=${2:-}
W=~/workspace/Rust
case $app in
  site-coordinator) conf=$W/HSI_Site_Coordinator/apps/desktop/src-tauri/tauri.conf.json; dir=$W/HSI_Site_Coordinator/target/release/bundle/appimage; name="HSI Site Coordinator" ;;
  installer)        conf=$W/HSI_Admin_Panel_NodeFlow/tauri-app/tauri.conf.json;          dir=$W/HSI_Admin_Panel_NodeFlow/tauri-app/target/release/bundle/appimage; name="HSI Installer" ;;
  *) echo "unknown app $app" >&2; exit 1 ;;
esac
ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$conf")
src="$dir/${name}_${ver}_amd64.AppImage"
[ -f "$src" ] && [ -f "$src.sig" ] || { echo "missing $src (+ .sig): build version $ver first" >&2; exit 1; }
file="${app}_${ver}_amd64.AppImage"; tag="$app-v$ver"
cd "$(dirname "$0")"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$src" "$tmp/$file"
gh release create "$tag" "$tmp/$file" --repo HSI-Lighting/release --title "$name $ver" --notes "${notes:-$name $ver}"
mkdir -p "$app"
python3 - "$app" "$ver" "$notes" "$tag" "$file" "$src.sig" <<'PY'
import json,sys,datetime
app,ver,notes,tag,file,sig=sys.argv[1:]
json.dump({"version":ver,"notes":notes or f"{ver}","pub_date":datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
 "platforms":{"linux-x86_64":{"signature":open(sig).read().strip(),
 "url":f"https://github.com/HSI-Lighting/release/releases/download/{tag}/{file}"}}},open(f"{app}/latest.json","w"),indent=2)
PY
git add "$app/latest.json" && git commit -qm "$name $ver" && git push -q
echo "published $tag"
