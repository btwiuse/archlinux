SHELL := /usr/bin/env bash

ARCH ?= $(shell uname -m)
VARIANT ?= base
IMAGE ?= btwiuse/arch
PKGDIR ?= $(HOME)/.cache/pacman/pkg
TARBALL_DIR ?= dist

.PHONY: build ci-build push-images syntax-check

build:
	ARCH=$(ARCH) VARIANT=$(VARIANT) IMAGE=$(IMAGE) PKGDIR=$(PKGDIR) TARBALL_DIR=$(TARBALL_DIR) ./.github/scripts/driver.sh

ci-build: build

push-images:
	ARCH=$(ARCH) IMAGE=$(IMAGE) bash ./.github/scripts/push-images.sh

syntax-check:
	bash -n .github/scripts/driver.sh
	bash -n .github/scripts/stage1.sh
	bash -n .github/scripts/stage2-inner.sh
	bash -n .github/scripts/stage3.sh
