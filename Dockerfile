# syntax=docker/dockerfile:1

# Build stage: always runs on the build host's architecture; Zig cross-compiles
# a static musl binary for the requested target platform.
FROM --platform=$BUILDPLATFORM alpine:3.22 AS builder

ARG ZIG_VERSION=0.16.0
ARG BUILDARCH
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl xz

RUN set -eux; \
    case "$BUILDARCH" in \
      amd64) zig_arch=x86_64;  zig_sha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;; \
      arm64) zig_arch=aarch64; zig_sha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;; \
      *) echo "unsupported build arch: $BUILDARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz"; \
    echo "${zig_sha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    rm /tmp/zig.tar.xz; \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /src
COPY build.zig ./
COPY src ./src

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64)   triple=x86_64-linux-musl ;; \
      arm64)   triple=aarch64-linux-musl ;; \
      arm)     triple=arm-linux-musleabihf ;; \
      riscv64) triple=riscv64-linux-musl ;; \
      *) echo "unsupported target arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    zig build -Dtarget="$triple" -Doptimize=ReleaseSmall

# Runtime stage: just the static binary and CA certificates (needed for https:// WebDAV URLs).
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /src/zig-out/bin/webdav-mcp /webdav-mcp

USER 65532:65532

ENTRYPOINT ["/webdav-mcp"]
