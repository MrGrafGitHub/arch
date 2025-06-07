#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
USERPASS="1234"
ROOTPASS="root"
DISK="/dev/sda"

# Разметка с ext4 /boot
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 300MiB   # /boot
parted -s "$DISK" mkpart primary ext4 300MiB 100%   # /

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

# Монтируем основную систему
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# --- Установка базовой системы ---
echo "Установка базовой системы"
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git bash-completion

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
echo "Установка Limine"

# Убедимся, что директория /boot существует
mkdir -p /boot

mkinitcpio -P

# Копируем файл загрузчика
cp /usr/share/limine/limine-bios.sys /boot/

# Проверка, что файл на месте
if [[ ! -f /boot/limine-bios.sys ]]; then
    echo "XXX Ошибка: limine-bios.sys НЕ найден в /boot!"
    echo "!!!  Загрузка не будет работать. Проверь копирование!"
    exit 1
fi

# Получаем UUID корневого раздела
UUID=\$(blkid -s UUID -o value ${DISK}2)

# Создаём конфиг Limine
cat > /boot/limine.cfg <<EOF
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
PROTOCOL=linux
KERNEL_PATH=/vmlinuz-linux
INITRD_PATH=/initramfs-linux.img
CMDLINE=root=UUID=\${UUID} rw quiet
EOF

# Устанавливаем Limine
limine bios-install $DISK

echo "Limine успешно установлен и настроен."

# --- Менеджер входа ly ---
pacman -Sy --noconfirm ly
systemctl enable ly



EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
