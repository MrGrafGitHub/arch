#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
USERPASS="1234"
HOME_DIR="/home/$USERNAME"
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
echo -e "\n\033[1;32m Установка базовой системы \033[0m"
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git \
xorg-server xorg-xinit  dbus wget \
xfconf xfce4-notifyd xfce4-settings \
network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv telegram-desktop \
pulseaudio-rtp pulseaudio-zeroconf i3 picom polybar kvantum-qt5 python-gobject python-gitdb pavucontrol arandr 

genfstab -U /mnt >> /mnt/etc/fstab

# --- Настройки внутри chroot ---
arch-chroot /mnt /bin/bash <<EOF_CHROOT

USERNAME="mrgraf"
USERPASS="1234"
HOME_DIR="/home/$USERNAME"
ROOTPASS="root"

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
echo -e "\n\033[1;32m Сеть \033[0m"
systemctl enable NetworkManager
systemctl enable dbus

# --- Пользователи ---
echo -e "\n\033[1;32m Пользователи \033[0m"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# --- Обновление ---
pacman -Syu --noconfirm

# --- СТАВИМ ЗАГРУЗЧИК Limine ---
echo -e "\n\033[1;32m СТАВИМ ЗАГРУЗЧИК Limine \033[0m"

# Убедимся, что есть директория /boot/limine
mkdir -p /boot/limine

# Создаём конфиг Limine
echo -e "\n\033[1;32m Создаём конфиг Limine \033[0m"
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
echo -e "\n\033[1;32m Копируем необходимые файлы Limine \033[0m"
cp /usr/share/limine/limine-bios.sys /boot/limine/
cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/

# Устанавливаем Limine
echo -e "\n\033[1;32m Устанавливаем Limine \033[0m"
limine bios-install $DISK

echo -e "\n\033[1;32mLimine успешно установлен и настроен!\033[0m"

# --- Менеджер входа ly ---
echo -e "\n\033[1;32m Менеджер входа ly \033[0m"
pacman -Sy --noconfirm ly
systemctl enable ly

# Создаём каталоги для конфигов под пользователем
mkdir -p "$HOME_DIR/.config/i3"
mkdir -p "$HOME_DIR/.config/neofetch"
mkdir -p "$HOME_DIR/.config/nitrogen"
mkdir -p "$HOME_DIR/.config/polybar"
mkdir -p "$HOME_DIR/Wallpapers"

# Загружаем конфиги под пользователем

