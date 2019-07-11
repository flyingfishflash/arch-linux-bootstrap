#!/bin/sh

#for i in "$@"; do
#	case $i in
#			--argument=*)
#			argument="${i#*=}"
#			shift
#			;;
#			*)
#							# unknown option
#			;;
#	esac
#done

# ansible playbooks
cd /bootstrap/ansible
ansible-playbook --vault-password-file=./vault-password bootstrap.yaml -e 'ansible_connection=local'
cd /bootstrap

# growpartfs
systemctl enable growpartfs@-

systemctl set-default multi-user.target

# grub
cp -v /bootstrap/grub /etc/default/grub
mkdir /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg

# the image will not boot with QEMU if the autodetect hooks precedes the block hook
# guessing this is a QEMU quirk
sed -i 's/autodetect modconf block/modconf block autodetect/g' /etc/mkinitcpio.conf
mkinitcpio -P
