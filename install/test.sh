#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
USERPASS="0502"
ROOTPASS="root"
DISK="/dev/sda"

# --- Разметка диска ---
echo "Разметка диска"
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary ext4 1MiB 100%
mkfs.ext4 "${DISK}1"
mount "${DISK}1" /mnt

# --- Установка базовой системы ---
echo "Установка базовой системы"
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git \
xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel xf86-video-vmware dbus \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman lxtask \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
pulseaudio-rtp pulseaudio-zeroconf xarchiver unrar unzip p7zip numlockx firefox rofi nitrogen i3-wm bash-completion

genfstab -U /mnt >> /mnt/etc/fstab

# --- Настройки внутри chroot ---
arch-chroot /mnt /bin/bash <<EOF_CHROOT

# --- Локализация ---
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

# --- Сеть ---
systemctl enable NetworkManager
systemctl enable dbus

# --- Пользователи ---
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# --- Обновление ---
pacman -Syu --noconfirm

# --- Limine ---
limine bios-install $DISK
UUID=\$(blkid -s UUID -o value ${DISK}1)

mkdir -p /boot
cat > /boot/limine.cfg <<EOF
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
PROTOCOL=linux
KERNEL_PATH=/vmlinuz-linux
INITRD_PATH=/initramfs-linux.img
CMDLINE=root=UUID=\${UUID} rw quiet
EOF

echo "Limine успешно установлен и настроен."

# --- Менеджер входа ly ---
pacman -Sy --noconfirm ly
systemctl enable ly

# --- Yay (AUR helper) ---
sudo -u $USERNAME bash -c '
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
'
chown -R $USERNAME:$USERNAME /home/$USERNAME

# --- Автозапуск XFCE ---
echo "exec startxfce4" > /home/$USERNAME/.xinitrc
chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