# i3
echo -e "\033[1;32m Загрузка конфигов i3 \033[0m"
wget -q -O "/tmp/i3.zip" "https://github.com/MrGrafGitHub/arch/raw/main/configs/i3.zip" || { echo "Ошибка загрузки i3.zip"; exit 1; }
rm -rf /tmp/i3-tmp && mkdir -p /tmp/i3-tmp
unzip -oq /tmp/i3.zip -d /tmp/i3-tmp || { echo "Ошибка распаковки i3.zip"; exit 1; }
cp -rf /tmp/i3-tmp/i3/* "$HOME_DIR/.config/i3/"
chown -R $USERNAME:$USERNAME "$HOME_DIR/.config/i3"
find "$HOME_DIR/.config/i3" -type f -name "*.sh" -exec chmod +x {} \;

# polybar
echo -e "\033[1;32m Загрузка конфигов polybar \033[0m"
wget -q -O "/tmp/polybar.zip" "https://github.com/MrGrafGitHub/arch/raw/main/configs/polybar.zip" || { echo "Ошибка загрузки polybar.zip"; exit 1; }
rm -rf /tmp/polybar-tmp && mkdir -p /tmp/polybar-tmp
unzip -oq /tmp/polybar.zip -d /tmp/polybar-tmp || { echo "Ошибка распаковки polybar.zip"; exit 1; }
cp -rf /tmp/polybar-tmp/polybar/* "$HOME_DIR/.config/polybar/"
chown -R $USERNAME:$USERNAME "$HOME_DIR/.config/polybar"
find "$HOME_DIR/.config/polybar" -type f -name "*.sh" -exec chmod +x {} \;

echo -e "\033[1;32m Загрузка и установка системных шрифтов \033[0m"
wget -q -O /tmp/fonts.zip "https://github.com/MrGrafGitHub/arch/raw/main/font/fonts.zip" || { echo "Ошибка загрузки fonts.zip"; exit 1; }

# Временная распаковка
rm -rf /tmp/fonts-tmp && mkdir -p /tmp/fonts-tmp
unzip -oq /tmp/fonts.zip -d /tmp/fonts-tmp || { echo "Ошибка распаковки fonts.zip"; exit 1; }

# Копируем все файлы напрямую в /usr/share/fonts (без вложенной папки)
cp -rf /tmp/fonts-tmp/* /usr/share/fonts/ || { echo "Ошибка копирования шрифтов"; exit 1; }

# Удаляем временные файлы
rm -rf /tmp/fonts.zip /tmp/fonts-tmp

# Обновляем кеш шрифтов
echo -e "\033[1;34m Обновление кеша шрифтов... \033[0m"
fc-cache -fv > /dev/null

echo -e "\033[1;32m Загрузка $HOME_DIR/.config/neofetch/config.conf \033[0m"
wget -q -O "$HOME_DIR/.config/neofetch/config.conf" "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf" || { echo "Ошибка загрузки neofetch config.conf"; exit 1; }
chown $USERNAME:$USERNAME "$HOME_DIR/.config/neofetch/config.conf"

echo -e "\033[1;32m Загрузка $HOME_DIR/Wallpapers/wallpaper.jpg \033[0m"
wget -q -O "$HOME_DIR/Wallpapers/wallpaper.jpg" "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/assets/wallpaper.jpg" || { echo "Ошибка загрузки wallpaper.jpg"; exit 1; }
chown $USERNAME:$USERNAME "$HOME_DIR/Wallpapers/wallpaper.jpg"


# Распаковка тем — нужно от root, в нужные каталоги
echo -e "\033[1;32m Загрузка тем в /tmp \033[0m"
wget -q -O /tmp/theme.tar.xz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Dracula-alt-style.tar.xz"
wget -q -O /tmp/icons.tar.xz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Mkos-Big-Sur.tar.xz"
wget -q -O /tmp/cursors.tar.gz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/oreo-teal-cursors.tar.gz"

# Распаковка тем
echo -e "\033[1;32m Распаковка тем \033[0m"
mkdir -p /usr/share/themes /usr/share/icons

# Theme
rm -rf /tmp/theme-tmp && mkdir -p /tmp/theme-tmp
tar -xf /tmp/theme.tar.xz -C /tmp/theme-tmp
cp -rf /tmp/theme-tmp/* /usr/share/themes/

# Icons
rm -rf /tmp/icons-tmp && mkdir -p /tmp/icons-tmp
tar -xf /tmp/icons.tar.xz -C /tmp/icons-tmp
cp -rf /tmp/icons-tmp/* /usr/share/icons/

# Cursors
rm -rf /tmp/cursors-tmp && mkdir -p /tmp/cursors-tmp
tar -xzf /tmp/cursors.tar.gz -C /tmp/cursors-tmp
cp -rf /tmp/cursors-tmp/* /usr/share/icons/

# Проверяем права на домашние конфиги
echo -e "\033[1;32m Исправляем права на домашние конфиги \033[0m"
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config"
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/Wallpapers"

# Настройка nitrogen (под пользователем)
cat > "$HOME_DIR/.config/nitrogen/bg-saved.cfg" <<EOF
[xin_-1]
file=${HOME_DIR}/Wallpapers/wallpaper.jpg
mode=4
bgcolor=#000000
EOF

chown "$USERNAME:$USERNAME" "$HOME_DIR/.config/nitrogen/bg-saved.cfg"

echo -e "\033[1;34m Настройка завершена \033[0m"


# --- Установка yay и AUR пакетов от пользователя $USERNAME ---
echo -e "\n\033[1;32m Установка yay и AUR пакетов от пользователя \033[0m"


# Временное предоставление пароля для sudo без запроса
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg" > /etc/sudoers.d/aur-temp
chmod 0440 /etc/sudoers.d/aur-temp

# Запуск от пользователя
echo -e "\n\033[1;32m Запуск от пользователя \033[0m"
sudo -u "$USERNAME" bash <<EOC
set -e  # Завершить выполнение при ошибке

cd "/home/$USERNAME"

# Проверка и установка yay
echo -e "\n\033[1;32m Проверка и установка yay \033[0m"
if ! command -v yay >/dev/null 2>&1; then
    echo "[*] Клонирование yay из AUR..."
    git clone https://aur.archlinux.org/yay.git ~/yay
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
fi

# Установка нужных AUR пакетов
echo -e "\n\033[1;32m [*] Установка AUR пакетов... \033[0m"
yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch sublime-text-4 
EOC

# Удаление временного правила sudo
rm -f /etc/sudoers.d/aur-temp


EOF_CHROOT

# --- Финал ---
echo -e "\033[1;34m Финал: размонтирование и завершение \033[0m"
umount -R /mnt
echo -e "\033[1;34m Установка завершена. Можно перезагружаться! \033[0m"
