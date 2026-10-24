#!/bin/bash
# Build only. Does not install certificates, grant permissions, or replace the running app.
set -euo pipefail
if [[ $# -ne 2 || ! "$1" =~ ^[[:xdigit:]]{40}$ || ! "$2" =~ ^[[:alnum:]]{10}$ ]]; then
    echo 'Usage: scripts/build-signed.sh <40-character signing identity SHA-1> <10-character Apple Team ID>' >&2
    echo 'List existing identities with: security find-identity -v -p codesigning' >&2
    exit 2
fi
identity_sha="$1"
team_id="$2"
if ! security find-identity -v -p codesigning | /usr/bin/grep -Fqi -- "$identity_sha"; then
    echo 'Requested signing identity is not available in the current keychain. Configure it in Xcode first.' >&2
    exit 1
fi
project_root="$(cd "$(dirname "$0")/.." && pwd)"
xcodebuild -project "$project_root/PenActor.xcodeproj" -scheme PenActor \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$project_root/build/Signed" -jobs 2 \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity_sha" DEVELOPMENT_TEAM="$team_id" build
signed_app="$project_root/build/Signed/Build/Products/Release/PenActor.app"
codesign --verify --deep --strict "$signed_app"
codesign --verify -R "=anchor apple generic and certificate leaf[subject.OU] = \"$team_id\"" "$signed_app"
codesign -d -r- "$signed_app"
echo "Signed build: $signed_app"
echo 'Keep the same signing team and bundle ID for future updates. The first change from ad-hoc signing still requires authorization.'
