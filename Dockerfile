FROM curlimages/curl AS fetch

WORKDIR /tmp/iipsrv
RUN curl -SL https://github.com/ruven/iipsrv/archive/refs/tags/iipsrv-1.2.tar.gz | \
    tar --extract --gzip --strip-components=1 --directory=/tmp/iipsrv

FROM debian:bookworm AS build

# Install development tools
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    g++ \
    libtool \
    make \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install required dependencies
RUN apt-get update && apt-get install -y \
    libtiff-dev \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install optional dependencies
RUN apt-get update && apt-get install -y \
    libmemcached-dev \
    libpng-dev \
    libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY --from=fetch /tmp/iipsrv .
RUN ./autogen.sh \
    && ./configure \
    && make

FROM node:18.18-bookworm-slim AS main

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    lighttpd \
    libtiff6 \
    libjpeg62-turbo \
    libwebp7 \
    libwebpdemux2 \
    libwebpmux3 \
    libpng16-16 \
    libmemcached11 \
    libgomp1 \
    zlib1g \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /build/src/iipsrv.fcgi /usr/local/bin/iipsrv.fcgi
RUN chmod a+x /usr/local/bin/iipsrv.fcgi

COPY iipsrv.conf /etc/lighttpd/conf-available/05-iipsrv.conf
COPY binding.conf /etc/lighttpd/conf-available/01-binding.conf
RUN /usr/sbin/lighty-enable-mod fastcgi && \
    /usr/sbin/lighty-enable-mod iipsrv && \
    /usr/sbin/lighty-enable-mod binding

RUN mkdir -p /run/lighttpd && \
    chown www-data:www-data /run/lighttpd

ENV IIPSRV_BIND=${IIPSRV_BIND:-0.0.0.0} \
    IIPSRV_PORT=${IIPSRV_PORT:-80} \
    FILESYSTEM_PREFIX=/srv/images/ \
    FILESYSTEM_SUFFIX=.tiff

# Alter some defaults for our current purposes
ENV MAX_CVT=${MAX_CVT:-10800} \
    MAX_LAYERS=${MAX_LAYERS:-10} \
    CACHE_CONTROL=${CACHE_CONTROL:-no-store} \
    CORS=${CORS:-*} \
    VERBOSITY=5

RUN mkdir -p ${FILESYSTEM_PREFIX}

CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
