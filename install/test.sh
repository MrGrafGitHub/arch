#!/bin/bash
set -e

# Подключаем интернет, обновляем часы
timedatectl set-ntp true

# Разметка диска и монтирование (пример для /dev/sda)
# Переделай под свою виртуалку если нужно
(
echo g # GPT
echo n # new partition
echo   # default partition number
echo   # default first sector
echo +20G # size 20Gb для root
echo w # write changes
) | fdisk /dev/sda

mkfs.ext4 /dev/sda1
mount /dev/sda1 /mnt

# Устанавливаем базовые пакеты + нужные из твоего списка
pacstrap /mnt base linux linux-firmware networkmanager \
  xfce4-netload-plugin xfce4-notifyd xfce4-panel xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin xfce4-xkb-plugin xfconf \
  thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman \
  lxtask \
  pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc pulseaudio-rtp pulseaudio-zeroconf \
  xarchiver unrar unzip p7zip \
  numlockx \
  i3 rofi nitrogen firefox ly limine

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -c "
  # Включаем networkmanager
  systemctl enable NetworkManager.service

  # Включаем ly менеджер входа
  systemctl enable ly.service

  # Устанавливаем limine загрузчик
  limine-install /dev/sda

  # Дополнительные настройки лимайн
  limine-install /dev/sda --syslinux-config

  # Создаем пользователя (пример)
  useradd -m -G wheel mrgraf
  echo 'mrgraf:password' | chpasswd
  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
"

echo "Установка завершена. Перезагрузи систему."
