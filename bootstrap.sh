#!/bin/bash
#
# Creates a multi-partition QEMU disk image from our buildroot outputs and embeds grub2
#
# TODO: Better error handling
# TODO: Better args (grub.cfg path is assumed)
#


default_locale="en_US.UTF-8"
timezone="US/Eastern"
qemu_img_convert_out="./terraform"

DEBUG=1
IMAGE_NAME="/tmp/archlinux-cloud.qcow2"
IMAGE_SIZE="4G" # 100M used for /boot

function log_()
{
    echo "[$(basename "$0")] $*"
}

function atexit()
{
    [[ -d $MOUNT2 ]] && sudo umount "$MOUNT2" &> /dev/null
    [[ -d $MOUNT1 ]] && sudo umount "$MOUNT1" &> /dev/null
    sudo kpartx -d "$LOOPBACK" &> /dev/null
    sudo losetup -d "$LOOPBACK" &> /dev/null
    sudo qemu-nbd -d "$NBD" &> /dev/null
}

function error()
{
    log_ "Error: $*"
    atexit
    exit 1
}

function check_commands()
{
    for comm in qemu-img qemu-nbd losetup kpartx parted mkfs.ext2 mkfs.ext4 grub-install ;
    do
        command -v "$comm" &> /dev/null || {
            log_ "Command '$comm' is not available"
            exit 1
        }
    done
}

function find_next_nbd()
{
    for dev in /sys/class/block/nbd*;
    do
        local size
        size="$(cat "$dev"/size)"

        if (( size == 0 ));
        then
            printf "%s" "/dev/nbd${dev: -1}"
            return
        fi
    done

    error "No available nbd devices"
}

function find_next_loopback()
{
    sudo losetup -f &> /dev/null || error "No available loopback devices"
    printf "%s" "$(sudo losetup -f)"
}

#####

if [[ -e "$IMAGE_NAME" ]] ; then
    error "File '$IMAGE_NAME' already exists. Exiting to avoid overwriting!"
fi

# init
check_commands
sudo -v || exit
atexit
sudo modprobe nbd max_part=16

# vars
NBD="$(find_next_nbd)"
LOOPBACK="$(find_next_loopback)"
LOOPBACK_N="${LOOPBACK: -1}" # the space before -1 is very important
MAPPER1="/dev/mapper/loop${LOOPBACK_N}p1"
MAPPER2="/dev/mapper/loop${LOOPBACK_N}p2"

(( DEBUG )) && {
    log_ "Debug: NBD=$NBD"
    log_ "Debug: LOOPBACK=$LOOPBACK"
    log_ "Debug: LOOPBACK_N=$LOOPBACK_N"
    log_ "Debug: MAPPER2=$MAPPER1"
    log_ "Debug: MAPPER2=$MAPPER1"
}

export NBD
export LOOPBACK
export MAPPER1
export MAPPER2

#####

qemu-img create -f qcow2 "$IMAGE_NAME" "$IMAGE_SIZE" || error "create image"
log_ "[+] Created image"

sudo qemu-nbd -c "$NBD" "$IMAGE_NAME" || error "mount nbd"
log_ "[+] Bound to $NBD"

sudo parted --script "$NBD"  \
    mklabel msdos               \
    mkpart primary ext2 1M 100M \
    mkpart primary ext4 100M "$IMAGE_SIZE" || error "format"
log_ "[+] Partitioned via parted"
sleep 3

sudo losetup "$LOOPBACK" "$NBD" || error "losetup"
log_ "[+] losetup on $LOOPBACK"
sleep 3

sudo kpartx -a "$LOOPBACK" || error "kpartx"
sleep 3
[[ -e "$MAPPER1" ]] || error "mapper 1 doesnt exist"
[[ -e "$MAPPER2" ]] || error "mapper 2 doesnt exist"
log_ "[+] kpartx"

MOUNT1=$(mktemp -d)
MOUNT2="$MOUNT1/boot"
export MOUNT1
export MOUNT2
log_ "[+] Created mount dirs ($MOUNT1) ($MOUNT2)"

