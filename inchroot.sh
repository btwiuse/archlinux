#!/usr/bin/env bash
# chroot defaults to /
cd /root/arch

gen-locale(){
  locale-gen en_US.UTF-8
}

ug(){
  # TODO: try chpasswd

  for user in $(cat users); do
    useradd -U -ms /bin/bash ${user} && passwd -d ${user}
  done

  for group in $(cat groups); do
    groupadd -f ${group}
    for user in $(cat users); do
      usermod -a -G ${group} ${user}
    done
  done

  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/wheel
}

setup-keyring(){
  pacman-key --init && pacman-key --populate archlinux archlinuxcn blackarch
}

install-binpkg(){
  ls -1 pkg/*.pkg.tar* | xargs pacman -U --noconfirm --needed --overwrite '/*'
}

update-packages(){
./packages lite | xargs pacman -Syu --noconfirm --needed --overwrite '/*'
# pkgfile --update
}

main(){
  gen-locale
  ug
# setup-keyring
# install-binpkg
# update-packages
}

main "$@"
