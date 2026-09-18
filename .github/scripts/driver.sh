#!/usr/bin/env bash
#
# driver.sh: orchestrate stage1 -> stage2 -> stage3 for one architecture
# end-to-end.
#
# Invoked by:
#   - .github/workflows/build.yml's bootstrap job, on an Ubuntu runner
#     that has Docker available, to build one per-arch image.
#   - ./stages, when the legacy ./docker-build flow is used on a host
#     that has Docker and pacstrap available (Arch host, or Ubuntu
#     with arch-install-scripts + pacman-static).
#
# Required environment (everything the stages consume, in summary):
#   ARCH     target architecture
#   VARIANT  image variant (base/bootstrap/all)
#   IMAGE    base image name (without :tag), e.g. ghcr.io/foo/arch
#   PKGDIR   shared pacman package cache
#   TARBALL_DIR  output directory for the two consumer-facing tarballs;
#                they will be written as
#                  ${TARBALL_DIR}/archlinux-bootstrap-<arch>.tar.gz
#                  ${TARBALL_DIR}/archlinux-base-<arch>.tar.gz
#
# Sourced companion scripts:
#   stage1.sh       pacstrap + tar.gz + docker import
#   stage3.sh       docker commit + docker export | gzip
#   stage2-inner.sh bash body that runs inside the bootstrap container

set -euo pipefail

: "${ARCH:?ARCH required}"
: "${VARIANT:?VARIANT required}"
: "${IMAGE:?IMAGE required}"
: "${PKGDIR:?PKGDIR required}"
: "${TARBALL_DIR:?TARBALL_DIR required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$TARBALL_DIR"

# ---------- stage1: pacstrap + tar.gz + docker import
PKGDIR="$PKGDIR" \
ARCH="$ARCH" \
BOOTSTRAP_CONF="pacman-bootstrap-${ARCH}.conf" \
TARBALL="${TARBALL_DIR}/archlinux-bootstrap-${ARCH}.tar.gz" \
IMAGE="${IMAGE}:bootstrap-${ARCH}" \
    bash "${SCRIPT_DIR}/stage1.sh"

# ---------- stage2: install packages, create users, generate locale
CONTAINER_NAME="stage2-${ARCH}-$(mktemp -u XXXXXXXX | tr '[:upper:]' '[:lower:]')"
docker run -i \
    --name "${CONTAINER_NAME}" \
    -v "${PWD}:/root/arch" \
    -v "${PKGDIR}:/var/cache/pacman/pkg" \
    -e LC_ALL=C \
    -e VARIANT="${VARIANT}" \
    -e ARCH="${ARCH}" \
    "${IMAGE}:bootstrap-${ARCH}" \
    bash "${SCRIPT_DIR}/stage2-inner.sh"

# ---------- stage3: docker commit + docker export | gzip
ARCH="$ARCH" \
VARIANT="$VARIANT" \
IMAGE="${IMAGE}:base-${ARCH}" \
TARBALL="${TARBALL_DIR}/archlinux-base-${ARCH}.tar.gz" \
    bash "${SCRIPT_DIR}/stage3.sh"