#!/usr/bin/env bash
#
# stage3: commit the stage2 container as the final per-arch image, and
# write the image's flattened filesystem as a gzip tarball for
# downstream consumers.
#
# Required environment:
#   ARCH     target architecture
#   VARIANT  image variant (base/bootstrap/all)
#   IMAGE    target image name (with :tag), e.g. ghcr.io/foo/arch:base-x86_64
#   TARBALL  output path for the consumer-facing base tarball,
#            e.g. dist/archlinux-base-x86_64.tar.gz
#
# Locates the stage2 container by name pattern; cleans it up.

set -euo pipefail

: "${ARCH:?ARCH required}"
: "${VARIANT:?VARIANT required}"
: "${IMAGE:?IMAGE required}"
: "${TARBALL:?TARBALL required}"

CONTAINER_ID=$(docker ps -aq --filter "name=stage2-${ARCH}-" | head -1)
if [[ -z "$CONTAINER_ID" ]]; then
    echo "::error::no stage2 container for arch ${ARCH}" >&2
    docker ps -a >&2
    exit 1
fi

docker commit \
    --change 'CMD ["/usr/bin/bash"]' \
    --change 'ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US:en' \
    "$CONTAINER_ID" "$IMAGE"
docker rm "$CONTAINER_ID"

# docker export gives a flat tar of the merged image filesystem
# (no layer metadata). gzip it to match the bootstrap tarball's
# format; consumers can either docker import or tar -xzf directly.
EXPORTER=$(docker create "$IMAGE")
sudo docker export "$EXPORTER" | sudo gzip > "$TARBALL"
docker rm "$EXPORTER"

docker images "$IMAGE"