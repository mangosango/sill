#!/bin/bash
# Separate universal viewer bundle/ZIP; no install, launch, notarization or publication.
# Default unsigned; --adhoc signs without pairing entitlements (persistent pairing unavailable).
# --developer-id IDENTITY PROFILE requires a viewer-specific macOS Developer ID profile.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=unsigned; identity=''; profile=''
case "${1:-}" in
    '') [ "$#" = 0 ] || exit 2 ;;
    --adhoc) [ "$#" = 1 ] || exit 2; mode=adhoc ;;
    --developer-id)
        [ "$#" = 3 ] || exit 2
        mode=developer; identity="$2"; profile="$3"
        case "$identity" in 'Developer ID Application: '*) ;; *) echo 'error: use a full Developer ID Application identity name' >&2; exit 2;; esac
        [ -f "$profile" ] || { echo 'error: viewer profile missing' >&2; exit 2; } ;;
    *) echo "usage: $0 [--adhoc | --developer-id IDENTITY PROFILE]" >&2; exit 2 ;;
esac
free_kb=$(df -k . | awk 'END {print $4}')
[ "$free_kb" -ge 26214400 ] || { echo 'error: 25 GB free disk required' >&2; exit 1; }
out="$PWD/.build/viewer"
mkdir -p "$out"
work=$(mktemp -d "$out/package.XXXXXX")
trap 'rm -rf "$work"' EXIT
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
build=$(git rev-list --count HEAD)
xcodebuild -project iOSClient/Sill.xcodeproj -scheme 'Sill Viewer' -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$out/DerivedData" -jobs 4 \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" build
app="$work/Sill Viewer.app"
ditto "$out/DerivedData/Build/Products/Release/Sill Viewer.app" "$app"
architectures="$(lipo -archs "$app/Contents/MacOS/Sill Viewer")"
for arch in arm64 x86_64; do
    case " $architectures " in *" $arch "*) ;; *) echo "error: missing $arch slice" >&2; exit 1;; esac
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = me.saffer.sill.viewer ]
if [ "$mode" = developer ]; then
    security cms -D -i "$profile" -o "$work/profile.plist"
    python3 Scripts/viewer-profile.py "$work/profile.plist" Packaging/SillViewer.entitlements
    cat "$profile" > "$app/Contents/embedded.provisionprofile"
    codesign --force --options runtime --timestamp --entitlements Packaging/SillViewer.entitlements --sign "$identity" "$app"
    codesign -d --extract-certificates="$work/signer" "$app"
    python3 Scripts/viewer-profile.py "$work/profile.plist" Packaging/SillViewer.entitlements "$work/signer0"
    codesign -d --entitlements "$work/signed.plist" --xml "$app"
    python3 Scripts/viewer-profile.py "$work/profile.plist" "$work/signed.plist" "$work/signer0"
    codesign --verify --deep --strict "$app"
elif [ "$mode" = adhoc ]; then
    codesign --force --sign - "$app"
    codesign --verify --deep --strict "$app"
fi
zip="$work/Sill-Viewer.zip"
ditto -c -k --keepParent "$app" "$zip"
rm -rf "$out/Sill Viewer.app"
mv "$app" "$out/Sill Viewer.app"
mv "$zip" "$out/Sill-Viewer.zip"
echo "Built $out/Sill Viewer.app and Sill-Viewer.zip ($version, $build; $mode)."
