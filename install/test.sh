#!/bin/bash
set -euo pipefail

echo "🖥️ Starting Arch Linux installation for VIRTUAL MACHINE..."

# 1. Обновляем системное время (чтобы избежать проблем с сертификатами)
timedatectl set-ntp true

# 2. Разметка диска (для виртуалки — один диск /dev/vda, весь под одну партицию)
echo "⚙️ Partitioning /dev/vda..."
(
  echo g     # GPT
  echo n     # новая партиция
  echo 1     # номер 1
  echo       # старт — по умолчанию
  echo       # конец — по умолчанию (весь диск)
  echo w     # записать и выйти
) | fdisk /dev/vda

# 3. Форматируем в ext4
echo "⚙️ Formatting /dev/vda1 as ext4..."
mkfs.ext4 /dev/vda1

# 4. Монтируем
mount /dev/vda1 /mnt

# 5. Установка базовой системы
echo "⚙️ Installing base system..."
pacstrap /mnt base linux linux-firmware vim nano

# 6. Генерируем fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 7. Chroot и базовая настройка
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

echo '🛠 Installing and enabling NetworkManager...'
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager
"

# 8. Отмонтировать и перезагрузить
echo "✅ Installation finished. Unmounting and rebooting..."
umount -R /mnt
reboot
