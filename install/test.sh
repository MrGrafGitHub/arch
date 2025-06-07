#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="user"
PASSWORD="1234"
DISK="/dev/sda"

# --- Разметка диска ---
echo "# Очистка диска"
sgdisk --zap-all $DISK
echo "# Запись нулей в начало диска"
dd if=/dev/zero of=$DISK bs=512 count=2048
echo "# Создание новой таблицы разделов"
sgdisk -o $DISK

echo "# Создание корневого раздела"
sgdisk -n 1:0:0 -t 1:8300 -c 1:"Linux Root Partition" $DISK

echo "# Создание файловой системы ext4"
mkfs.ext4 "${DISK}1"

echo "# Монтирование корневого раздела"
mount "${DISK}1" /mnt

# --- Установка базовой системы ---
echo "# Установка базовой системы"
pacstrap /mnt base base-devel linux linux-firmware vim networkmanager sudo git

echo "# Генерация fstab"
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

# --- Локализация ---
echo "# Установка имени хоста"
echo "$HOSTNAME" > /etc/hostname
echo "# Настройка часового пояса"
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "# Настройка локали"
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "# Настройка консоли"
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

# Сеть
echo "# Включение NetworkManager"
systemctl enable NetworkManager

# Пользователи
echo "# Установка пароля для root"
echo root:$PASSWORD | chpasswd
echo "# Создание пользователя"
useradd -m -G wheel $USERNAME
echo "# Установка пароля для пользователя"
echo $USERNAME:$PASSWORD | chpasswd
echo "# Настройка sudo"
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Обновление базы пакетов
echo "# Обновление базы пакетов"
pacman -Sy --noconfirm

# Установка и настройка Limine
echo "# Установка зависимостей для Limine"
pacman -S --noconfirm git xz base-devel

echo "# Клонирование и сборка Limine"
cd /tmp
git clone https://github.com/limine-bootloader/limine.git
cd limine
make

echo "# Установка загрузочных бинарников для BIOS"
cp limine-bios.sys /boot/limine.sys
cp limine-bios-cd.bin /boot/limine-cd.bin

echo "# Генерация конфигурации Limine"
cat > /boot/limine.cfg <<EOL
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
 PROTOCOL=linux
 KERNEL_PATH=/vmlinuz-linux
 INITRD_PATH=/initramfs-linux.img
 CMDLINE=root=/dev/sda1 rw quiet
EOL

echo "# Установка Limine"
limine bios-install /dev/sda

echo "# Очистка временных файлов"
cd /
rm -rf /tmp/limine

# --- Драйверы для виртуалки ---
echo "# Установка драйверов для виртуалки"
pacman -S --noconfirm linux-headers linux-virtio

# --- Графика и окружение ---
echo "# Установка графического окружения"
pacman -S --noconfirm xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman lxtask \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
pulseaudio-rtp pulseaudio-zeroconf xarchiver unrar unzip p7zip numlockx firefox rofi nitrogen i3-wm

# Менеджер входа ly
echo "# Установка менеджера входа ly"
pacman -S --noconfirm ly dbus
systemctl enable ly
systemctl enable dbus

# --- Yay (AUR helper) ---
echo "# Установка Yay"
sudo -u $USERNAME bash -c "
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# --- Автозапуск XFCE ---
echo "# Настройка автозапуска XFCE"
echo "exec startxfce4" > /home/$USERNAME/.xinitrc
chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

EOF

# --- Финал ---
echo "# Размонтирование и завершение установки"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
