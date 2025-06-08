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
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git xf86-video-vmware \
xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel  dbus \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv neofetch \
pulseaudio-rtp pulseaudio-zeroconf i3-wm picom 

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


# Configs
RAW_I3_CFG="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/i3/test/config"
RAW_PICOM_CFG="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/i3/test/picom"
RAW_NEOFETCH_CFG="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf"
RAW_XFCE_CFG="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
RAW_PULSE_DEFAULT="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/pulse/default.pa"
RAW_PULSE_SYSTEM="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/pulse/system.pa"

# Themes
RAW_THEME="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Dracula-alt-style.tar.xz"
RAW_THEME_ICON="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Mkos-Big-Sur.tar.xz"
RAW_THEME_CURSOR="https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/oreo-teal-cursors.tar.gz"

# Wallpaper
WALL_DIR="$HOME_DIR/Wallpapers"
WALL_URL="https://raw.githubusercontent.com/MrGrafGitHub/arch/assets/wallpaper.jpg"
WALL_FILE="$WALL_DIR/wallpaper.jpg"


# Включаем multilib и цвет, не затрагивая остальное
echo -e "\n\033[1;32m Включаем multilib \033[0m"
sed -i '/^\[multilib\]/,/^Include/ s/^#//' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

#Добавление строки в /etc/environment
echo -e "\n\033[1;32m Добавление строки в /etc/environment \033[0m"
grep -qxF 'QT_QPA_PLATFORMTHEME=qt5ct' /etc/environment || echo 'QT_QPA_PLATFORMTHEME=qt5ct' >> /etc/environment

#Добавление load-module module-device-manager в /etc/pulse/default.pa и system.pa
echo -e "\n\033[1;32m Добавление load-module module-device-manager в pulse \033[0m"
for FILE in /etc/pulse/default.pa /etc/pulse/system.pa; do
    if ! grep -q '^load-module module-device-manager' "$FILE"; then
        echo 'load-module module-device-manager' >> "$FILE"
    fi
done

USERNAME="mrgraf"
HOME_DIR="/home/$USERNAME"

# Directories
echo -e "\n\033[1;32m Создание директорий для конфигов и тем \033[0m"
mkdir -p "$HOME_DIR/.config/i3"
mkdir -p "$HOME_DIR/.config/neofetch"
mkdir -p "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p /usr/share/icons/custom-cursors
mkdir -p /usr/share/themes/custom-themes

# Config downloads
echo -e "\n\033[1;32m Загрузка конфигов \033[0m"
curl -Lo "$HOME_DIR/.config/i3/config" "$RAW_I3_CFG"
curl -Lo "$HOME_DIR/.config/i3/picom.conf" "$RAW_PICOM_CFG"
curl -Lo "$HOME_DIR/.config/neofetch/config.conf" "$RAW_NEOFETCH_CFG"
curl -Lo "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "$RAW_XFCE_CFG"
curl -Lo /etc/pulse/default.pa "$RAW_PULSE_DEFAULT"
curl -Lo /etc/pulse/system.pa "$RAW_PULSE_SYSTEM"

# Theme downloads and extraction
echo -e "\n\033[1;32m Загрузка и распаковка тем \033[0m"
curl -Lo /tmp/theme.tar.xz "$RAW_THEME"
curl -Lo /tmp/icons.tar.xz "$RAW_THEME_ICON"
curl -Lo /tmp/cursors.tar.gz "$RAW_THEME_CURSOR"

echo -e "\n\033[1;32m Установка тем \033[0m"
tar -xf /tmp/theme.tar.xz -C /usr/share/themes/custom-themes
tar -xf /tmp/icons.tar.xz -C /usr/share/icons/
tar -xzf /tmp/cursors.tar.gz -C /usr/share/icons/custom-cursors

# Set ownership back to user
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config"

# Создать папку и скачать обойну
mkdir -p "$WALL_DIR"
curl -Lo "$WALL_FILE" "$WALL_URL"

# Настроить nitrogen
mkdir -p "$HOME_DIR/.config/nitrogen"

cat > "$HOME_DIR/.config/nitrogen/bg-saved.cfg" <<EOF
[xin_-1]
file=$WALL_FILE
mode=4
bgcolor=#000000
EOF

# Права
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config/nitrogen"


# --- Установка yay и AUR пакетов от пользователя $USERNAME ---
echo -e "\n\033[1;32m Установка yay и AUR пакетов от пользователя \033[0m"


# Временное предоставление пароля для sudo без запроса
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg" > /etc/sudoers.d/aur-temp
chmod 0440 /etc/sudoers.d/aur-temp

# Запуск от пользователя
echo -e "\n\033[1;32m Запуск от пользователя \033[0m"
sudo -u "$USERNAME" bash <<'EOC'
set -e  # Завершить выполнение при ошибке

cd "$HOME"

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
yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling
EOC

# Удаление временного правила sudo
rm -f /etc/sudoers.d/aur-temp


EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
