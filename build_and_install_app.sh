#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/DynamicNotch.xcodeproj}"
SCHEME="${SCHEME:-DynamicNotch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/DynamicNotchDerivedData}"
CLONED_SOURCE_PACKAGES_PATH="${CLONED_SOURCE_PACKAGES_PATH:-}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_NAME="${APP_NAME:-Notchwatch.app}"
# Identidad de firma: "-" (ad hoc) o "Notchwatch Self-Signed"; SIGN_KEYCHAIN es opcional.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
TARGET_PATH="$INSTALL_DIR/$APP_NAME"

echo "Building $APP_NAME ($CONFIGURATION)..."
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

if [[ -n "$CLONED_SOURCE_PACKAGES_PATH" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    build
else
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build finished, but app was not found at: $APP_PATH" >&2
  exit 1
fi

# Sin firma de desarrollador, Apple Silicon no ejecuta el binario: se firma ad hoc
# o, con SIGN_IDENTITY, con el certificado propio («Notchwatch Self-Signed»).
# El script compila siempre sin certificado y firma después.
if true; then
  echo "Signing $APP_NAME (identity: $SIGN_IDENTITY)..."
  SIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
  fi
  codesign "${SIGN_ARGS[@]}" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi

echo "Installing to $TARGET_PATH..."
if [[ ! -d "$INSTALL_DIR" && -w "$(dirname "$INSTALL_DIR")" ]]; then
  mkdir -p "$INSTALL_DIR"
fi

if [[ -d "$INSTALL_DIR" && -w "$INSTALL_DIR" ]]; then
  rm -rf "$TARGET_PATH"
  ditto "$APP_PATH" "$TARGET_PATH"
else
  sudo mkdir -p "$INSTALL_DIR"
  sudo rm -rf "$TARGET_PATH"
  sudo ditto "$APP_PATH" "$TARGET_PATH"
fi

echo "Installed: $TARGET_PATH"
