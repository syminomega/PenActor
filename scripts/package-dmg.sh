#!/bin/bash
# Build/package locally. Never installs, launches, notarizes, or uploads the app.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path=""
output_dir="$project_root/build/Release"
usage() {
    echo 'Usage: scripts/package-dmg.sh [--app /path/to/PenActor.app] [--output-dir /path/to/output]'
    echo 'Without --app, builds a universal Release app using the current Xcode signing configuration.'
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app|--output-dir)
            if [[ $# -lt 2 || -z "$2" ]]; then usage >&2; exit 2; fi
            if [[ "$1" == --app ]]; then app_path="$2"; else output_dir="$2"; fi
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
if [[ -z "$app_path" ]]; then
    xcodebuild -project "$project_root/PenActor.xcodeproj" -scheme PenActor \
        -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$project_root/build/Packaging" -jobs 2 \
        ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
    app_path="$project_root/build/Packaging/Build/Products/Release/PenActor.app"
fi
if [[ ! -d "$app_path" || ! -f "$app_path/Contents/Info.plist" ]]; then
    echo 'Expected a compiled PenActor.app bundle.' >&2; exit 1
fi
app_path="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"
plist="$app_path/Contents/Info.plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
if [[ "$bundle_id" != dev.SyminStudio.PenActor || ! "$version" =~ ^[[:alnum:]._-]+$ || "$executable" != PenActor ]]; then
    echo 'Unexpected bundle identifier, executable, or version.' >&2; exit 1
fi
codesign --verify --deep --strict "$app_path"
# A universal artifact must actually contain both executable slices.
verify_universal() {
    local architectures
    architectures=" $(lipo -archs "$1") "
    for required in arm64 x86_64; do
        if [[ "$architectures" != *" $required "* ]]; then
            echo "Missing executable architecture: $required" >&2; return 1
        fi
    done
}
verify_universal "$app_path/Contents/MacOS/$executable"
for language in en zh-Hans; do
    if [[ ! -f "$app_path/Contents/Resources/$language.lproj/Localizable.strings" ]]; then
        echo "Missing compiled localization: $language" >&2; exit 1
    fi
done
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
filename="PenActor-$version-macos-universal.dmg"
if [[ -e "$output_dir/$filename" || -e "$output_dir/$filename.sha256" ]]; then
    echo "Refusing to overwrite an existing release artifact: $output_dir/$filename" >&2
    echo 'Choose a new output directory or archive the previous artifact first.' >&2; exit 1
fi
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/PenActorDMG.XXXXXX")
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        if ! hdiutil detach "$work_dir/mounted" -quiet; then
            echo "Could not detach validation volume; temporary files retained at $work_dir" >&2
            return
        fi
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/staging" "$work_dir/mounted"
# Preserve the signed bundle; do not re-sign or modify its contents during packaging.
ditto "$app_path" "$work_dir/staging/PenActor.app"
ln -s /Applications "$work_dir/staging/Applications"
cp "$project_root/docs/installation.md" "$work_dir/staging/installation.md"
cp "$project_root/docs/installation.zh-CN.md" "$work_dir/staging/installation.zh-CN.md"
codesign --verify --deep --strict "$work_dir/staging/PenActor.app"
hdiutil create -volname "PenActor $version" -srcfolder "$work_dir/staging" \
    -fs HFS+ -format UDZO "$work_dir/$filename"
hdiutil verify "$work_dir/$filename"
hdiutil attach -readonly -nobrowse -mountpoint "$work_dir/mounted" "$work_dir/$filename" >/dev/null
mounted=true
codesign --verify --deep --strict "$work_dir/mounted/PenActor.app"
verify_universal "$work_dir/mounted/PenActor.app/Contents/MacOS/PenActor"
if [[ "$(readlink "$work_dir/mounted/Applications")" != /Applications ]]; then
    echo 'Invalid Applications shortcut in the disk image.' >&2; exit 1
fi
cmp "$project_root/docs/installation.md" "$work_dir/mounted/installation.md"
cmp "$project_root/docs/installation.zh-CN.md" "$work_dir/mounted/installation.zh-CN.md"
hdiutil detach "$work_dir/mounted" -quiet
mounted=false
mv "$work_dir/$filename" "$output_dir/$filename"
(cd "$output_dir" && shasum -a 256 "$filename" > "$filename.sha256")
echo "DMG: $output_dir/$filename"
echo "SHA-256: $output_dir/$filename.sha256"
echo 'The app retains its input signature. This script does not provide Developer ID signing or notarization.'
