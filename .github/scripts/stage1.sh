#!/usr/bin/env bash
#
# stage1: bootstrap a minimal Arch Linux rootfs via pacstrap, import it
# as a Docker image, and write the rootfs as a gzip-compressed tarball
# for downstream consumers (GitHub Releases artifacts).
#
# Required environment:
#   ARCH              target architecture (x86_64, i686, aarch64, riscv64)
#   BOOTSTRAP_CONF    name of the pacman-bootstrap config under
#                     rootfs/etc/, e.g. pacman-bootstrap-x86_64.conf
#   PKGDIR            shared pacman package cache (mounted into the
#                     new rootfs so stage1 reuses previously fetched
#                     packages)
#   TARBALL           output path for the consumer-facing tarball,
#                     e.g. dist/archlinux-bootstrap-x86_64.tar.gz
#   IMAGE             target Docker image tag, e.g. ghcr.io/foo/arch:bootstrap-x86_64
#
# Optional environment:
#   BOOTSTRAP_PACKAGES command to print the bootstrap package list
#                     (defaults to ./packages bootstrap)

set -euo pipefail

: "${ARCH:?ARCH required}"
: "${BOOTSTRAP_CONF:?BOOTSTRAP_CONF required}"
: "${PKGDIR:?PKGDIR required}"
: "${TARBALL:?TARBALL required}"
: "${IMAGE:?IMAGE required}"
: "${BOOTSTRAP_PACKAGES:=./packages bootstrap}"

TMPDIR=$(mktemp -d)
export PKGDIR
mkdir -p "$PKGDIR" "$(dirname "$TARBALL")"
# pacstrap chowns files to root:root, so the whole stage1 runs under
# sudo to match the bootstrap job in CI.
sudo -E pacstrap -C "rootfs/etc/${BOOTSTRAP_CONF}" -c -G -M "$TMPDIR" $(${BOOTSTRAP_PACKAGES})

# gzip-compressed rootfs tarball for downstream consumers (kept in
# sync with docker import via the same exclude rules).
sudo tar --numeric-owner --xattrs --acls --exclude-from=exclude \
    -C "$TMPDIR" -czf "$TARBALL" .

# docker import expects an uncompressed tar stream.
sudo tar --numeric-owner --xattrs --acls --exclude-from=exclude \
    -C "$TMPDIR" -c . \
    | docker import \
        --change 'CMD ["/usr/bin/bash"]' \
        - "$IMAGE"

sudo rm -rf "$TMPDIR"
ls -la "$TARBALL"
docker images "$IMAGE"