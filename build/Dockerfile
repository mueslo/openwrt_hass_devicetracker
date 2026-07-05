ARG SDK_IMAGE_TAG=x86_64-main

FROM openwrt/sdk:${SDK_IMAGE_TAG} AS builder

# The openwrt/sdk image is a lightweight wrapper: setup.sh downloads
# the actual SDK tarball from downloads.openwrt.org and verifies it with GPG.
RUN bash ./setup.sh

# Copy package source into the SDK feed tree
COPY packages/net/hass-tracker feeds/packages/net/hass-tracker/

# Install feed, enable apk output, and build
RUN ./scripts/feeds update -i \
    && ./scripts/feeds install hass-tracker \
    && echo "CONFIG_USE_APK=y" >> .config \
    && echo "CONFIG_SIGNED_PACKAGES=n" >> .config \
    && make defconfig \
    && make package/hass-tracker/compile -j$(nproc)

# Extract the .apk artifact
RUN mkdir -p /output \
    && cp $(find bin -name "hass-tracker*.apk" | head -1) /output/

FROM scratch AS export
COPY --from=builder /output /
