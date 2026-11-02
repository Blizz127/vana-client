# The Linux release build image: the Steam Runtime 3 "sniper" SDK (glibc 2.31) plus a Rust toolchain, so a binary built in
# it runs on every current distro and on the Steam Runtime (Steam Deck, Game Mode).
#
# Build it with release/build-linux-sandbox.sh (or by hand: docker build -f release/sniper.Dockerfile -t vana-sniper:build
# release). Building the image is the only step that needs the network: it pulls the SDK and downloads rustup and the
# toolchain. The build itself runs from this image with no network (release/build-linux-sandbox.sh).
#
# The SDK already carries the development files the client needs (libudev for gamepads, PipeWire and PulseAudio and
# ALSA for sound, Vulkan, X11 / XCB / Wayland / xkbcommon for the window, clang for bindgen). The check below fails the
# image build if one is missing, rather than building a client that cannot link.
FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest

# The toolchain egui 0.37 and the 2024 edition need. Pinned, so a build under `--network none` never finds a channel it
# lacks and tries to download one.
ARG RUST_VERSION=1.95.0
ARG RUSTUP_VERSION=1.29.0
ARG RUSTUP_SHA256=4acc9acc76d5079515b46346a485974457b5a79893cfb01112423c89aeb5aa10

RUN set -eux; \
    pkg-config --exists libudev x11 xcb xkbcommon wayland-client libpipewire-0.3 libpulse vulkan alsa; \
    command -v clang cmake gcc g++; \
    ls /usr/lib/llvm-11/lib/libclang.so.1

# rustup and the toolchain in a world-readable place, outside any home directory, so the build can run as any user.
ENV RUSTUP_HOME=/usr/local/rustup \
    RUSTUP_TOOLCHAIN=${RUST_VERSION} \
    PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN set -eux; \
    url="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/rustup-init "$url"; \
    echo "${RUSTUP_SHA256} */tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    CARGO_HOME=/usr/local/cargo /tmp/rustup-init -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_VERSION}" --default-host x86_64-unknown-linux-gnu; \
    rm /tmp/rustup-init; \
    chmod -R a+rX /usr/local/rustup /usr/local/cargo; \
    rustc --version; cargo --version

# The build's cargo home (the registry is mounted into it at run time, read from the host's).
RUN mkdir /cargo && chmod 1777 /cargo
ENV CARGO_HOME=/cargo \
    CARGO_NET_OFFLINE=true \
    LIBCLANG_PATH=/usr/lib/llvm-11/lib
WORKDIR /src
