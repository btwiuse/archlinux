# Docker Base Image for Arch Linux

[![Build](https://github.com/btwiuse/archlinux/actions/workflows/build.yml/badge.svg)](https://github.com/btwiuse/archlinux/actions/workflows/build.yml)
[![DockerHub](https://img.shields.io/docker/pulls/btwiuse/arch.svg)](https://hub.docker.com/r/btwiuse/arch)
[![GHCR](https://img.shields.io/badge/ghcr.io-btwiuse%2Farch-blue)](https://github.com/btwiuse/archlinux/pkgs/container/arch)
[![License](https://img.shields.io/github/license/btwiuse/arch?color=%23000&style=flat-round)](https://github.com/btwiuse/archlinux/blob/master/LICENSE)

Multi-arch Arch Linux Docker base images, built and published by GitHub Actions.

| Arch | GHCR | Docker Hub | Notes |
|---|---|---|---|
| `x86_64` | `ghcr.io/btwiuse/arch:base-x86_64` / `:bootstrap-x86_64` | `btwiuse/arch:base-x86_64` / `:bootstrap-x86_64` | upstream Arch Linux |
| `i686` | `ghcr.io/btwiuse/arch:base-i686` / `:bootstrap-i686` | `btwiuse/arch:base-i686` / `:bootstrap-i686` | Arch Linux 32 (`mirror.archlinux32.org`) |
| `aarch64` | `ghcr.io/btwiuse/arch:base-aarch64` / `:bootstrap-aarch64` | `btwiuse/arch:base-aarch64` / `:bootstrap-aarch64` | Arch Linux ARM |
| `riscv64` | `ghcr.io/btwiuse/arch:base-riscv64` / `:bootstrap-riscv64` | `btwiuse/arch:base-riscv64` / `:bootstrap-riscv64` | Arch Linux RISC-V (`riscv.mirror.pkgbuild.com`) |

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

Each arch ships as its own tag in both `ghcr.io/btwiuse/arch` and `btwiuse/arch` (Docker Hub). Pick the exact image instead of relying on the multi-arch manifest list:

```
# base image (stage3: packages installed, users/locale/sudoers set up)
docker pull ghcr.io/btwiuse/arch:base-x86_64
docker pull ghcr.io/btwiuse/arch:base-i686
docker pull ghcr.io/btwiuse/arch:base-aarch64
docker pull ghcr.io/btwiuse/arch:base-riscv64

# bootstrap image (stage1: pacstrap output, no package install)
docker pull ghcr.io/btwiuse/arch:bootstrap-x86_64
docker pull ghcr.io/btwiuse/arch:bootstrap-i686
docker pull ghcr.io/btwiuse/arch:bootstrap-aarch64
docker pull ghcr.io/btwiuse/arch:bootstrap-riscv64

# same set is mirrored to Docker Hub
docker pull btwiuse/arch:base-x86_64
docker pull btwiuse/arch:bootstrap-x86_64
# ...
```

### Use a rootfs tarball from a release

Each CI run publishes a `rootfs-<short-sha>` release with two tarballs per arch: one for the bootstrap filesystem and one for the committed base image.

```
# bootstrap: drop-in for `docker import`, same content as :bootstrap-<arch>
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-<sha>/archlinux-bootstrap-x86_64.tar.gz \
  | docker import - btwiuse/arch:bootstrap-local

# base: flattened filesystem of the committed :base-<arch> image
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-<sha>/archlinux-base-x86_64.tar.gz \
  | docker import - btwiuse/arch:base-local

# or extract as a chroot (works for either tarball)
tar -xzf archlinux-bootstrap-x86_64.tar.gz -C /var/lib/mychroot
```

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