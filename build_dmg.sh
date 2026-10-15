#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/DynamicNotch.xcodeproj}"
SCHEME="${SCHEME:-DynamicNotch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
CLONED_SOURCE_PACKAGES_PATH="${CLONED_SOURCE_PACKAGES_PATH:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

APP_NAME="${APP_NAME:-Notchwatch.app}"
# Identidad de firma: "-" (ad hoc) o "Notchwatch Self-Signed"; SIGN_KEYCHAIN es opcional.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
VOLUME_NAME="${VOLUME_NAME:-Notchwatch}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/dmg}"
DMG_NAME="${DMG_NAME:-Notchwatch.dmg}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dynamicnotch-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "Resolving Swift packages..."
if [[ -n "$CLONED_SOURCE_PACKAGES_PATH" ]]; then
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH"
else
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME"
fi

# Sin certificado el binario se firma ad hoc; el hardened runtime impediría cargar los frameworks.
EXTRA_BUILD_SETTINGS=""
if [[ "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
  EXTRA_BUILD_SETTINGS="ENABLE_HARDENED_RUNTIME=NO"
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
if [[ -n "$CLONED_SOURCE_PACKAGES_PATH" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    $EXTRA_BUILD_SETTINGS \
    build
else
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    $EXTRA_BUILD_SETTINGS \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build finished, but app was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Staging DMG contents..."
# Sin firma de desarrollador, Apple Silicon no ejecuta el binario: se firma ad hoc
# o, con SIGN_IDENTITY, con el certificado propio («Notchwatch Self-Signed»).
if [[ "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
  echo "Signing $APP_NAME (identity: $SIGN_IDENTITY)..."
  SIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
  fi
  codesign "${SIGN_ARGS[@]}" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created: $DMG_PATH"
