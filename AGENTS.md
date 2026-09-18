# AGENTS.md

## Overview

This repository builds multi-arch Arch Linux Docker base images for `x86_64`, `i686`, `aarch64`, and `riscv64`. ARM arches `arm` / `armv6h` / `armv7h` are defined in `pkgs/` but commented out in `archs`.

**Build and publish are fully driven by GitHub Actions** (`.github/workflows/build.yml`). No Travis, no Docker Hub automated build, no k0s agents. The legacy `hooks/post_checkout`, `.travis.yml`, and the in-tree `./docker-build` indirection are kept only for local development; CI does not use them.

Published destinations:
* **Docker Hub** — `btwiuse/arch:{base,latest,base-<arch>,bootstrap-<arch>}`
* **GitHub Container Registry** — `ghcr.io/btwiuse/arch:{base,latest,base-<arch>,bootstrap-<arch>}`
* **GitHub Releases** — `rootfs-<short-sha>` with one `archlinux-base-<arch>.tar.gz` per arch
* **GitHub Actions artifacts** — `rootfs-<arch>` per build (debug / direct download)

The 3-stage pipeline is unchanged:
* **stage1** bootstraps a minimal rootfs via `pacstrap` and imports it as `bootstrap-<arch>`
* **stage2** runs inside that container to install packages and create users
* **stage3** commits the container to the final `base-<arch>` image

---

## CI: `.github/workflows/build.yml`

Two jobs. The bootstrap matrix runs 4 arches in parallel; the aggregate job collects the per-arch images, builds the multi-arch manifest list, pushes to GHCR and (if `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` are set as repo secrets) Docker Hub, and verifies the published manifest contains all four architectures.

```
push / tag / workflow_dispatch
        │
        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ bootstrap  (matrix: x86_64, i686, aarch64, riscv64)             │
 │                                                                 │
 │   1. install pacstrap + pacman-static (apt + fallback download) │
 │   2. (non-native arches) docker/setup-qemu-action              │
 │   3. stage1: pacstrap → tar.gz → docker import → :bootstrap-$A │
 │   4. stage2: docker run bootstrap, install pkgs, add users     │
 │   5. stage3: docker commit → :base-$A                          │
 │   6. push both :bootstrap-$A and :base-$A to GHCR               │
 │   7. upload-artifact dist/archlinux-base-$A.tar.gz              │
 │   8. publish tarball to GitHub Releases (concurrent, see below) │
 └─────────────────────────────────────────────────────────────────┘
        │
        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ aggregate  (needs: bootstrap)                                   │
 │                                                                 │
 │   1. pull :base-<arch> for each of the four arches             │
 │   2. assemble and push multi-arch manifest list :base + :latest │
 │      to ghcr.io/btwiuse/arch                                    │
 │   3. if DOCKERHUB_USERNAME + DOCKERHUB_TOKEN are set:           │
 │      docker login, re-create manifest list, push to            │
 │      docker.io/btwiuse/arch                                     │
 │   4. verify ghcr.io/btwiuse/arch:base contains all four arches │
 │      (warnings on missing, not failures)                        │
 └─────────────────────────────────────────────────────────────────┘
```

### Concurrency model

* The four bootstrap jobs run in parallel; each is responsible for its own arch's `:base-<arch>` image and its own rootfs tarball.
* Each bootstrap job publishes its tarball directly to the GitHub Release tagged `rootfs-<short-sha>` (or the tag name on a tag push). The first job to find the release missing creates it; the rest fall through to `gh release upload --clobber` with their own tarball. This avoids cross-job artifact transfer and serial waiting on a release job.
* `aggregate` runs after all four bootstrap jobs finish. It pulls the per-arch images, assembles the multi-arch list, pushes to GHCR and Docker Hub, then verifies completeness.

### Required secrets

| Secret | Used by | Required? |
|---|---|---|
| `GITHUB_TOKEN` | built-in, no setup needed | yes (auto) |
| `DOCKERHUB_USERNAME` | `aggregate` (optional Docker Hub publish) | no (only if you want Docker Hub) |
| `DOCKERHUB_TOKEN` | `aggregate` (optional Docker Hub publish) | no (only if you want Docker Hub) |

When `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` are not set, the aggregate step emits `::notice::DOCKERHUB_USERNAME/DOCKERHUB_TOKEN not set; skipping Docker Hub publish` and continues. The Docker Hub push path is therefore opt-in.

---

## Key Commands

| Command | What it does |
|---|---|
| `./init` | One-time local setup: git config, pull bootstrap image. Not used by CI. |
| `./archs` | Prints active architectures (one per line); pipe to a build loop locally. |
| `./archs \| xargs -L1 -I% env ARCH=% ./docker-build` | Local build all active arches serially. |
| `ARCH=x86_64 VARIANT=base ./docker-build` | Local build a specific arch + variant. |
| `ARCH=x86_64 ./packages base` | Print package list for a variant (no side effects). |
| `./pull` | Pull existing bootstrap images from Docker Hub (local development). |
| `./push` | Manual push and multi-arch manifest assembly for Docker Hub. The CI `aggregate` job supersedes this; the script is kept for parity and ad-hoc use. Requires `docker login`. |
| `./update` | Update an existing `btwiuse/arch:stable` container in-place (legacy). |

