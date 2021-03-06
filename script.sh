#!/bin/bash

# Script to build your own Raspberry Pi SD card
#
# original script extracted from Klaus M Pfeiffer website at http://blog.kmp.or.at/ 
# and now it's completed under GPLv3 by https://gameboyzero.es community
#
# Remember, you need at least to execute current script (debian based)
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

deb_mirror="http://http.debian.net/debian"

bootsize="64M"
deb_release="stretch"

device=$1
buildenv="/home/box/pruebas/rpi"
rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"
archtype="armhf"

mydate=`date +%Y%m%d`

if [ "$deb_local_mirror" == "" ]; then
  deb_local_mirror=$deb_mirror  
fi

image=""


if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi

if ! [ -b $device ]; then
  echo "$device is not a block device"
  exit 1
fi

if [ "$device" == "" ]; then
  echo "no block device given, just creating an image"
  mkdir -p $buildenv
  image="${buildenv}/rpi_basic_${deb_release}_${archtype}_${mydate}.img"
  dd if=/dev/zero of=$image bs=1MB count=1000
  device=`losetup -f --show $image`
  echo "image $image created and mounted as $device"
else
  dd if=/dev/zero of=$device bs=512 count=1
fi

fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2


w
EOF


if [ "$image" != "" ]; then
  losetup -d $device
  device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  device="/dev/mapper/${device}"
  bootp=${device}p1
  rootp=${device}p2
else
  if ! [ -b ${device}1 ]; then
    bootp=${device}p1
    rootp=${device}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${device}1 nor as ${device}p1, exiting."
      exit 1
    fi
  else
    bootp=${device}1
    rootp=${device}2
  fi  
fi

mkfs.vfat $bootp
mkfs.ext4 $rootp

mkdir -p $rootfs

mount $rootp $rootfs

cd $rootfs

debootstrap --foreign --arch $archtype $deb_release $rootfs $deb_local_mirror
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

mount $bootp $bootfs

echo "deb $deb_local_mirror $deb_release main contrib non-free
" > etc/apt/sources.list

echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

echo "proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
" > etc/fstab

echo "raspberrypi" > etc/hostname

echo "auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
" > etc/network/interfaces

echo "vchiq
snd_bcm2835
" >> etc/modules

echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	de-latin1-nodeadkeys
" > debconf.set

echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update 
apt-get -y install git-core binutils ca-certificates curl gcc zip
wget http://goo.gl/1BOfJ -O /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
mkdir -p /lib/modules/3.1.9+
touch /boot/start.elf
rpi-update
apt-get -y install locales console-common ntp openssh-server less vim
echo \"root:raspberry\" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
cd /tmp
wget https://learn.adafruit.com/pages/6577/elements/1960154/download -O gpio_alt.c
gcc -o gpio_alt gpio_alt.c
sudo chown root:root gpio_alt
sudo chmod u+s gpio_alt
sudo mv gpio_alt /usr/local/bin/
wget https://learn.adafruit.com/pages/6577/elements/1960188/download -O /root/pwmaudio.sh
chmod +x /root/pwmaudio.sh
wget https://learn.adafruit.com/pages/6577/elements/1960193/download -O pwmaudio.service
chmod +x pwmaudio.service
mv pwmaudio.service /lib/systemd/system/pwmaudio.service
systemctl enable pwmaudio.service
echo \"\\ndtoverlay=pwm-2chan,pin=18,func=2,pin2=13,func2=4\" >> /boot/config.txt
wget https://gitlab.gameboyzero.es/bit/generate-gameboyzero-distro/-/archive/master/generate-gameboyzero-distro-master.zip
unzip generate-gameboyzero-distro-master.zip
cd generate-gameboyzero-distro-master
make keypad
mv keypad /opt/keypad
chmod +x /opt/keypad
echo 'SUBSYSTEM==\"input\", ATTRS{name}==\"retrogame\", ENV{ID_INPUT_KEYBOARD}=\"1\"' > /etc/udev/rules.d/10-retrogame.rules
echo '/opt/keypad & \\n exit 0' > /etc/rc.local
rm -f third-stage
" > third-stage
chmod +x third-stage
LANG=C chroot $rootfs /third-stage

echo "deb $deb_mirror $deb_release main contrib non-free
" > etc/apt/sources.list

echo "#!/bin/bash
aptitude update
aptitude clean
apt-get clean
rm -f cleanup
" > cleanup
chmod +x cleanup
LANG=C chroot $rootfs /cleanup

cd

umount $bootp
umount $rootp

if [ "$image" != "" ]; then
  kpartx -d $image
  echo "created image $image"
fi


echo "done."

