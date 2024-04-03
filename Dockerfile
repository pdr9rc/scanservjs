# Builder image
#
# The builder image builds the core javascript app and debian package
# ==============================================================================
FROM node:18-bookworm-slim AS scanservjs-build
ENV APP_DIR=/app
WORKDIR "$APP_DIR"

COPY package*.json build.js "$APP_DIR/"
COPY app-server/package*.json "$APP_DIR/app-server/"
COPY app-ui/package*.json "$APP_DIR/app-ui/"

RUN npm clean-install .

COPY app-server/ "$APP_DIR/app-server/"
COPY app-ui/ "$APP_DIR/app-ui/"

RUN npm run build

COPY makedeb.sh "$APP_DIR/"
RUN ./makedeb.sh

# Sane image
#
# This is the minimum bookworm/node/sane image required which is used elsewhere.
# Dependencies are installed here in order to anticipate and cache what will
# be required by the deb package. It would all still work perfectly well if this
# layer did not exist but testing would be slower and more painful.
# ==============================================================================
FROM debian:bookworm-slim AS scanservjs-base
RUN apt-get update \
  && apt-get install -yq \
    nodejs \
    adduser \
    imagemagick \
    ipp-usb \
    sane-airscan \
    sane-utils \
    tesseract-ocr \
    tesseract-ocr-ces \
    tesseract-ocr-deu \
    tesseract-ocr-eng \
    tesseract-ocr-spa \
    tesseract-ocr-fra \
    tesseract-ocr-ita \
    tesseract-ocr-nld \
    tesseract-ocr-pol \
    tesseract-ocr-por \
    tesseract-ocr-rus \
    tesseract-ocr-tur \
    tesseract-ocr-chi-sim \
  && rm -rf /var/lib/apt/lists/*;

# Core image
#
# This is the minimum core image required. It installs the base dependencies for
# sane and tesseract. The executing user remains ROOT. If you want to build your
# own image with drivers then this is likely the image to start from.
# ==============================================================================
FROM scanservjs-base AS scanservjs-core
ENV \
  # This goes into /etc/sane.d/net.conf
  SANED_NET_HOSTS="" \
  # This gets added to /etc/sane.d/airscan.conf
  AIRSCAN_DEVICES="" \
  # This gets added to /etc/sane.d/pimxa.conf
  PIXMA_HOSTS="" \
  # This directs scanserv not to bother querying `scanimage -L`
  SCANIMAGE_LIST_IGNORE="" \
  # This gets added to scanservjs/server/config.js:devices
  DEVICES="" \
  # Override OCR language
  OCR_LANG=""

# Copy entry point
COPY entrypoint.sh /entrypoint.sh
RUN ["chmod", "+x", "/entrypoint.sh"]
ENTRYPOINT [ "/entrypoint.sh" ]

# Copy the code and install
COPY --from=scanservjs-build "/app/debian/scanservjs_*.deb" "/"
RUN apt-get install ./scanservjs_*.deb \
  && rm -f ./scanservjs_*.deb

WORKDIR /usr/lib/scanservjs

EXPOSE 8080


# default build
FROM scanservjs-core
RUN apt-get update \
  && apt-get install -yq libsane-hpaio \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && echo hpaio >> /etc/sane.d/dll.conf
  && echo '[options]' >> /etc/sane.d/dll.conf
  && echo 'discovery = disable' >> /etc/sane.d/dll.conf