CI runs on every push that touches the build paths (`.github/workflows/**`, `pkgs/**`, `rootfs/**`, `stages`, `packages`, `push`, `pull`, `keyrings`, `users`, `groups`, `exclude`, `archs`).

---

## Architecture & Control Flow (local)

```
./docker-build  (== hooks/build)
  → stage1: pacstrap into $TMPDIR → docker import → btwiuse/arch:bootstrap-$ARCH
  → stage2: docker run bootstrap image → install packages, create users → running container
  → stage3: docker commit container → btwiuse/arch:$VARIANT-$ARCH
  → cleanup $TMPDIR
```

- `./stages` is the script that *was* executed inside the build container in the old CI setup. The new CI inlines stage2 into a `docker run` heredoc, so `./stages` is no longer the source of truth — keep it for reference only, or delete it.
- `VARIANT` controls which package set is installed: `bootstrap`, `base`, `docker`, or anything else (→ `all`).
- `NAME` (container name) and `TMPDIR` are derived from `mktemp`, keeping parallel local builds non-conflicting.

---

## Package Lists

All package lists live in `pkgs/`. The `./packages` script assembles them at build time.

```
pkgs/
  archlinux-bootstrap-packages       # minimal set for stage1 pacstrap
  cmdline                            # top-level stub
  common/                            # shared across all arches
    base, base-devel                 # core packages
    keyring                          # archlinux-keyring (+ arch-specific)
    dev, editor, cmdline             # tooling
    arch, archive, network           # utilities
    monitor, remote, download        # more utilities
    optional-*                       # not included in the base variant
  x86_64/, i686/, aarch64/, riscv64/, ...  # arch-specific overrides
    keyring                          # arch-specific keyrings
    optional-*                       # arch-specific optional packages
```

**Variant → package set mapping** (in `./packages`):
- `bootstrap` → hardcoded sed/gzip/grep + `pkgs/archlinux-bootstrap-packages`
- `base` → `common/{base*,base-devel,dev,keyring,editor,cmdline}` + `$ARCH/keyring` + `docker` (hardcoded)
- anything else → all files in `common/` + all files in `$ARCH/`

Lines starting with `#` are stripped; blank lines are filtered.

### Active architectures and their repo URLs

Each arch has two pacman configs in `rootfs/etc/`:

| Arch | Bootstrap repo (stage1 pacstrap) | Runtime repo (stage2 pacman -Syu) | Notes |
|---|---|---|---|
| x86_64 | upstream Arch Linux | upstream Arch Linux | default |
| i686 | `mirror.archlinux32.org` | `mirror.archlinux32.org` | Arch Linux 32 |
| aarch64 | `ca.us.mirror.archlinuxarm.org` | `ca.us.mirror.archlinuxarm.org` | Arch Linux ARM |
| riscv64 | `riscv.mirror.pkgbuild.com/repo` | `riscv.mirror.pkgbuild.com/repo` | not on upstream mirror.archlinux.org yet |

`SigLevel = Never TrustAll` everywhere; `[archlinuxcn]` is **dropped on arches where it doesn't ship packages** (i686, riscv64).

---

## Adding/Removing Packages

- Edit the appropriate file under `pkgs/common/` or `pkgs/$ARCH/`.
- Use `#` to comment out packages without deleting them.
- To add a new optional category, create a new file named `optional-<name>` in `pkgs/common/` or `pkgs/$ARCH/`; it will be included automatically in the `all` variant but not in `base`.

---

## Active Architectures

Controlled by the `archs` file. Currently active: `x86_64`, `i686`, `aarch64`, `riscv64`. ARM arches (`arm`, `armv6h`, `armv7h`) are commented out.

To enable an arch, uncomment it in `archs` and ensure the corresponding files exist:
- `pkgs/$ARCH/keyring`
- `rootfs/etc/pacman-$ARCH.conf`
- `rootfs/etc/pacman-bootstrap-$ARCH.conf`

Then extend the matrix in `.github/workflows/build.yml` and the manifest list assembly in the `aggregate` job to include the new arch.

---

## Rootfs / Configuration

`rootfs/` is copied verbatim into the container at the start of stage2 (`cp --recursive --preserve=timestamps --backup --suffix=.pacold rootfs/* /`). Existing files get a `.pacold` backup.

After copying, `/etc/pacman.conf` is symlinked to `pacman-$ARCH.conf`. This is how arch-specific pacman configurations are applied.

Key configs:
- `rootfs/etc/pacman-$ARCH.conf` — runtime pacman config; includes `[archlinuxcn]` / `[blackarch]` / `[btwiuse]` where supported; `SigLevel = Never TrustAll`
- `rootfs/etc/pacman-bootstrap-$ARCH.conf` — used only during stage1 pacstrap; mirror URL structure is arch-specific
- `rootfs/etc/locale.gen` / `locale.conf` — sets `en_US.UTF-8`

---

## Users & Groups

