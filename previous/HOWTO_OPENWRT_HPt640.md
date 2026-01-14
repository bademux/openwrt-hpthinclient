The Idea is to have immutable yet extendable Openwrt instalation.
For that purpose [extroot](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration) is used.

```
you can build it with docker or download here https://github.com/bademux/openwrt-hpthinclient
```


First we need to [download\create bootable image](https://firmware-selector.openwrt.org/?version=SNAPSHOT&target=x86%2F64&id=generic), image `squashfs-combined-efi.img.gz`

Installed packages:
```
apk-mbedtls base-files ca-bundle dnsmasq dropbear e2fsprogs firewall4 fstools grub2-bios-setup kmod-button-hotplug kmod-nft-offload libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils ppp ppp-mod-pppoe procd-ujail uci uclient-fetch urandom-seed urngd kmod-e1000 kmod-forcedeth kmod-fs-vfat kmod-r8169 luci luci-app-attendedsysupgrade pciutils usbutils parted losetup resize2fs curl nano lsblk amd64-microcode shadow-usermod block-mount kmod-usb-hid kmod-usb-ohci kmod-usb-serial kmod-usb3 kmod-usb2 kmod-usb-storage-uas acpid btrfs-progs nvme-cli smartmontools cpupower shadow-useradd iperf3 libubox
```
*libubox is missig as of 08.2025 on snapshot

Script to run on first boot (uci-defaults):
```bash
uci batch << EOF #set eth0 as wan
  delete network.@device[0].ports
  set network.wan=interface
  set network.wan.proto='dhcp'
  set network.wan.device='eth0'
EOF
uci batch << EOF #expose luci to wan
  add firewall rule
  set firewall.@rule[-1].name='Wan-HTTP-Allow'
  set firewall.@rule[-1].proto='tcp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='80'
  set firewall.@rule[-1].target='ACCEPT'
EOF
uci batch << EOF #expose ssh to wan
  add firewall rule
  set firewall.@rule[-1].name='Wan-SSH-Allow'
  set firewall.@rule[-1].proto='tcp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='22'
  set firewall.@rule[-1].target='ACCEPT'
EOF
uci batch << EOF # mount btrfs overlay
  set fstab.extroot='mount'
  set fstab.extroot.label='system'
  set fstab.extroot.target='/overlay'
  set fstab.extroot.fstype='btrfs'
  set fstab.extroot.options='noatime,discard=async,compress=zstd:8'
EOF
btrfs filesystem mkswapfile --size 16G /overlay/upper/swapfile
uci batch << EOF # mount swap
  set fstab.swap='swap'
  set fstab.swap.device="/overlay/upper/swapfile"
EOF
#apply
uci commit
```

You may want to activate extroot and swap:
```bash
uci set fstab.extroot.enabled=1
uci set fstab.swap.enabled='1'
uci commit
```
Format it first
```bash
mkfs.btrfs --checksum xxhash -m DUP /dev/nvme0n1pX -L system
```

Unfortunatly defaut boot configuration hung boot on HP t640, so fix below have to be alllied:

unpack firmware:
```bash
gzip -k openwrt-x86-64-generic-squashfs-combined-efi.img.gz
```
apply fix:
```bash
dev=$(losetup -Pf --show openwrt-x86-64-generic-squashfs-combined-efi.img)
echo -e "Fix" | parted "$dev" print
mount "${dev}p1" /mnt && sed -i 's/console=ttyS0,115200n8//' /mnt/boot/grub/grub.cfg && umount /mnt
losetup -d $dev
```

Image can be tested with qemu (efi firmware is mandatory)

```bash
qemu-system-x86_64 -enable-kvm -smp cpus=2 -m 256\
   -M q35 -nographic\
   -netdev user,id=net0\
   -device e1000,netdev=net0,id=net0\
   -netdev user,id=net1\
   -device e1000,netdev=net1,id=net1\
   -drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE_4M.fd\
   -drive format=raw,file=openwrt-x86-64-generic-squashfs-combined-efi.img # -drive format=raw,file=extroot.img
```

Write firmware to pendrive
```bash
dd if=openwrt-x86-64-generic-squashfs-combined-efi.img of=/dev/sdX conv=fsync status=progress
```

Create extroot partition labeled `system` (can be done on fresh Openwrt instalation)
```bash
mkfs.btrfs --checksum xxhash -m DUP /dev/nvme1n1pX -L storage
mount /dev/nvme1n1pX /mnt && btrfs filesystem mkswapfile --size 16G /mnt/swapfile && umount /mnt
```

Additional packages after install:
```bash
apk add --update amdgpu-firmware luci-app-commands luci-app-statistics collectd-mod-sensors luci-app-ksmbd ksmbd-avahi-service syncthing
```

Docker:
```bash
apk add --update amdgpu-firmware luci-app-dockerman

#move data home directly to overlay mount
mkdir -p /overlay/opt/docker/ && mv -R /opt/docker/* /overlay/opt/docker/*
uci get dockerd.globals.data_root='/overlay/opt/docker/'
uci commit
```