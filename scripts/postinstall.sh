#!/bin/bash
# Download libLiteRTLM.a from GitHub release if not present or if it's an LFS pointer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../ios/Vendor"
LIB_PATH="$VENDOR_DIR/libLiteRTLM.a"
RELEASE_URL="https://github.com/Medforall/medforall-react-native-litert-lm/releases/download/v0.1.3/engine_cpu_fat.a"

needs_download=false

if [ ! -f "$LIB_PATH" ]; then
  needs_download=true
elif file "$LIB_PATH" | grep -q "text\|ASCII"; then
  needs_download=true
elif [ "$(wc -c < "$LIB_PATH" | tr -d ' ')" -lt 100000000 ]; then
  # Real binary is ~281MB; anything under 100MB is wrong
  needs_download=true
fi

if [ "$needs_download" = true ]; then
  echo "[react-native-litert-lm] Downloading libLiteRTLM.a (iOS arm64)..."
  mkdir -p "$VENDOR_DIR"
  curl -fSL -o "$LIB_PATH" "$RELEASE_URL"
  echo "[react-native-litert-lm] Downloaded $(du -h "$LIB_PATH" | cut -f1)"
fi