log_ "[...] Starting format..."
sudo mkfs.ext2 "$MAPPER1" -L boot || error "mkfs.ext2"
sudo mkfs.ext4 "$MAPPER2" -L root -U fcd9def0-a80a-4f2f-b427-c65f543790fd || error "mkfs.ext4"
log_ "[+] Formatted in ext2 + ext4..."

sudo mount "$MAPPER2" "$MOUNT1" || error "Failed to mount ext4 partition"
log_ "[+] Mounted $MAPPER2 to $MOUNT1"
sudo mkdir -p "$MOUNT2" # /boot not not exist

sudo mount "$MAPPER1" "$MOUNT2" || error "Failed to mount ext2 partition"
log_ "[+] Mounted $MAPPER1 to $MOUNT2"
log_ "[+] Mounted loopback devices"

# Arch Linux installation

sudo pacstrap -c $MOUNT1 base base-devel ansible

script='genfstab -pU $1 >> $1/etc/fstab'
sudo sh -c "$script" -- "$MOUNT1"

script='echo "127.0.1.1 localhost" >> $1/etc/hosts'
sudo sh -c "$script" -- "$MOUNT1"
script='echo "::1   localhost" >> $1/etc/hosts'
sudo sh -c "$script" -- "$MOUNT1"

sudo arch-chroot $MOUNT1 ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

sudo sed -i 's/#\(en_US\.UTF-8\)/\1/' $MOUNT1/etc/locale.gen
sudo arch-chroot $MOUNT1 locale-gen
script='echo "LANG=$default_locale" > $1/etc/locale.conf'
sudo sh -c "$script" -- "$MOUNT1"

# display the machine's ip address at the login prompt
sudo install -v -o root -g root -m 644 issue/90-issuegen.rules $MOUNT1/etc/udev/rules.d/
sudo install -v -o root -g root -m 700 issue/issuegen $MOUNT1/usr/local/sbin
sudo install -v -o root -g root -m 644 issue/issuegen.service $MOUNT1/etc/systemd/system/
sudo install -v -o root -g root -m 755 -d $MOUNT1/usr/local/share/issuegen
sudo install -v -o root -g root -m 644 issue/issue-header.txt $MOUNT1/usr/local/share/issuegen/

# install growparts (from AUR package: growpart)
sudo install -v -o root -g root -m755 -Dt "$MOUNT1/usr/bin/" growpartfs/growpartfs
sudo install -v -o root -g root -m755 -Dt "$MOUNT1/usr/bin/" growpartfs/growpart
sudo install -v -o root -g root -m644 -Dt "$MOUNT1/usr/lib/systemd/system/" growpartfs/growpartfs@.service

# facilitate working in the chroot session if you use termite
sudo install -v -o root -g root -m644 -Dt "$MOUNT1/usr/share/terminfo/x/" xterm-termite/xterm-termite

# provide files needed in the chroot session
sudo install -v -d $MOUNT1/bootstrap
sudo cp -v chroot.sh $MOUNT1/bootstrap/
sudo cp -rv ansible $MOUNT1/bootstrap/
sudo cp -v grub/grub $MOUNT1/bootstrap/

# chroot
sudo chmod 755 $MOUNT1/bootstrap/chroot.sh
sudo arch-chroot $MOUNT1 /bootstrap/chroot.sh 

# enter the chroot environment for testing/review
#sudo arch-chroot $MOUNT1

sudo rm $MOUNT1/usr/share/terminfo/x/xterm-termite
sudo rm -rf $MOUNT1/bootstrap

sudo grub-install --target=i386-pc --boot-directory="$(readlink -f "$MOUNT2")" "$LOOPBACK" || error "Failed to install grub"
log_ "[+] Grub installed"

#

sudo umount "$MOUNT2" || error "Failed to unmount loop2"
log_ "[+] Unmounted MOUNT2"

sudo umount "$MOUNT1" || error "Failed to unmount loop1"
log_ "[+] Unmounted MOUNT1"
rm -r "$MOUNT1" # remove this dir as we no longer need it

atexit

#

#sudo cp -v "$IMAGE_NAME" /var/lib/libvirt/images/
sudo cp -v "$IMAGE_NAME" $qemu_img_convert_out

#

exit 0
