# Docker Base Image for Arch Linux

[![Build Status](https://travis-ci.org/archlinux/archlinux-docker.svg?branch=master)](https://travis-ci.org/archlinux/archlinux-docker)
[![DockerHub](https://img.shields.io/docker/pulls/btwiuse/arch.svg)](https://hub.docker.com/r/btwiuse/arch)
[![License](https://img.shields.io/github/license/btwiuse/arch?color=%23000&style=flat-round)](https://github.com/btwiuse/arch/blob/master/LICENSE)

This repository contains all scripts and files needed to bootstrap a Docker base image for Arch Linux.

## Goals

* No bloat, only most common tools are added
* Initialize pacman keyrings at build stage, making `pacman -Syu` work out of the box
* Additional package repos:
  - archlinuxcn
  - blackarch
  - btwiuse (for personal use)
  - aur (manually install `yay` or `yaourt` first)

## Usage

Run `./docker-build` to build the base image.

```
$ ./init #
$ cat archs | xargs -L1 -o -P1 -I% env ARCH=% ./docker-build
$ ARCH=i686 VARIANT=docker ./docker-build
```

## Dependencies

Arch

* make
* devtools
* docker

Ubuntu

* arch-install-scripts


## Alternative method for building base packages

```
export ARCH=x86_64 VARIANT=base;
id=$(docker run -dit -v $PWD:/root/arch -w /root/arch -v /var/cache/pacman/pkg:/var/cache/pacman/pkg btwiuse/arch:bootstrap-$ARCH bash);
docker exec -it $id bash -c "./packages $VARIANT | xargs pacman --config rootfs/etc/pacman-bootstrap-$ARCH.conf -Sy --noconfirm --needed"
```
