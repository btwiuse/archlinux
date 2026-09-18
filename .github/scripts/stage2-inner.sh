#!/usr/bin/env bash
#
# stage2: run inside the freshly imported bootstrap image to install
# the variant's packages, generate locale, and create the user/group
# setup that the runtime expects.
#
# Required environment:
#   ARCH     target architecture
#   VARIANT  image variant (base/bootstrap/all)
#
# Files consumed (relative to the source checkout, which is bind-mounted
# into the container at /root/arch):
#   users                one username per line
#   groups               one group name per line
#   packages             package-list assembler
#   pkgs/**              package list files
#   rootfs/etc/pacman-$ARCH.conf          runtime pacman config
#
# Expects /var/cache/pacman/pkg to be bind-mounted from the runner's
# PKGDIR so package downloads are reused.

set -e

cd /root/arch

gen-locale() {
  locale-gen en_US.UTF-8
}

ug() {
  for user in $(cat users); do
    useradd -U -ms /bin/bash "${user}" && passwd -d "${user}"
  done

  for group in $(cat groups); do
    groupadd -f "${group}"
    for user in $(cat users); do
      usermod -a -G "${group}" "${user}"
    done
  done

  mkdir -p /etc/sudoers.d
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
}

update-packages() {
  ./packages "${VARIANT}" | xargs pacman -Syu --needed --noconfirm --overwrite '/*'
}

cp --recursive --preserve=timestamps --backup --suffix=.pacold rootfs/* /
ln -sf "pacman-${ARCH}.conf" /etc/pacman.conf

update-packages
gen-locale
ug