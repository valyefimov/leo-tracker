#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_name="LeoTracker"
display_name="Leo Tracker"
bundle_name="$app_name.app"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$bundle_name"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

cd "$repo_dir"

swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
executable="$bin_dir/$app_name"
resource_bundle="$bin_dir/${app_name}_${app_name}.bundle"

if [[ ! -x "$executable" ]]; then
  echo "Missing executable: $executable" >&2
  exit 1
fi

if [[ ! -d "$resource_bundle" ]]; then
  echo "Missing resource bundle: $resource_bundle" >&2
  exit 1
fi

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$executable" "$macos_dir/$app_name"
cp "$repo_dir/AppBundle/Info.plist" "$contents_dir/Info.plist"

# Keep SwiftPM-processed resources in the standard macOS app resources folder.
cp -R "$resource_bundle" "$resources_dir/${app_name}_${app_name}.bundle"

iconset="$repo_dir/Sources/LeoTracker/Resources/Assets.xcassets/AppIcon.appiconset"
if command -v iconutil >/dev/null 2>&1 && [[ -d "$iconset" ]]; then
  tmp_iconset="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$tmp_iconset"
  cp "$iconset"/icon_*.png "$tmp_iconset"/
  iconutil -c icns "$tmp_iconset" -o "$resources_dir/AppIcon.icns"
fi

chmod +x "$macos_dir/$app_name"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$app_dir"
fi

echo "Built $app_dir"
echo "Open it with: open \"$app_dir\""
