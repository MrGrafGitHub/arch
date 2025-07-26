#!/bin/bash
set -e

# --- Определяем режим загрузки ---
if [ -d /sys/firmware/efi ]; then
    MODE="UEFI"
    echo -e "\033[1;32mОбнаружен режим UEFI. Устанавливаем как UEFI.\033[0m"
else
    MODE="BIOS"
    echo -e "\033[1;33mОбнаружен режим BIOS (Legacy). Устанавливаем как BIOS.\033[0m"
fi

# --- Определяем диски ---
echo -e "\n\033[1;32m=== Определяем диски ===\033[0m"
mapfile -t DISKS < <(lsblk -dn -o NAME,SIZE -b | awk '{print "/dev/"$1 " " $2}')

SSD=""
HDD_HOME=""
HDD_GAMES=""
HDD_MEDIA=""

for entry in "${DISKS[@]}"; do
    DEV=$(echo "$entry" | awk '{print $1}')
    SIZE=$(echo "$entry" | awk '{print $2}')
    USED=$(lsblk -dn -o FSUSED "$DEV" | tr -d '[:space:]')

    if [ "$SIZE" -lt $((500*1024*1024*1024)) ]; then
        SSD="$DEV"
    elif [ "$SIZE" -gt $((500*1024*1024*1024)) ] && [ "$SIZE" -lt $((2*1024*1024*1024*1024)) ]; then
        if [ -z "$USED" ] || [ "$USED" = "0" ] || [ "$USED" = "0B" ]; then
            if [ -z "$HDD_HOME" ]; then
                HDD_HOME="$DEV"
            else
                HDD_GAMES="$DEV"
            fi
        else
            HDD_GAMES="$DEV"
        fi
    elif [ "$SIZE" -gt $((2*1024*1024*1024*1024)) ]; then
        HDD_MEDIA="$DEV"
    fi
done

if [[ -z "$SSD" || -z "$HDD_HOME" || -z "$HDD_GAMES" || -z "$HDD_MEDIA" ]]; then
    echo -e "\033[1;31mОшибка: не удалось определить все диски. Проверь разметку!\033[0m"
    exit 1
fi

echo "SSD: $SSD"
echo "HOME: $HDD_HOME"
echo "GAMES: $HDD_GAMES"
echo "MEDIA (NTFS): $HDD_MEDIA"

# --- Разметка SSD ---
if [[ "$MODE" == "BIOS" ]]; then
    echo -e "\n\033[1;32m=== Размечаем SSD (BIOS+GPT) ===\033[0m"
    parted -s "$SSD" mklabel gpt
    parted -s "$SSD" mkpart primary 1MiB 2MiB
    parted -s "$SSD" set 1 bios_grub on
    parted -s "$SSD" mkpart primary fat32 2MiB 302MiB
    parted -s "$SSD" mkpart primary ext4 302MiB 100%
    BOOT_PART="${SSD}2"
    ROOT_PART="${SSD}3"
else
    echo -e "\n\033[1;32m=== Размечаем SSD (UEFI+GPT) ===\033[0m"
    parted -s "$SSD" mklabel gpt
    parted -s "$SSD" mkpart primary fat32 1MiB 301MiB
    parted -s "$SSD" set 1 esp on
    parted -s "$SSD" mkpart primary ext4 301MiB 100%
    BOOT_PART="${SSD}1"
    ROOT_PART="${SSD}2"
fi

# Проверка что разделы созданы
lsblk "$SSD" | grep -q "$(basename $BOOT_PART)" || { echo "Ошибка: раздел BOOT не создан"; exit 1; }
lsblk "$SSD" | grep -q "$(basename $ROOT_PART)" || { echo "Ошибка: раздел ROOT не создан"; exit 1; }

# --- Форматирование ---
mkfs.fat -F32 -n BOOT "$BOOT_PART"
mkfs.ext4 -L ROOT "$ROOT_PART"

# --- Монтирование ---
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# --- HOME ---
echo -e "\n\033[1;32m=== Размечаем HOME ===\033[0m"
parted -s "$HDD_HOME" mklabel gpt
parted -s "$HDD_HOME" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L HOME "${HDD_HOME}1"
mkdir -p /mnt/home
mount "${HDD_HOME}1" /mnt/home

