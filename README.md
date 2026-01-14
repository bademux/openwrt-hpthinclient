# What is it?
Openwrt Firmware for HP t640 Thin Client with attended updates*
It allows to boot HP t640 from USB. 

# How to use

## build
```bash
 DOCKER_BUILDKIT=1 docker build --build-arg OPENWRT_VER=25.12.0-rc2 --output ./ .
```
 
Use openwrt version tag from here https://github.com/openwrt/openwrt/tags  as build arg `OPENWRT_VER`, strip "v"

## flash to USB pendrive
```bash
gzip -c openwrt-*-squashfs-combined-efi.img.gz | dd of=/dev/sdX bs=16M status=progress conv=sync
```

# *Attended updates (owut)
Apply fix for serial console
```bash
owut download -V 25.12.0-rc4 && cat /tmp/firmware.sha256sums | sha256sum -c
gunzip -c /tmp/firmware.bin > /tmp/firmware.img
dev=$(losetup -Pf --show "/tmp/firmware.img")
echo -e "Fix" | parted "$dev" print
mount "${dev}p1" /mnt && sed -i 's/console=ttyS0,115200n8//' /mnt/boot/grub/grub.cfg && umount /mnt
losetup -d $dev
gzip -9 < /tmp/firmware.img > /tmp/firmware.bin && rm /tmp/firmware.img && sha256sum /tmp/firmware.bin > /tmp/firmware.sha256sums
owut install
```

