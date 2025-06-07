#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="user"
PASSWORD="1234"
DISK="/dev/sda"

# --- Разметка диска ---
sgdisk --zap-all $DISK
dd if=/dev/zero of=$DISK bs=512 count=2048
sgdisk -o $DISK

sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" $DISK
sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux Root Partition" $DISK

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# --- Установка базовой системы ---
pacstrap /mnt base base-devel linux linux-firmware vim networkmanager sudo git

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

# --- Локализация ---
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Консоль (поддержка кириллицы)
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

# Сеть
systemctl enable NetworkManager

# Пользователи
echo root:$PASSWORD | chpasswd
useradd -m -G wheel $USERNAME
echo $USERNAME:$PASSWORD | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Обновление базы пакетов
pacman -Sy --noconfirm

# Установка зависимостей и сборка Limine
pacman -S --noconfirm git xz base-devel

cd /tmp
git clone https://github.com/limine-bootloader/limine.git
cd limine
make

# Установка загрузочных бинарников
mkdir -p /boot/EFI/BOOT
cp limine.sys /boot/
cp limine-bios.sys /boot/            # для BIOS (опционально)
cp BOOTX64.EFI /boot/EFI/BOOT/

# Генерация limine.cfg
PARTUUID=$(blkid -s PARTUUID -o value "$(findmnt / -o SOURCE -n)")
cat > /boot/limine.cfg <<EOF
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=/vmlinuz-linux
    INITRD_PATH=/initramfs-linux.img
    CMDLINE=root=PARTUUID=${PARTUUID} rw quiet
EOF

# Создание UEFI-записи вручную
efibootmgr --create --disk "$DISK" --part 1 --label "Arch Linux (Limine)" \
  --loader '\EFI\BOOT\BOOTX64.EFI' || echo "! Не удалось создать запись efibootmgr"

# Очистка
cd /
rm -rf /tmp/limine

# --- Конец блока Limine ---



# --- Драйверы для виртуалки ---
pacman -S --noconfirm linux-headers linux-virtio

# --- Графика и окружение ---
pacman -S --noconfirm xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman lxtask \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
pulseaudio-rtp pulseaudio-zeroconf xarchiver unrar unzip p7zip numlockx firefox rofi nitrogen i3-wm

# Менеджер входа ly
pacman -S --noconfirm ly dbus
systemctl enable ly
systemctl enable dbus

# --- Yay (AUR helper) ---
sudo -u $USERNAME bash -c "
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# --- Автозапуск XFCE ---
echo "exec startxfce4" > /home/$USERNAME/.xinitrc
chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

EOF

# --- Финал ---
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
