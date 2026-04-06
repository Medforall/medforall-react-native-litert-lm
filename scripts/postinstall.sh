#!/bin/bash
# Download libLiteRTLM.a from GitHub release if not present or too small
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../ios/Vendor"
LIB_PATH="$VENDOR_DIR/libLiteRTLM.a"
RELEASE_URL="https://github.com/Medforall/medforall-react-native-litert-lm/releases/download/v0.1.3/engine_cpu_fat.a"
EXPECTED_SIZE=294282872

needs_download=false

if [ ! -f "$LIB_PATH" ]; then
  needs_download=true
elif [ "$(wc -c < "$LIB_PATH" | tr -d ' ')" -lt "$EXPECTED_SIZE" ]; then
  needs_download=true
fi

if [ "$needs_download" = true ]; then
  echo "[react-native-litert-lm] Downloading libLiteRTLM.a (iOS arm64, ~281MB)..."
  mkdir -p "$VENDOR_DIR"
  # Use curl with retry, resume support, and no timeout
  curl -fSL --retry 3 --retry-delay 5 -C - -o "$LIB_PATH" "$RELEASE_URL"

  # Verify download completed
  actual_size="$(wc -c < "$LIB_PATH" | tr -d ' ')"
  if [ "$actual_size" -lt "$EXPECTED_SIZE" ]; then
    echo "[react-native-litert-lm] WARNING: Download incomplete ($actual_size/$EXPECTED_SIZE bytes). Retrying..."
    rm -f "$LIB_PATH"
    curl -fSL --retry 3 --retry-delay 5 -o "$LIB_PATH" "$RELEASE_URL"
    actual_size="$(wc -c < "$LIB_PATH" | tr -d ' ')"
    if [ "$actual_size" -lt "$EXPECTED_SIZE" ]; then
      echo "[react-native-litert-lm] ERROR: Download still incomplete ($actual_size/$EXPECTED_SIZE bytes)"
      exit 1
    fi
  fi
  echo "[react-native-litert-lm] Downloaded $(du -h "$LIB_PATH" | cut -f1)"
fi
