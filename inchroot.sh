locale-gen en_US.UTF-8
# TODO: try chpasswd

for user in $(cat /root/users); do
  useradd -U -ms /bin/bash ${user} && passwd -d ${user}
done

for group in $(cat /root/groups); do
  groupadd -f ${group}
  for user in $(cat /root/users); do
    usermod -a -G ${group} ${user}
  done
done

echo "%wheel ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

pacman-key --init
pacman-key --populate archlinux

ls -1 /root/ | grep .pkg.tar.xz | (cd /root; xargs pacman -U --noconfirm --overwrite '/*')
#mkinitcpio -p linux
sudo pacman -Syu --noconfirm --overwrite '/*'
pkgfile --update
