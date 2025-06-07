#!/bin/bash
set -euo pipefail

echo "🖥️ Starting Arch Linux installation for VIRTUAL MACHINE..."

timedatectl set-ntp true

echo "⚙️ Partitioning /dev/vda..."
(
  echo g
  echo n
  echo 1
  echo
  echo
  echo w
) | fdisk /dev/vda

echo "⚙️ Formatting /dev/vda1 as ext4..."
mkfs.ext4 /dev/vda1

mount /dev/vda1 /mnt

echo "⚙️ Installing base system and packages..."
pacstrap /mnt base linux linux-firmware networkmanager \
  xfce4-netload-plugin xfce4-notifyd xfce4-panel xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin xfce4-xkb-plugin xfconf \
  thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman \
  lxtask \
  pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc pulseaudio-rtp pulseaudio-zeroconf \
  xarchiver unrar unzip p7zip \
  numlockx \
  i3 rofi nitrogen firefox


genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -c "
echo '🛠 Setting timezone, locale, hostname...'

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

echo archvm > /etc/hostname

echo '127.0.0.1 localhost' > /etc/hosts
echo '::1       localhost' >> /etc/hosts
echo '127.0.1.1 archvm.localdomain archvm' >> /etc/hosts

echo '🛠 Setting root password...'
echo root:root | chpasswd

echo '🛠 Enabling NetworkManager...'
systemctl enable NetworkManager

echo '🛠 Enabling lightdm (XFCE display manager)...'
pacman -S --noconfirm lightdm lightdm-gtk-greeter
systemctl enable lightdm

echo '🛠 Disabling Wayland for lightdm...'
mkdir -p /etc/lightdm
echo '[Seat:*]' > /etc/lightdm/lightdm.conf
echo 'xserver-command=X -nolisten tcp' >> /etc/lightdm/lightdm.conf

echo '🛠 Setting default target to graphical...'
systemctl set-default graphical.target

echo '🛠 Setting up yay (AUR helper)...'
pacman -S --noconfirm --needed git base-devel
useradd -m -G wheel user
echo 'user:user' | chpasswd

runuser -l user -c 'git clone https://aur.archlinux.org/yay.git ~/yay && cd ~/yay && makepkg -si --noconfirm'

echo '🛠 Allowing sudo for wheel group...'
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

"

umount -R /mnt
echo "✅ Installation finished. Rebooting..."
reboot
