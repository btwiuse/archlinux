# AGENTS.md

## Overview

This repository builds multi-arch Arch Linux Docker base images for `x86_64`, `i686`, and `aarch64` (ARM arches `arm`, `armv6h`, `armv7h` are defined but commented out in `archs`). Images are published to `btwiuse/arch` on Docker Hub.

The build process uses a 3-stage pipeline: **stage1** bootstraps a minimal rootfs via `pacstrap` and imports it as a Docker image; **stage2** runs inside that container to install packages and create users; **stage3** commits the container to a final image.

---

## Key Commands

| Command | What it does |
|---|---|
| `./init` | One-time setup: configure git identity, clone `qemu-static`, pull bootstrap image |
| `./archs` | Prints active architectures (one per line); pipe to build loop |
| `./archs \| xargs -L1 -P1 -I% env ARCH=% ./docker-build` | Build all active arches in parallel |
| `ARCH=x86_64 VARIANT=base ./docker-build` | Build a specific arch/variant |
| `ARCH=x86_64 ./packages base` | Print package list for a variant (no side effects) |
| `./pull` | Pull existing bootstrap images from Docker Hub |
| `./push` | Push and create multi-arch manifests on Docker Hub (requires login) |
| `./update` | Update an existing `btwiuse/arch:stable` container in-place |

CI runs `make ci-test` (Travis CI, `.travis.yml`).

---

## Architecture & Control Flow

```
./docker-build
  → stage1: pacstrap into $TMPDIR → docker import → btwiuse/arch:bootstrap-$ARCH
  → stage2: docker run bootstrap image → install packages, create users → running container
  → stage3: docker commit container → btwiuse/arch:$VARIANT-$ARCH
  → cleanup $TMPDIR
```

- `./stages` is the script actually executed **inside** the build container during CI (`docker-build` invokes it via `btwiuse/arch:docker-x86_64`).
- `VARIANT` controls which package set is installed: `bootstrap`, `base`, `docker`, or anything else (→ `all`).
- `NAME` (container name) and `TMPDIR` are derived from `mktemp`, keeping parallel builds non-conflicting.

---

## Package Lists

All package lists live in `pkgs/`. The `./packages` script assembles them at build time.

```
pkgs/
  archlinux-bootstrap-packages   # minimal set for stage1 pacstrap
  cmdline                        # top-level (currently just bat, appears to be a stub)
  common/                        # shared across all arches
    base, base-devel             # core packages
    keyring                      # archlinux-keyring, archlinuxcn-keyring, blackarch-keyring
    dev, editor, cmdline         # tooling
    arch, archive, network       # utilities
    monitor, remote, download    # more utilities
    optional-*                   # not included in base variant
  x86_64/, i686/, aarch64/, ...  # arch-specific overrides
    keyring                      # arch-specific keyrings (e.g. archlinuxarm-keyring for ARM)
    optional-container           # docker, podman, buildah, skopeo
    optional-dev-lang            # go, ruby, python, clang, etc.
    optional-drivers             # e.g. broadcom-wl
```

**Variant → package set mapping** (in `./packages`):
- `bootstrap` → hardcoded sed/gzip/grep + `pkgs/archlinux-bootstrap-packages`
- `base` → `common/{base*,base-devel,dev,keyring,editor,cmdline}` + `$ARCH/keyring`
- `docker` → same as `base` + `docker`
- anything else → all files in `common/` + all files in `$ARCH/`

Lines starting with `#` are stripped; blank lines are filtered.

---

## Adding/Removing Packages

- Edit the appropriate file under `pkgs/common/` or `pkgs/$ARCH/`.
- Use `#` to comment out packages without deleting them.
- To add a new optional category, create a new file named `optional-<name>` in `pkgs/common/` or `pkgs/$ARCH/`; it will be included automatically in the `all` variant but not in `base`.

---

## Active Architectures

Controlled by the `archs` file. Currently active: `x86_64`, `i686`, `aarch64`. ARM arches (`arm`, `armv6h`, `armv7h`) are commented out.

To enable an arch, uncomment it in `archs` and ensure corresponding files exist:
- `pkgs/$ARCH/keyring`
- `rootfs/etc/pacman-$ARCH.conf`
- `rootfs/etc/pacman-bootstrap-$ARCH.conf`

