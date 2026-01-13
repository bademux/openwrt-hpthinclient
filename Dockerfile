#use DOCKER_BUILDKIT=1 to cache downloaded layer and --output to export built Artefact
#build: DOCKER_BUILDKIT=1 docker build --progress=plain --output ./ .
#flash: gzip -c openwrt-*-squashfs-combined-efi.img.gz | dd of=/dev/sdX bs=16M status=progress oflag=direct conv=fsync
ARG OPENWRT_VER=25.12.0-rc2
FROM openwrt/imagebuilder:x86-64-${OPENWRT_VER} AS builder
COPY <<PACKAGES_EOF packages.txt
apk-mbedtls base-files ca-bundle dnsmasq dropbear e2fsprogs firewall4 fstools grub2-bios-setup
kmod-nft-offload libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils
ppp ppp-mod-pppoe procd-ujail uci uclient-fetch urandom-seed urngd kmod-e1000 kmod-forcedeth kmod-fs-vfat kmod-r8169
luci luci-app-attendedsysupgrade pciutils usbutils parted losetup fstrim resize2fs curl nano lsblk amd64-microcode block-mount
kmod-usb3 kmod-usb2 kmod-usb-hid kmod-usb-serial kmod-usb-storage-uas acpid chattr lsattr btrfs-progs nvme-cli smartmontools
cpupower luci-app-dockerman vsftpd-tls iperf3 libubox kmod-crypto-hw-ccp kmod-drm-amdgpu kmod-kvm-amd amdgpu-firmware
luci-app-commands luci-app-statistics collectd-mod-sensors syncthing rclone-config rclone-webui-react
PACKAGES_EOF
COPY --chmod=755 <<UCI_EOF files/etc/uci-defaults/99-custom
#!/bin/sh
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
uci batch << EOF #expose ftp to wan
  add firewall rule
  set firewall.@rule[-1].name='Wan-FTP-Allow'
  set firewall.@rule[-1].proto='tcp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='21'
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
uci batch << EOF #expose discovery to wan
  add firewall rule
  set firewall.@rule[-1].name='Wan-AVAHI-Allow'
  set firewall.@rule[-1].proto='udp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='5353'
  set firewall.@rule[-1].target='ACCEPT'
EOF
uci batch << EOF #expose syncthing
  add firewall rule
  set firewall.@rule[-1].name='Wan-SyncthingGUI-Allow'
  set firewall.@rule[-1].proto='tcp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='8384'
  set firewall.@rule[-1].target='ACCEPT'
EOF
uci batch << EOF #expose syncthing
  add firewall rule
  set firewall.@rule[-1].name='Wan-SyncthingDiscovery-Allow'
  set firewall.@rule[-1].proto='udp'
  set firewall.@rule[-1].src='wan'
  set firewall.@rule[-1].dest_port='21027'
  set firewall.@rule[-1].target='ACCEPT'
EOF
uci batch << EOF # mount storage
  add fstab mount
  set fstab.@mount[-1].label='storage'
  set fstab.@mount[-1].target='/mnt/storage'
  set fstab.@mount[-1].fstype='btrfs'
  set fstab.@mount[-1].options='noatime,discard=async,compress=zstd:15'
EOF
uci batch << EOF # mount system
  add fstab mount
  set fstab.@mount[-1].label='system'
  set fstab.@mount[-1].target='/mnt/system'
  set fstab.@mount[-1].fstype='ext4'
  set fstab.@mount[-1].options='noatime,nodiratime,discard'
EOF
#dd if=/dev/zero of=/mnt/system/swapfile bs=1G count=16 && chmod 600 /mnt/system/swapfile && mkswap /mnt/system/swapfile
uci batch << EOF # mount swap
  add fstab mount
  set fstab.@mount[-1].device="/mnt/system/swapfile"
EOF
#apply on dir 'chattr -RV +C /mnt/system/syncthing'
uci batch << EOF #syncthing config
  set syncthing.@syncthing[0].enabled=1
  set syncthing.@syncthing[0].home='/mnt/system/syncthing'
  set syncthing.@syncthing[0].logfile='-'
  set syncthing.@syncthing[0].macprocs=1
EOF
#ftp config, set pass for syncthing user with 'passwd syncthing'
usermod -d /mnt/storage/data syncthing
echo 'syncthing' > '/etc/vsftpd/allowed_users'
cat <<EOT >> /etc/vsftpd.conf
chroot_local_user=YES
allow_writeable_chroot=YES
syslog_enable=YES
seccomp_sandbox=NO
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd/allowed_users
hide_file={.stfolder}
EOT
#cp -rfp /opt/docker /mnt/system/ && rf-rf /opt/docker
uci batch << EOF #docker config
  set dockerd.@globals[0].data_root='/mnt/system/docker'
EOF
uci commit

rm /etc/uci-defaults/99-custom
exit 0
UCI_EOF
RUN echo $(tr -d '\n' < packages.txt)
RUN ./setup.sh
#apply t640 boot fix
RUN sed -i '/CONFIG_TARGET_SERIAL=/d' .config
RUN make -j$(nproc) image ROOTFS_PARTSIZE=1024 FILES=files PACKAGES="$(tr '\n' ' ' < packages.txt)"
FROM scratch AS export-stage
COPY --from=builder /builder/bin/targets/x86/64/openwrt-*-x86-64-generic-squashfs-combined-efi.img.gz / 
