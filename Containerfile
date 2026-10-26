# rclone built from source on UBI 9
#
#   podman build -t registry.example.com/tools/rclone-ubi:1.75.2 .
#   podman build --build-arg BUILD_VERSION=v1.75.2 -t ... .

# rclone version (git tag) to build. Deliberately NOT named RCLONE_*:
# rclone reads RCLONE_<FLAG> env vars as flags, so RCLONE_VERSION would be
# treated as --version and break the 'rclone version' check below.
ARG BUILD_VERSION=v1.75.2

# ---- Build stage ------------------------------------------------------------
FROM registry.access.redhat.com/ubi9/go-toolset:latest AS build
ARG BUILD_VERSION

# rclone 1.75 requires Go 1.26 but UBI go-toolset ships Go 1.25, so let the
# go command download the exact toolchain go.mod asks for (checksum-verified
# against sum.golang.org). Needs access to proxy.golang.org at build time.
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0

RUN git clone --depth 1 --branch "${BUILD_VERSION}" \
      https://github.com/rclone/rclone.git /opt/app-root/src/rclone

WORKDIR /opt/app-root/src/rclone

# Same flags as rclone's own Makefile
RUN go build -trimpath \
      -ldflags "-s -X github.com/rclone/rclone/fs.Version=${BUILD_VERSION}" \
      -o /opt/app-root/rclone . \
 && /opt/app-root/rclone version

# ---- Runtime stage ----------------------------------------------------------
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

COPY --from=build /opt/app-root/rclone /usr/local/bin/rclone

# RCLONE_CONFIG=/dev/null      no config file; the remote comes from env vars
# RCLONE_NO_CHECK_CERTIFICATE  skip TLS certificate verification for the
#                              object store endpoint (self-signed / private CA)
ENV HOME=/tmp \
    RCLONE_CONFIG=/dev/null \
    RCLONE_NO_CHECK_CERTIFICATE=true

USER 1001

# The script is NOT baked into the image - it is mounted at /scripts from
# the rclone-copy-script ConfigMap, so it can change without a rebuild.
ENTRYPOINT ["/bin/sh", "/scripts/copy.sh"]