# --- GAMES ---
echo -e "\n\033[1;32m=== Размечаем GAMES ===\033[0m"
parted -s "$HDD_GAMES" mklabel gpt
parted -s "$HDD_GAMES" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L GAMES "${HDD_GAMES}1"
mkdir -p /mnt/games
mount "${HDD_GAMES}1" /mnt/games

# --- MEDIA ---
echo -e "\n\033[1;32m=== Монтируем 4ТБ NTFS ===\033[0m"
mkdir -p /mnt/media
if ! blkid -s LABEL -o value "$HDD_MEDIA" | grep -q .; then
    ntfslabel "$HDD_MEDIA" MEDIA
fi
mount -t ntfs-3g "$HDD_MEDIA" /mnt/media -o uid=1000,gid=1000,noatime

# --- FSTAB ---
echo -e "\n\033[1;32m=== Генерируем fstab ===\033[0m"
FSTAB="/mnt/etc/fstab"
mkdir -p /mnt/etc
: > "$FSTAB"

add_fstab_entry() {
    echo "LABEL=$1    $2    $3    $4    $5 $6" >> "$FSTAB"
}
add_fstab_entry "ROOT" "/" "ext4" "defaults,noatime" 0 1
add_fstab_entry "BOOT" "/boot" "vfat" "defaults" 0 2
add_fstab_entry "HOME" "/home" "ext4" "defaults,noatime" 0 2
add_fstab_entry "GAMES" "/games" "ext4" "defaults,noatime" 0 2
add_fstab_entry "MEDIA" "/media" "ntfs-3g" "uid=1000,gid=1000,defaults,noatime" 0 0

cat "$FSTAB"

# --- Установка системы ---
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git \
nvidia nvidia-settings nvidia-utils \
xorg-server xorg-xinit dbus wget \
xfconf xfce4-notifyd xfce4-settings \
network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv telegram-desktop \
pulseaudio-rtp pulseaudio-zeroconf i3 picom polybar kvantum-qt5 python-gobject python-gitdb pavucontrol arandr

export SSD MODE
arch-chroot /mnt /bin/bash <<'EOF_CHROOT'
SSD="'"$SSD"'"
MODE="'"$MODE"'"

USERNAME="mrgraf"
HOSTNAME="arch"
HOME_DIR="/home/$USERNAME"

# --- Базовые настройки ---
echo -n "Введите пароль для root: "; read -s ROOTPASS; echo
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel "$USERNAME"
echo -n "Введите пароль для пользователя $USERNAME: "; read -s USERPASS; echo
echo "${USERNAME}:${USERPASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

systemctl enable NetworkManager
systemctl enable dbus
pacman -Syu --noconfirm

# --- Limine ---
mkdir -p /boot/limine
cat > /boot/limine/limine.conf <<EOF
/+Arch Linux
comment: loader linux
protocol: linux
path: boot():/vmlinuz-linux
cmdline: root=LABEL=ROOT rw quiet
module_path: boot():/initramfs-linux.img
EOF

if [[ "$MODE" == "BIOS" ]]; then
    cp /usr/share/limine/limine-bios.sys /boot/limine/
    cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
    cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/
    limine bios-install "$SSD"
else
    limine-install --efi-directory=/boot
fi

pacman -Sy --noconfirm ly
systemctl enable ly

### --- ДОБАВЛЕННЫЙ БЛОК: Конфиги, шрифты, темы и AUR --- ###

# Создаём каталоги для конфигов под пользователем
mkdir -p "$HOME_DIR/.config/i3" "$HOME_DIR/.config/neofetch" "$HOME_DIR/.config/nitrogen" "$HOME_DIR/.config/polybar" "$HOME_DIR/Wallpapers"

