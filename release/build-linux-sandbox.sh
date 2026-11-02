#!/usr/bin/env bash
# The Linux release binary, built in the Steam Runtime 3 "sniper" SDK (glibc 2.31) with no network: one binary that runs
# on every current distro and on the Steam Runtime (Steam Deck, Game Mode). Written to target/assets/vana-client-linux-x86_64
# (the asset name the in-app Update looks for), then checked inside the SDK image.
#
# release/build-linux.sh does the same with the host's rustup toolchain mounted into the SDK; this one needs only Docker and
# a populated cargo registry (`cargo fetch` once, with network, fills ~/.cargo/registry):
#   - release/sniper.Dockerfile builds the image (vana-sniper:build): the SDK from registry.gitlab.steamos.cloud, its
#     build dependencies checked, and rustup with the pinned toolchain. Building the image is the only network step, and
#     runs only when the image is missing (or with --rebuild-image).
#   - the build runs `--network none` as an unprivileged user with no capabilities, the repository at /src, the cargo
#     registry at /cargo/registry, a private /tmp, and its output in target/steamrt (apart from a host-glibc target/).
#
# Usage: release/build-linux-sandbox.sh [--rebuild-image]
# Environment: VANA_SNIPER_IMAGE (image name), VANA_BUILD_UID (user id the build runs as, default 1000), VANA_BUILD_CPUS
# (a docker --cpuset-cpus list, default all), CARGO_REGISTRY_DIR (default ~/.cargo/registry).
set -euo pipefail
cd "$(dirname "$0")/.."
image=${VANA_SNIPER_IMAGE:-vana-sniper:build}
uid=${VANA_BUILD_UID:-1000}
registry=${CARGO_REGISTRY_DIR:-$HOME/.cargo/registry}
asset=target/assets/vana-client-linux-x86_64

if [ "${1:-}" = "--rebuild-image" ] || ! docker image inspect "$image" > /dev/null 2>&1; then
    docker build -f release/sniper.Dockerfile -t "$image" release
fi
if [ ! -d "$registry" ]; then
    echo "no cargo registry at $registry: run 'cargo fetch' (with network) once to fill it" >&2
    exit 1
fi
mkdir -p target/steamrt target/assets

# Every container here: no network, no capabilities, an unprivileged user, a private /tmp that may hold executables
# (build scripts run from it).
sandbox=(docker run --rm --network none --user "$uid:$uid" --cap-drop ALL --tmpfs /tmp:rw,exec,size=8g)
[ -z "${VANA_BUILD_CPUS:-}" ] || sandbox+=(--cpuset-cpus "$VANA_BUILD_CPUS")

"${sandbox[@]}" \
    -e HOME=/tmp -e CARGO_HOME=/cargo -e CARGO_NET_OFFLINE=true -e CARGO_TARGET_DIR=/src/target/steamrt \
    -e RUSTFLAGS="-C target-cpu=x86-64-v2" \
    -v "$registry:/cargo/registry" -v "$PWD:/src" -w /src \
    "$image" cargo build --profile dist --offline
cp target/steamrt/dist/vana-client "$asset"

# The checks, inside the SDK image against the file as shipped: the glibc it asks for is no newer than the runtime's, it
# starts, and every library it links is there. (Libraries the client opens at run time, such as the Vulkan loader, are
# not linked and so not listed by ldd; the Steam Runtime provides them.)
"${sandbox[@]}" -v "$PWD/target/assets:/out:ro" -w /out "$image" bash -euo pipefail -c '
    bin=/out/vana-client-linux-x86_64
    have=$(ldd --version | head -1 | grep -o "[0-9][0-9.]*$")
    need=$(objdump -T "$bin" | grep -o "GLIBC_[0-9][0-9.]*" | sort -Vu | tail -1 | sed "s/GLIBC_//")
    echo "glibc: the binary needs ${need}, this runtime has ${have}"
    [ "$(printf "%s\n%s\n" "$need" "$have" | sort -V | tail -1)" = "$have" ] || { echo "binary needs a newer glibc than the runtime" >&2; exit 1; }
    if ldd "$bin" | grep "not found"; then echo "missing libraries (above)" >&2; exit 1; fi
    "$bin" --help > /dev/null
    echo "ldd: nothing missing; --help runs"
'
echo "$asset"
