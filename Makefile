DOCKER_USER:=pierres
DOCKER_ORGANIZATION=archlinux
DOCKER_IMAGE:=base

rootfs:
	$(eval TMPDIR := $(shell mktemp -d))
	getenforce || true
        cat /proc/cmdline
	env -i pacstrap -C /usr/share/devtools/pacman-extra.conf -c -d -G -M $(TMPDIR) $(shell cat packages)
	cp --recursive --preserve=timestamps --backup --suffix=.pacnew rootfs/* $(TMPDIR)/
	cp -v pkg/* $(TMPDIR)/root/
	mount --bind $(TMPDIR) $(TMPDIR)
	arch-chroot $(TMPDIR) bash -c 'ls -1 /root/ | grep .pkg.tar.xz | (cd /root; xargs pacman -U --noconfirm)'
	arch-chroot $(TMPDIR) getenforce
	arch-chroot $(TMPDIR) locale-gen
	arch-chroot $(TMPDIR) pacman-key --init
	arch-chroot $(TMPDIR) pacman-key --populate archlinux
	arch-chroot $(TMPDIR) mkinitcpio -p linux
	arch-chroot $(TMPDIR) pkgfile --update
	umount $(TMPDIR)
	tar --numeric-owner --xattrs --acls --exclude-from=exclude -C $(TMPDIR) -c . -f archlinux.tar
	rm -rf $(TMPDIR)

docker-image: rootfs
	docker build -t $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) .

docker-image-test: docker-image
	# FIXME: /etc/mtab is hidden by docker so the stricter -Qkk fails
	docker run --rm $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) sh -c "/usr/bin/pacman -Sy && /usr/bin/pacman -Qqk"
	docker run --rm $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) sh -c "/usr/bin/pacman -Syu --noconfirm docker && docker -v"
	# Ensure that the image does not include a private key
	! docker run --rm $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) pacman-key --lsign-key pierre@archlinux.de
	docker run --rm $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) sh -c "/usr/bin/id -u http"
	docker run --rm $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) sh -c "/usr/bin/pacman -Syu --noconfirm grep && locale | grep -q UTF-8"

ci-test:
	docker run --rm --privileged --tmpfs=/tmp:exec --tmpfs=/run/shm -v /run/docker.sock:/run/docker.sock \
		-v $(PWD):/app -w /app $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE) \
		sh -c 'pacman -Syu --noconfirm make devtools docker && make docker-image-test'

docker-push:
	docker login -u $(DOCKER_USER)
	docker push $(DOCKER_ORGANIZATION)/$(DOCKER_IMAGE)

.PHONY: rootfs docker-image docker-image-test ci-test docker-push
