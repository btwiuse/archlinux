# AGENTS.md

## Overview

This repository builds multi-arch Arch Linux Docker base images for `x86_64`, `i686`, `aarch64`, and `riscv64`. ARM arches `arm` / `armv6h` / `armv7h` are defined in `pkgs/` but commented out in `archs`.

**Build and publish are fully driven by GitHub Actions** (`.github/workflows/build.yml`). No Travis, no Docker Hub automated build, no k0s agents. The legacy `hooks/post_checkout`, `.travis.yml`, and the in-tree `./docker-build` indirection are kept only for local development; CI does not use them.

Published destinations:
* **Docker Hub** — `btwiuse/arch:{base,latest,base-<arch>,bootstrap-<arch>}`
* **GitHub Container Registry** — `ghcr.io/btwiuse/arch:{base,latest,base-<arch>,bootstrap-<arch>}`
* **GitHub Releases** — `rootfs-<short-sha>` with both `archlinux-bootstrap-<arch>.tar.gz` and `archlinux-base-<arch>.tar.gz` per arch
* **GitHub Actions artifacts** — `rootfs-bootstrap-<arch>` and `rootfs-base-<arch>` per build (debug / direct download)

### Per-arch image table

Each arch ships as the same set of tags on both registries:

| Arch | GHCR (base / bootstrap) | Docker Hub (base / bootstrap) | Mirror |
|---|---|---|---|
| `x86_64`  | `ghcr.io/btwiuse/arch:base-x86_64` / `:bootstrap-x86_64` | `btwiuse/arch:base-x86_64` / `:bootstrap-x86_64` | upstream Arch Linux |
| `i686`    | `ghcr.io/btwiuse/arch:base-i686` / `:bootstrap-i686` | `btwiuse/arch:base-i686` / `:bootstrap-i686` | `mirror.archlinux32.org` |
| `aarch64` | `ghcr.io/btwiuse/arch:base-aarch64` / `:bootstrap-aarch64` | `btwiuse/arch:base-aarch64` / `:bootstrap-aarch64` | Arch Linux ARM |
| `riscv64` | `ghcr.io/btwiuse/arch:base-riscv64` / `:bootstrap-riscv64` | `btwiuse/arch:base-riscv64` / `:bootstrap-riscv64` | `riscv.mirror.pkgbuild.com` |

The multi-arch manifest lists `:base` and `:latest` on each registry resolve to whichever per-arch image matches the host platform.

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
 │   6. push both :bootstrap-$A and :base-$A to GHCR               │
 │   7. upload-artifact dist/archlinux-bootstrap-$A.tar.gz         │
 │   7b. stage3: docker commit -> docker export -> gzip ->         │
 │       dist/archlinux-base-$A.tar.gz (uploaded as artifact too)  │
 │   8. publish both tarballs to GitHub Releases (concurrent)      │
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

* The four bootstrap jobs run in parallel; each is responsible for its own arch's `:base-<arch>` image and **two** rootfs tarballs (`archlinux-bootstrap-<arch>.tar.gz` from stage1, `archlinux-base-<arch>.tar.gz` from stage3's `docker export | gzip`).
* Each bootstrap job publishes both tarballs directly to the GitHub Release tagged `rootfs-<short-sha>` (or the tag name on a tag push). The first job to find the release missing creates it; the rest fall through to `gh release upload --clobber` with their own tarballs. This avoids cross-job artifact transfer and serial waiting on a release job.
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
| `./init` | One-time local setup on an Arch host: set git identity, clone the `qemu-static` helper repo, pull `btwiuse/arch:base-x86_64`. CI does not use this; the GitHub Actions runner ships its own tooling. |
| `./archs` | Prints active architectures (one per line); pipe to a build loop locally. |
| `make build ARCH=<arch> VARIANT=<variant>` | Local single-arch build. Equivalent to `ARCH=<arch> VARIANT=<variant> ./.github/scripts/driver.sh`. Requires `pacstrap` on PATH. |
| `make ci-build` | Convenience target used by `.github/workflows/build.yml`. Same as `make build`. |
| `make push-images ARCH=<arch> IMAGE=<repo>` | Push the per-arch `:bootstrap-<arch>` and `:base-<arch>` tags. Used by the workflow's GHCR push step. |
| `ARCH=x86_64 ./packages base` | Print the package list that a variant installs (no side effects). |
| `./pull` | Local dev helper: `docker pull` the bootstrap image for each active arch. CI does not use it. |
| `./push` | Manual push and multi-arch manifest assembly for Docker Hub. The CI `aggregate` job supersedes this; the script is kept for parity and ad-hoc use. Reads `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` from the environment. |
| `./docker-build` | Local build entry point. Now a thin shim that exports `IMAGE`/`TARBALL_DIR`/`PKGDIR` and execs `.github/scripts/driver.sh`. The legacy `hooks/build` (which launched a `btwiuse/arch:docker-x86_64` helper image to run `./stages`) is replaced. |
| `./update` | Update an existing `btwiuse/arch:stable` container in-place. Legacy, predates the current build pipeline. |

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

