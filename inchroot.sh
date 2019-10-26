#!/usr/bin/env bash
locale-gen en_US.UTF-8
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

FILE=/etc/sudoers
LINE="%wheel ALL=(ALL) NOPASSWD:ALL"
if ! grep -qe "^${LINE}" $FILE; then
  echo "$LINE" | sudo tee -a $FILE
fi

pushd pkg/
ls -1 *.pkg.tar* | xargs pacman -U --noconfirm --needed --overwrite '/*'
popd
cat packages | xargs pacman -Syu --noconfirm --needed --overwrite '/*'

pkgfile --update
pacman-key --init && pacman-key --populate archlinux archlinuxcn blackarch
