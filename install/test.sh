#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="user"
PASSWORD="1234"
DISK="/dev/sda"

# --- Разметка диска ---
# Полное стирание таблицы разделов, чтобы убрать MBR и GPT
sgdisk --zap-all $DISK

# Дополнительно можно обнулить первые блоки диска, чтобы не осталось остатков
dd if=/dev/zero of=$DISK bs=512 count=2048

# Создаем новую GPT
sgdisk -o $DISK

# Создаем разделы заново
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux Root Partition" $DISK

# Форматируем разделы
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

# Монтируем корень
mount "${DISK}2" /mnt

# Создаём и монтируем EFI
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

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

