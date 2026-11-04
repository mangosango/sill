#!/bin/bash
# Package an already checked viewer bundle; no mounting, signing, notarization or launch.
set -euo pipefail
[ "$#" = 2 ] || exit 2
app="$1"; out="$2"
[ "$(basename "$app")" = 'Sill Viewer.app' ] && [ -f "$app/Contents/Info.plist" ] || exit 1
mkdir -p "$out"
work=$(mktemp -d "$out/artifacts.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/image"
ditto "$app" "$work/image/Sill Viewer.app"
ln -s /Applications "$work/image/Applications"
hdiutil create -ov -fs HFS+ -volname 'Sill Viewer' -format ULFO -srcfolder "$work/image" "$work/Sill-Viewer.dmg"
hdiutil verify "$work/Sill-Viewer.dmg"
ditto -c -k --keepParent "$app" "$work/Sill-Viewer.zip"
mkdir "$work/unpacked"
ditto -x -k "$work/Sill-Viewer.zip" "$work/unpacked"
[ "$(ls -A "$work/unpacked")" = 'Sill Viewer.app' ]
diff -r "$app" "$work/unpacked/Sill Viewer.app"
for file in Sill-Viewer.dmg Sill-Viewer.zip; do
    [ -s "$work/$file" ]
    (cd "$work"; shasum -a 256 "$file" > "$file.sha256"; shasum -a 256 -c "$file.sha256")
done
for file in Sill-Viewer.dmg Sill-Viewer.zip Sill-Viewer.dmg.sha256 Sill-Viewer.zip.sha256; do
    mv "$work/$file" "$out/$file"
done