# i3 configs
echo -e "\033[1;32m Загрузка конфигов i3 \033[0m"
wget -q -O "/tmp/i3.zip" "https://github.com/mrgraf-src/arch/raw/main/configs/i3.zip" || { echo "Ошибка загрузки i3.zip"; exit 1; }
unzip -oq /tmp/i3.zip -d /tmp/i3-tmp || { echo "Ошибка распаковки i3.zip"; exit 1; }
cp -rf /tmp/i3-tmp/i3/* "$HOME_DIR/.config/i3/"
chown -R $USERNAME:$USERNAME "$HOME_DIR/.config/i3"
find "$HOME_DIR/.config/i3" -type f -name "*.sh" -exec chmod +x {} \;

# polybar configs
echo -e "\033[1;32m Загрузка конфигов polybar \033[0m"
wget -q -O "/tmp/polybar.zip" "https://github.com/mrgraf-src/arch/raw/main/configs/polybar.zip" || { echo "Ошибка загрузки polybar.zip"; exit 1; }
unzip -oq /tmp/polybar.zip -d /tmp/polybar-tmp || { echo "Ошибка распаковки polybar.zip"; exit 1; }
cp -rf /tmp/polybar-tmp/polybar/* "$HOME_DIR/.config/polybar/"
chown -R $USERNAME:$USERNAME "$HOME_DIR/.config/polybar"
find "$HOME_DIR/.config/polybar" -type f -name "*.sh" -exec chmod +x {} \;

# Fonts
echo -e "\033[1;32m Загрузка и установка системных шрифтов \033[0m"
wget -q -O /tmp/fonts.zip "https://github.com/mrgraf-src/arch/raw/main/font/fonts.zip" || { echo "Ошибка загрузки fonts.zip"; exit 1; }
unzip -oq /tmp/fonts.zip -d /tmp/fonts-tmp || { echo "Ошибка распаковки fonts.zip"; exit 1; }
cp -rf /tmp/fonts-tmp/* /usr/share/fonts/ || { echo "Ошибка копирования шрифтов"; exit 1; }
fc-cache -fv > /dev/null

# neofetch config
wget -q -O "$HOME_DIR/.config/neofetch/config.conf" "https://raw.githubusercontent.com/mrgraf-src/arch/main/configs/neofetch/config.conf" || { echo "Ошибка загрузки neofetch config.conf"; exit 1; }
chown $USERNAME:$USERNAME "$HOME_DIR/.config/neofetch/config.conf"

# wallpaper
wget -q -O "$HOME_DIR/Wallpapers/wallpaper.jpg" "https://raw.githubusercontent.com/mrgraf-src/arch/main/assets/wallpaper.jpg" || { echo "Ошибка загрузки wallpaper.jpg"; exit 1; }
chown $USERNAME:$USERNAME "$HOME_DIR/Wallpapers/wallpaper.jpg"

# themes & icons
wget -q -O /tmp/theme.tar.xz "https://raw.githubusercontent.com/mrgraf-src/arch/main/theme/Dracula-alt-style.tar.xz"
wget -q -O /tmp/icons.tar.xz "https://raw.githubusercontent.com/mrgraf-src/arch/main/theme/Mkos-Big-Sur.tar.xz"
wget -q -O /tmp/cursors.tar.gz "https://raw.githubusercontent.com/mrgraf-src/arch/main/theme/oreo-teal-cursors.tar.gz"
mkdir -p /usr/share/themes /usr/share/icons
tar -xf /tmp/theme.tar.xz -C /usr/share/themes
tar -xf /tmp/icons.tar.xz -C /usr/share/icons
tar -xzf /tmp/cursors.tar.gz -C /usr/share/icons

# nitrogen config
cat > "$HOME_DIR/.config/nitrogen/bg-saved.cfg" <<EOF
[xin_-1]
file=${HOME_DIR}/Wallpapers/wallpaper.jpg
mode=4
bgcolor=#000000
EOF
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.config" "$HOME_DIR/Wallpapers"

# --- Установка yay и AUR пакетов ---
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg" > /etc/sudoers.d/aur-temp
chmod 0440 /etc/sudoers.d/aur-temp

sudo -u "$USERNAME" bash <<EOC
set -e
cd "/home/$USERNAME"
if ! command -v yay >/dev/null 2>&1; then
    git clone https://aur.archlinux.org/yay.git ~/yay
    cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay
fi
yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch sublime-text-4 
EOC
rm -f /etc/sudoers.d/aur-temp

### --- КОНЕЦ ДОБАВЛЕННОГО БЛОКА --- ###

mkinitcpio -P
EOF_CHROOT

umount -R /mnt
echo -e "\033[1;34mУстановка завершена. Перезагрузи систему.\033[0m"
