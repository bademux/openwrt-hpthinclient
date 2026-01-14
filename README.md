# What is it?
Openwrt Firmware for HP t640 Thin Client.
It allows to boot HP t640 from USB. 
Attended updates work.

# How to use

## build
```bash
 DOCKER_BUILDKIT=1 docker build --build-arg OPENWRT_VER=25.12.0-rc2 --output ./ .
```
 
Use openwrt version tag from here https://github.com/openwrt/openwrt/tags  as build arg `OPENWRT_VER`, strip "v"

## flash to USB pendrive
```bash
gzip -c openwrt-*-squashfs-combined-efi.img.gz | dd of=/dev/sdX bs=16M status=progress oflag=direct
```

# Previous attempts

[Here](previous/)


