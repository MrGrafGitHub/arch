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
xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel  dbus wget \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv \
pulseaudio-rtp pulseaudio-zeroconf i3 picom 

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


# Функция загрузки файла под пользователем, с проверкой
download_user_file() {
  local url="$1"
  local dest="$2"
  echo -e "\033[1;32m Загрузка $dest \033[0m"
  sudo -u "$USERNAME" wget -qO "$dest" "$url" || {
    echo -e "\033[1;31m Ошибка загрузки $url \033[0m"
    exit 1
  }
}

# Создаём каталоги для конфигов под пользователем
mkdir -p "$HOME_DIR/.config/i3"
mkdir -p "$HOME_DIR/.config/neofetch"
mkdir -p "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$HOME_DIR/.config/nitrogen"
mkdir -p "$HOME_DIR/Wallpapers"
mkdir -p "$HOME_DIR/.config/autostart"

# Загружаем конфиги под пользователем
download_user_file "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/i3/test/config" "$HOME_DIR/.config/i3/config"
download_user_file "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/i3/test/picom" "$HOME_DIR/.config/i3/picom.conf"
download_user_file "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf" "$HOME_DIR/.config/neofetch/config.conf"
download_user_file "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
download_user_file "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/assets/wallpaper.jpg" "$HOME_DIR/Wallpapers/wallpaper.jpg"

# Для PulseAudio файлы в /etc/pulse — нужна root-права
echo -e "\n\033[1;32m Добавление load-module module-device-manager в pulse \033[0m"
for FILE in /etc/pulse/default.pa /etc/pulse/system.pa; do
    if ! grep -q '^load-module module-device-manager' "$FILE"; then
        echo 'load-module module-device-manager' >> "$FILE"
    fi
done

# Распаковка тем — нужно от root, в нужные каталоги
echo -e "\033[1;32m Загрузка тем в /tmp \033[0m"
wget -qO /tmp/theme.tar.xz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Dracula-alt-style.tar.xz"
wget -qO /tmp/icons.tar.xz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/Mkos-Big-Sur.tar.xz"
wget -qO /tmp/cursors.tar.gz "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/theme/oreo-teal-cursors.tar.gz"

echo -e "\033[1;32m Распаковка тем \033[0m"
mkdir -p /usr/share/themes/custom-themes
mkdir -p /usr/share/icons/custom-cursors
mkdir -p /usr/share/icons

tar -xf /tmp/theme.tar.xz -C /usr/share/themes/custom-themes
tar -xf /tmp/icons.tar.xz -C /usr/share/icons/
tar -xzf /tmp/cursors.tar.gz -C /usr/share/icons/custom-cursors

# Проверяем права на домашние конфиги
echo -e "\033[1;32m Исправляем права на домашние конфиги \033[0m"
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config"
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/Wallpapers"

# Настройка nitrogen (под пользователем)
cat > "$HOME_DIR/.config/nitrogen/bg-saved.cfg" <<EOF
[xin_-1]
file=$HOME_DIR/Wallpapers/wallpaper.jpg
mode=4
bgcolor=#000000
EOF

chown "$USERNAME:$USERNAME" "$HOME_DIR/.config/nitrogen/bg-saved.cfg"

echo -e "\033[1;32m Загрузка и установка автозапуска i3 \033[0m"
cat > "$HOME_DIR/.config/autostart/i3.desktop" <<EOF
[Desktop Entry]
Encoding=UTF-8
Version=0.9.4
Type=Application
Name=i3
Comment=i3
Exec=i3
OnlyShowIn=XFCE;
RunHook=0
StartupNotify=false
Terminal=false
Hidden=false
EOF
chown "$USERNAME:$USERNAME" "$HOME_DIR/.config/autostart/i3.desktop"

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
yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch 
EOC

# Удаление временного правила sudo
rm -f /etc/sudoers.d/aur-temp


EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
