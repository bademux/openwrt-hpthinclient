# openwrt-hpthinclient
USB Firmware for HP t640 Thin Client

# How to use

## build: 
 ```bash
 DOCKER_BUILDKIT=1 docker build --progress=plain --output ./ .
 ```
 
## flash
```bash
gzip -c openwrt-*-squashfs-combined-efi.img.gz | dd of=/dev/sdX bs=16M status=progress oflag=direct
```
