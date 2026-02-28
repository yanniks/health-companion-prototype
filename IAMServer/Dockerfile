# syntax = docker/dockerfile:1.2

FROM swift:6.2 AS build-env

# Create app directory
WORKDIR /usr/src/app

# Install system dependencies for building
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get update \
    && apt-get -y install libssl-dev libsasl2-dev libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy package manifest and resolve dependencies first (better layer caching)
COPY Package.swift Package.resolved ./
RUN swift package resolve

COPY Sources Sources/
COPY Tests Tests/

RUN swift build -c release --static-swift-stdlib -Xlinker -ljemalloc

WORKDIR /staging

RUN mv $(swift build --package-path /usr/src/app -c release --show-bin-path)/IAMServer service

# Copy static swift backtracer binary to staging area
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy resources bundled by SPM to staging area
RUN find -L "$(swift build --package-path /usr/src/app -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \; 2>/dev/null || true

FROM ubuntu:noble

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      curl \
      tzdata \
      libcurl4 \
      libxml2 \
    && rm -r /var/lib/apt/lists/*

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build-env --chown=vapor:vapor /staging /app

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Persistent data directory for patient store, auth codes, etc.
RUN mkdir -p /app/data
VOLUME /app/data

EXPOSE 8081
ENTRYPOINT ["/app/service"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8081"]
