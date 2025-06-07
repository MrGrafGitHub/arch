#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="user"
PASSWORD="1234"
DISK="/dev/sda"

# --- Разметка диска ---
# Создаём GPT таблицу
echo "Разметка диска \n Создаём GPT таблицу"
parted -s $DISK mklabel gpt

# Создаём один раздел на весь диск
parted -s $DISK mkpart primary ext4 1MiB 100%

# Форматируем
mkfs.ext4 "${DISK}1"

# Монтируем
mount "${DISK}1" /mnt

# --- Установка базовой системы ---
echo "Установка базовой системы"
pacstrap /mnt base base-devel linux linux-headers linux-firmware nano networkmanager sudo git

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

# --- Локализация ---
echo "Локализация"

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
echo "Сеть"
systemctl enable NetworkManager

# Пользователи
echo "Пользователи"
echo root:$PASSWORD | chpasswd
useradd -m -G wheel $USERNAME
echo $USERNAME:$PASSWORD | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Обновление базы пакетов
echo "Обновление базы пакетов"
pacman -Sy --noconfirm

# Установка пакета limine
echo "Установка пакета limine"
pacman -S --noconfirm limine

# Установка Limine в MBR диска
echo "Установка Limine в MBR диска"
limine bios-install /dev/sda

# Получаем PARTUUID корневого раздела
echo "Получаем PARTUUID корневого раздела"
PARTUUID=$(blkid -s PARTUUID -o value /dev/sda1)

# Конфиг для Limine в /boot/limine.cfg
echo "Конфиг для Limine в /boot/limine.cfg"
cat > /boot/limine.cfg <<EOF
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
PROTOCOL=linux
KERNEL_PATH=/vmlinuz-linux
INITRD_PATH=/initramfs-linux.img
CMDLINE=root=PARTUUID=${PARTUUID} rw quiet
EOF

echo "Limine успешно установлен и настроен."

# --- Драйверы для виртуалки ---
echo "Драйверы для виртуалки"
pacman -Sy --noconfirm xf86-video-vmware

# --- Графика и окружение ---
echo "Графика и окружение"
pacman -Sy --noconfirm xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman lxtask \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
pulseaudio-rtp pulseaudio-zeroconf xarchiver unrar unzip p7zip numlockx firefox rofi nitrogen i3-wm bash-completion

# Менеджер входа ly
echo "Менеджер входа ly"
pacman -Sy --noconfirm ly dbus
systemctl enable ly
systemctl enable dbus

# --- Yay (AUR helper) ---
echo "Yay (AUR helper)"
sudo -u $USERNAME bash -c "
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# --- Автозапуск XFCE ---
echo "Автозапуск XFCE"
echo "exec startxfce4" > /home/$USERNAME/.xinitrc
chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

EOF

# --- Финал ---
echo "Финал"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