For every CI run on `master`, the workflow creates a GitHub Release `rootfs-<short-sha>` with **eight** tarballs per arch — a bootstrap tarball (stage1, the raw pacstrap output) and a base tarball (stage3, the committed image's filesystem flattened by `docker export | gzip`).

| File | Source | Format |
|---|---|---|
| `archlinux-bootstrap-<arch>.tar.gz` | stage1: `sudo tar --exclude-from=exclude -C "$TMPDIR" -czf …` | faithful rootfs of `:bootstrap-<arch>`, same `exclude` rules as `docker import` |
| `archlinux-base-<arch>.tar.gz`      | stage3: `docker export $(docker create "$IMAGE") \| gzip` | flattened filesystem of `:base-<arch>` (committed image, with users/locale/sudoers) |

Tag pushes (e.g. `v20240917`) reuse the tag name as the release tag.

Consumers:
```
# bootstrap: a faithful pacstrap output, drop-in for `docker import`
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-abc1234/archlinux-bootstrap-x86_64.tar.gz \
  | docker import - btwiuse/arch:bootstrap-local

# base: a pre-installed rootfs with the user/locale/sudoers setup
curl -L https://github.com/btwiuse/archlinux/releases/download/rootfs-abc1234/archlinux-base-x86_64.tar.gz \
  | docker import - btwiuse/arch:base-local

# or extract as a chroot
tar -xzf archlinux-bootstrap-x86_64.tar.gz -C /var/lib/mychroot
```

---

## Exclude List

`exclude` lists paths omitted from the stage1 tar (secrets, caches, runtime state):
- `etc/pacman.d/gnupg/` keys and sockets
- `root/*`, `tmp/*`, `var/cache/pacman/pkg/*`, `var/lib/pacman/sync/*`, `var/tmp/*`

This file is only applied to the **bootstrap** tarball (stage1). The **base** tarball is produced by `docker export | gzip` of the committed image, which preserves the full filesystem state at commit time — including the keys/sockets that stage1 strips out, because those are created later by pacman during stage2.

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
- **Package cache**: `actions/cache@v4` caches `/home/runner/.cache/pacman/pkg` between runs, keyed per-arch on the SHA-256 of the package-list files (`pkgs/common/keyring`, `pkgs/common/base`, `pkgs/common/base-devel`, `pkgs/common/dev`, `pkgs/common/cmdline`, `pkgs/archlinux-bootstrap-packages`). The earlier `hashFiles` issues with comma-separated globs were avoided by hashing each file in its own `${{ hashFiles(...) }}` expression.
- **`./push` reads `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` from the environment** (token via stdin). It is no longer invoked by CI; the `aggregate` job does the same work, automated. Keep the script for ad-hoc local publishes.
- **`makepkg.conf`** in `rootfs/etc/` sets build flags for the container environment.
- **`./squash` and `./update`** are alternative update workflows, not part of the main build pipeline.
- **`hooks/post_checkout` is removed**. It installed a `k0s` agent and triggered an infinite rebuild loop on Docker Hub automated builds. CI no longer touches it.
- **`.travis.yml` is removed**. The Travis `make ci-test` config was already broken (no Makefile).