Defined in `users` and `groups` (plain text, one per line). Stage2 creates each user with `useradd -U -ms /bin/bash` (no password), adds them to all listed groups, and grants passwordless sudo to `%wheel`.

Current users: `aaron`, `btwiuse`, `chronos`, `libredot`, `navigaid`, `sage`, `star`
Current groups: `wheel`, `video`, `audio`, `vboxusers`, `plugdev`, `docker`, `libvirt`, `lxd`, `podman`

---

## Keyrings

`./keyrings` reads `pkgs/{common,$ARCH}/keyring`, strips the `-keyring` suffix, and deduplicates. The list is passed to `pacman-key --populate` in stage2.

**Gotcha**: Stage2 has `setup-keyring` commented out — keyring initialization is skipped in the default build. If you re-enable it, be aware it is slow and requires entropy.

---

## Docker Image Naming

| Image | Description |
|---|---|
| `ghcr.io/btwiuse/arch:bootstrap-$ARCH` (also `btwiuse/arch:bootstrap-$ARCH`) | Minimal stage1 image |
| `ghcr.io/btwiuse/arch:base-$ARCH` (also `btwiuse/arch:base-$ARCH`) | Final per-arch image with packages + users |
| `ghcr.io/btwiuse/arch:base` (also `:latest`) | Multi-arch manifest list (built by the aggregate job) |

---

## Rootfs Tarball Releases

For every CI run on `master`, the workflow creates a GitHub Release `rootfs-<short-sha>` with one tarball per arch (`archlinux-base-x86_64.tar.gz`, `archlinux-base-i686.tar.gz`, `archlinux-base-aarch64.tar.gz`, `archlinux-base-riscv64.tar.gz`). Tag pushes (e.g. `v20240917`) reuse the tag name as the release tag.

Each tarball is gzip-compressed and uses the same `exclude` rules as `docker import`, so it is a faithful on-disk representation of the `:bootstrap-$ARCH` image.

Consumers:
```
# stream straight into docker import
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-abc1234/archlinux-base-x86_64.tar.gz \
  | docker import - btwiuse/arch:local

# or extract as a chroot
tar -xzf archlinux-base-x86_64.tar.gz -C /var/lib/mychroot
```

---

## Exclude List

`exclude` lists paths omitted from the tar in stage1 (secrets, caches, runtime state):
- `etc/pacman.d/gnupg/` keys and sockets
- `root/*`, `tmp/*`, `var/cache/pacman/pkg/*`, `var/lib/pacman/sync/*`, `var/tmp/*`

The same file is used for both the bootstrap `docker import` and the rootfs tarball, so they stay in sync.

---

## Pacman Repo Configuration

All `pacman-*.conf` files use `SigLevel = Never TrustAll` — signature checking is disabled. Custom repos configured where supported:
- **`[archlinuxcn]`** — mirrors at `ustc.edu.cn` and `tsinghua.edu.cn` (skipped on i686 / riscv64 — no upstream packages)
- **`[blackarch]`** — same mirrors (skipped on i686 / riscv64)
- **`[btwiuse]`** — GitHub releases at `btwiuse/archpkg` (disabled on some arches)

The `[btwiuse]` repo provides AUR-built packages like `binfmt-qemu-static-all-arch`, `qemu-user-static-git`, `tmux-xpanes`, `cheat-bash-git`, `fakepkg`.

---

## Gotchas

- **CI runners are Ubuntu**, not Arch. The CI installs `arch-install-scripts` (provides `pacstrap`) and falls back to fetching `pacman-static` from `pkgbuild.com/~morganamilo/pacman-static/` when `pacman-package-manager` is not in the runner's apt index.
- **Non-native arches** (`i686`, `aarch64`, `riscv64`) need QEMU user-mode emulation. `docker/setup-qemu-action` registers `tonistiigi/binfmt` automatically; do **not** rely on the host kernel having binfmt-misc pre-configured.
- **Bootstrap image reuse**: stage1 always rebuilds from scratch — there is no incremental reuse. The Docker Hub automated-build bootstrap-skip behaviour is gone.
- **Docker Hub push is opt-in** via `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets. Without these the workflow still produces GHCR images and rootfs releases.
- **`./docker-build` runs on an Arch Linux host** (uses `pacstrap`). On Ubuntu it can work via `arch-install-scripts`, but it is no longer the CI entry point — use GitHub Actions instead.
- **Package cache**: `actions/cache` is **not currently used** (the `hashFiles` interaction had bugs in earlier iterations). The runner's `~/.cache/pacman/pkg` is populated per-job but is not shared across runs. Adding persistent caching is a future improvement.
- **`./push` still has a hardcoded Docker Hub password** in plaintext. CI does not use it. Plan to rotate the token and replace the inline password with a read-from-env or simply delete the script.
- **`makepkg.conf`** in `rootfs/etc/` sets build flags for the container environment.
- **`./squash` and `./update`** are alternative update workflows, not part of the main build pipeline.
- **`hooks/post_checkout` is removed**. It installed a `k0s` agent and triggered an infinite rebuild loop on Docker Hub automated builds. CI no longer touches it.
- **`.travis.yml` is removed**. The Travis `make ci-test` config was already broken (no Makefile).