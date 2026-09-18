# Docker Base Image for Arch Linux

[![Build](https://github.com/btwiuse/archlinux/actions/workflows/build.yml/badge.svg)](https://github.com/btwiuse/archlinux/actions/workflows/build.yml)
[![DockerHub](https://img.shields.io/docker/pulls/btwiuse/arch.svg)](https://hub.docker.com/r/btwiuse/arch)
[![GHCR](https://img.shields.io/badge/ghcr.io-btwiuse%2Farch-blue)](https://github.com/btwiuse/archlinux/pkgs/container/arch)
[![License](https://img.shields.io/github/license/btwiuse/arch?color=%23000&style=flat-round)](https://github.com/btwiuse/archlinux/blob/master/LICENSE)

Multi-arch Arch Linux Docker base images, built and published by GitHub Actions.

| Arch | Bootstrap tag | Base tag | Notes |
|---|---|---|---|
| `x86_64` | `bootstrap-x86_64` | `base-x86_64` | upstream Arch Linux |
| `i686` | `bootstrap-i686` | `base-i686` | Arch Linux 32 (`mirror.archlinux32.org`) |
| `aarch64` | `bootstrap-aarch64` | `base-aarch64` | Arch Linux ARM |
| `riscv64` | `bootstrap-riscv64` | `base-riscv64` | Arch Linux RISC-V (`riscv.mirror.pkgbuild.com`) |

A multi-arch manifest list `:base` (and `:latest`) is published to both `ghcr.io/btwiuse/arch` and `btwiuse/arch` on Docker Hub, so `docker run --platform linux/amd64|linux/arm64 ... ghcr.io/btwiuse/arch:base` picks the right image automatically.

## Goals

* No bloat, only the most common tools are added
* Initialize pacman keyrings at build time so `pacman -Syu` works out of the box
* Multi-arch: x86_64 / i686 / aarch64 / riscv64
* Reproducible rootfs tarballs published to GitHub Releases for downstream consumers

## Usage

### Pull the multi-arch image

```
docker run --rm -it btwiuse/arch:base
```

Pin to a specific arch with `--platform` if needed.

### Pull a per-arch image

```
docker pull ghcr.io/btwiuse/arch:base-x86_64
docker pull ghcr.io/btwiuse/arch:base-aarch64
```

### Use a rootfs tarball from a release

Each CI run publishes a `rootfs-<short-sha>` release containing per-arch tarballs:

```
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-<sha>/archlinux-base-x86_64.tar.gz \
  | docker import - btwiuse/arch:local
```

The tarball is a faithful on-disk representation of the image (same exclude rules as `docker import`).

## Building locally

The CI is the primary build path. Local builds are still supported for development:

```sh
./init                         # one-time setup on an Arch host
./archs | xargs -L1 -I% env ARCH=% ./docker-build
ARCH=x86_64 VARIANT=base ./docker-build   # single arch + variant
```

`./docker-build` is the `hooks/build` script and runs the same 3-stage pipeline that CI runs inside its container.

## CI

`.github/workflows/build.yml` runs on every push to `master`, every tag push, and via `workflow_dispatch`. See `AGENTS.md` for the full architecture description.

## Dependencies

Arch (host build):

* make
* devtools
* docker

Ubuntu (host build):

* arch-install-scripts

## License

GPL-3. See `LICENSE`.