FROM yhnw/openwrt-sdk:17.01-ar71xx

USER openwrt
WORKDIR /home/openwrt/sdk

COPY build/.config /home/openwrt/sdk/.config
COPY packages/net/hass /home/openwrt/sdk/feeds/packages/net/hass

# initial build to cache compilation of other packages
RUN ./scripts/feeds update -i && ./scripts/feeds install hass && make package/hass/compile -j3

CMD make package/hass/compile -j3

