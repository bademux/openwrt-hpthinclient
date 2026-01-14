#!/bin/bash
#flash with: gunzip -c openwrt-*-x86-64-generic-squashfs-combined-efi.img.gz | dd of=/dev/sdX iflag=fullblock oflag=direct,sync status=progress bs=8M
declare -r BUILDER=sysupgrade.openwrt.org #asu-2.kyarucloud.moe

read -r -d '' PACKAGES <<'EOF'
apk-mbedtls base-files ca-bundle dnsmasq dropbear e2fsprogs firewall4 fstools grub2-bios-setup
kmod-nft-offload libc libgcc libustream-mbedtls logd mkf2fs mtd netifd nftables odhcp6c odhcpd-ipv6only partx-utils
ppp ppp-mod-pppoe procd-ujail uci uclient-fetch urandom-seed urngd kmod-e1000 kmod-forcedeth kmod-fs-vfat kmod-r8169 luci luci-app-attendedsysupgrade
pciutils usbutils parted losetup fstrim resize2fs curl nano lsblk amd64-microcode block-mount
kmod-usb3 kmod-usb2 kmod-usb-hid kmod-usb-serial kmod-usb-storage-uas acpid chattr lsattr btrfs-progs nvme-cli smartmontools cpupower
luci-app-dockerman vsftpd-tls iperf3 libubox kmod-crypto-hw-ccp kmod-drm-amdgpu kmod-kvm-amd amdgpu-firmware luci-app-commands
luci-app-statistics collectd-mod-sensors syncthing rclone-config rclone-webui-react
EOF

read -r -d '' UCI_DEFAULTS <<'UCI_EOF'
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
UCI_EOF

resp=$(jq -n --arg packages "$PACKAGES" --arg defaults "$UCI_DEFAULTS" '{
           "profile": "generic",
           "target": "x86/64",
           "packages": ($packages | split("\\s+";"")),
           "defaults": $defaults,
           "version": "SNAPSHOT",
           "rootfs_size_mb": "1024",
           "diff_packages": true,
           "client": "t640-builder/1"
       }' | curl -sS -0 -X POST "https://$BUILDER/api/v1/build" --json @-)
req_id=$(jq -r .request_hash <<< "$resp")
echo "Using req_id: $req_id"

while : ; do
    if [[ "$(jq -r '.status'<<< "$resp")" == '500' ]]
    then
        echo "FAILED with serverside error: $(jq -r '.error'<<< "$resp")"
        echo "       stdout: $(jq -r '.stdout'<<< "$resp")"
        echo "       stderr: $(jq -r '.strerr'<<< "$resp")"
        exit 1
    fi
    detail="$(jq -r .detail <<< "$resp")"
    [[ "$detail" == 'done' ]] && break
    echo "[$detail] Waiting..."
    sleep 15
    resp=$(curl -sS "https://$BUILDER/api/v1/build/$req_id")
done

echo "[$detail] Image is ready to download v"$(jq -r .version_code <<< "$resp")""
read -d "\n" name size sha256 <<< "$(jq -r '.images[] | select((.filesystem == "squashfs") and (.type == "combined-efi")) | .name, .size, .sha256'  <<< "$resp")"
echo "Downloading '$name' size: $size"
curl "https://$BUILDER/store/$req_id/$name" -o "$name"
sha256sum "$name"
echo "$sha256 $name" | sha256sum --check --status

read -p "Apply t640 bootfix to downloaded image (y/N)? " -n 1 -r apply_fix
if [[ $apply_fix =~ ^[Yy]$ ]]
then
    gunzip -c "$name" > openwrt.img
sudo bash <<'EOF'
    dev=$(losetup -Pf --show "openwrt.img")
    echo -e "Fix" | parted "$dev" print
    mount "${dev}p1" /mnt && sed -i 's/console=ttyS0,115200n8//' /mnt/boot/grub/grub.cfg && umount /mnt
    losetup -d $dev
EOF
    gzip -9 < openwrt.img > "$name" && rm openwrt.img
fi

echo "done"