---

## Rootfs / Configuration

`rootfs/` is copied verbatim into the container at the start of stage2 (`cp --recursive --preserve=timestamps --backup --suffix=.pacold rootfs/* /`). Existing files get a `.pacold` backup.

After copying, `/etc/pacman.conf` is symlinked to `pacman-$ARCH.conf`. This is how arch-specific pacman configurations are applied.

Key configs:
- `rootfs/etc/pacman-$ARCH.conf` — runtime pacman config; includes `[archlinuxcn]`, `[blackarch]`, `[btwiuse]` repos; `SigLevel = Never TrustAll`
- `rootfs/etc/pacman-bootstrap-$ARCH.conf` — used only during stage1 pacstrap; uses `rootfs/etc/pacman.d/mirrorlist` (relative path)
- `rootfs/etc/locale.gen` / `locale.conf` — sets `en_US.UTF-8`

---

## Users & Groups

Defined in the `users` and `groups` files (plain text, one per line). Stage2 creates each user with `useradd -U -ms /bin/bash` (no password), adds them to all listed groups, and grants passwordless sudo to `%wheel`.

Current users: `aaron`, `btwiuse`, `chronos`, `libredot`, `navigaid`, `sage`, `star`  
Current groups: `wheel`, `video`, `audio`, `vboxusers`, `plugdev`, `docker`, `libvirt`, `lxd`, `podman`

---

## Keyrings

The `./keyrings` script reads `pkgs/{common,$ARCH}/keyring`, strips `-keyring` suffix, and deduplicates. This list is passed to `pacman-key --populate` in stage2.

**Gotcha**: Stage2 has `setup-keyring` commented out — keyring initialization is skipped in the default build. If you re-enable it, be aware it is slow and requires entropy.

---

## Docker Image Naming

| Image | Description |
|---|---|
| `btwiuse/arch:bootstrap-$ARCH` | Minimal stage1 image |
| `btwiuse/arch:$VARIANT-$ARCH` | Final per-arch image |
| `btwiuse/arch:$VARIANT` | Multi-arch manifest (created by `./push`) |
| `btwiuse/arch:docker-x86_64` | Used as the build host for CI (`./docker-build`) |

---

## Exclude List

`exclude` lists paths omitted from the `tar` in stage1 (secrets, caches, runtime state):
- `etc/pacman.d/gnupg/` keys and sockets
- `root/*`, `tmp/*`, `var/cache/pacman/pkg/*`, `var/lib/pacman/sync/*`, `var/tmp/*`

---

## Pacman Repo Configuration

All `pacman-*.conf` files use `SigLevel = Never TrustAll` — signature checking is disabled. Custom repos configured:
- **`[archlinuxcn]`** — mirrors at `ustc.edu.cn` and `tsinghua.edu.cn`
- **`[blackarch]`** — same mirrors
- **`[btwiuse]`** — GitHub releases at `btwiuse/archpkg` (disabled on some arches)

The `[btwiuse]` repo provides AUR-built packages like `binfmt-qemu-static-all-arch`, `qemu-user-static-git`, `tmux-xpanes`, `cheat-bash-git`, `fakepkg`.

---

## Gotchas

- **`./docker-build` must run on an Arch Linux host** for stage1 (uses `pacstrap` from `arch-install-scripts`). On Ubuntu, `arch-install-scripts` provides a compatible `pacstrap`.
- **Package cache**: if `/var/cache/pacman/pkg` exists on the host (i.e., building on Arch), it's bind-mounted in — otherwise `cache-$ARCH/` in the repo root is used.
- **Bootstrap image reuse**: stage1 skips `pacstrap` if the bootstrap image already exists in Docker. Delete it manually to force a rebuild.
- **`./push` hardcodes a Docker Hub password** in plaintext — do not commit new credentials here; update `.travis.yml` secrets or use `docker login` interactively instead.
- **`makepkg.conf`** in `rootfs/etc/` sets build flags for the container environment.
- **`./squash` and `./update`** are alternative update workflows, not part of the main build pipeline.
- **`hooks/post_checkout`** installs a `k0s` agent and triggers an infinite rebuild loop — this is a Docker Hub automated build hook, not something to run locally.
