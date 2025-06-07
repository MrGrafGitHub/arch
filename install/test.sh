#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
USERPASS="1234"
ROOTPASS="root"
DISK="/dev/sda"

# Разметка с ext4 /boot
echo -e "\n\033[1;32mРазметка с ext4 /boot fat32\033[0m"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 300MiB   # /boot
parted -s "$DISK" mkpart primary ext4 300MiB 100%   # /

mkfs.fat -F32 -n boot "${DISK}1"
mkfs.ext4 -L root "${DISK}2"

# Монтируем основную систему
echo -e "\n\033[1;32mМонтируем основную систему\033[0m"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# --- Установка базовой системы ---
echo -e "\n\033[1;32mУстановка базовой системы\033[0m"
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
echo -e "\n\033[1;32mЛокализация\033[0m"
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

# --- СТАВИМ ЗАГРУЗЧИК Limine ---
echo "Установка Limine"

# Убедимся, что есть директория /boot/limine
mkdir -p /boot/limine

# Создаём конфиг Limine
cat > /boot/limine/limine.conf <<EOF
/+Arch Linux
comment: loader linux

//Linux
protocol: linux
path: boot():/vmlinuz-linux
cmdline: root=LABEL=root rw quiet
module_path: boot():/initramfs-linux.img
EOF

# Копируем необходимые файлы
cp /usr/share/limine/limine-bios.sys /boot/limine/
cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/

# Устанавливаем Limine
limine bios-install $DISK

echo -e "\n\033[1;32mLimine успешно установлен и настроен!\033[0m"

# --- Менеджер входа ly ---
pacman -Sy --noconfirm ly
systemctl enable ly



EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
