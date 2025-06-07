#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
PASSWORD="1234"  # желательно заменить или потом сменить

# Разметка диска (пример для /dev/sda)
DISK="/dev/sda"

# Разделы
BOOT_PART="${DISK}1"
ROOT_PART="${DISK}2"

# --- Разметка диска ---
sgdisk -o $DISK
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux Root Partition" $DISK

# Форматирование
mkfs.fat -F32 $BOOT_PART
mkfs.ext4 $ROOT_PART

# Монтирование
mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $BOOT_PART /mnt/boot

# --- Установка базовой системы ---
pacstrap /mnt base base-devel linux linux-firmware vim networkmanager sudo git

# --- Настройка системы ---
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

# Локаль и часовой пояс
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Сеть
systemctl enable NetworkManager

# Пользователь и пароль
echo root:$PASSWORD | chpasswd
useradd -m -G wheel $USERNAME
echo $USERNAME:$PASSWORD | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Установка загрузчика Limine
pacman -S --noconfirm git base-devel
cd /tmp
git clone https://github.com/limine-bootloader/limine.git
cd limine
make
make install
cd /
rm -rf /tmp/limine

# Установка дополнительных драйверов для виртуалки (virtio)
pacman -S --noconfirm linux-headers linux-virtio

# Установка Xorg, XFCE минимальный набор, i3wm и утилиты
pacman -S --noconfirm xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman lxtask \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
pulseaudio-rtp pulseaudio-zeroconf xarchiver unrar unzip p7zip numlockx firefox rofi nitrogen i3-wm

# Менеджер входа ly
pacman -S --noconfirm ly

# Yay из AUR (через git)
sudo -u $USERNAME bash -c "
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# Настройка xinitrc для запуска XFCE по умолчанию
echo "exec startxfce4" > /home/$USERNAME/.xinitrc
chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

# Включение ly для автозапуска
systemctl enable ly

EOF

# Размонтировать и перезагрузить
umount -R /mnt
echo "Установка завершена. Перезагружайся."

