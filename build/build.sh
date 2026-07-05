#!/bin/bash
#
# Build hass-tracker using the official openwrt/sdk Docker image.
# Produces .apk packages for apk-based OpenWrt (25.12+).
#
set -euo pipefail

SDK_IMAGE_TAG="${SDK_IMAGE_TAG:-x86_64-main}"
OUTPUT_DIR="${OUTPUT_DIR:-$(dirname "$0")/../build/bin}"
PACKAGE_DIR="${PACKAGE_DIR:-$(dirname "$0")/../packages/net/hass-tracker}"

mkdir -p "$OUTPUT_DIR"

echo "Building hass-tracker with openwrt/sdk:${SDK_IMAGE_TAG}..."
echo "  Package:  ${PACKAGE_DIR}"
echo "  Output:   ${OUTPUT_DIR}"

docker run --rm \
    -v "$(realpath "$PACKAGE_DIR"):/package:ro" \
    -v "$(realpath "$OUTPUT_DIR"):/output:rw" \
    "openwrt/sdk:${SDK_IMAGE_TAG}" \
    bash -c '
set -euo pipefail

# Download the actual SDK
bash ./setup.sh

# Copy package into SDK feed
mkdir -p feeds/packages/net/hass-tracker
cp -r /package/* feeds/packages/net/hass-tracker/

# Install feed, enable apk output, build
./scripts/feeds update -i
./scripts/feeds install hass-tracker
echo "CONFIG_USE_APK=y" >> .config
echo "CONFIG_SIGNED_PACKAGES=n" >> .config
make defconfig
make package/hass-tracker/compile -j$(nproc)

# Copy artifact to mounted output
APK=$(find bin -name "hass-tracker*.apk" | head -1)
if [ -z "$APK" ]; then
    echo "ERROR: no .apk produced" >&2
    find bin -type f 2>/dev/null | head -20
    exit 1
fi
cp "$APK" /output/
echo ""
echo "============================================"
echo "Build successful!"
echo "Artifact: $(basename "$APK")"
echo "============================================"
'
