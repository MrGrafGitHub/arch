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

# Создание одного корневого раздела
sgdisk -n 1:0:0 -t 1:8300 -c 1:"Linux Root Partition" $DISK

mkfs.ext4 "${DISK}1"

mount "${DISK}1" /mnt

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

# Установка пакетов
pacman -S --noconfirm limine efibootmgr

# Копирование файлов Limine
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/

# Создание записи в NVRAM
efibootmgr --create --disk /dev/sda --part Y --label "Arch Linux Limine Bootloader" --loader '\EFI\limine\BOOTX64.EFI' --unicode --verbose

# Генерация конфигурации Limine
PARTUUID=$(blkid -s PARTUUID -o value /dev/sdXY)
cat > /boot/EFI/limine/limine.cfg <<EOF
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
 PROTOCOL=linux
 KERNEL_PATH=/vmlinuz-linux
 INITRD_PATH=/initramfs-linux.img
 CMDLINE=root=PARTUUID=${PARTUUID} rw quiet
EOF

# Установка загрузчика в MBR (для BIOS-систем)
limine bios-install /dev/sda

echo "Limine успешно установлен и настроен."

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
