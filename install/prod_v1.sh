#!/bin/bash
set -e

# --- Настройки ---
echo -e "\n\033[1;32m=== Определяем диски ===\033[0m"

# Получаем список дисков с размерами
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

# Проверка что все диски найдены
if [[ -z "$SSD" || -z "$HDD_HOME" || -z "$HDD_GAMES" || -z "$HDD_MEDIA" ]]; then
    echo -e "\033[1;31mОшибка: не удалось определить все диски. Проверь разметку!\033[0m"
    exit 1
fi

echo "SSD: $SSD"
echo "HOME: $HDD_HOME"
echo "GAMES: $HDD_GAMES"
echo "MEDIA (NTFS): $HDD_MEDIA"

### --- Разметка и форматирование (BIOS+GPT) ---
echo -e "\n\033[1;32m=== Размечаем и форматируем SSD (BIOS+GPT) ===\033[0m"
parted -s "$SSD" mklabel gpt
parted -s "$SSD" mkpart primary 1MiB 2MiB
parted -s "$SSD" set 1 bios_grub on
parted -s "$SSD" mkpart primary fat32 2MiB 302MiB
parted -s "$SSD" mkpart primary ext4 302MiB 100%
mkfs.fat -F32 -n BOOT "${SSD}2"
mkfs.ext4 -L ROOT "${SSD}3"

mount "${SSD}3" /mnt
mkdir -p /mnt/boot
mount "${SSD}2" /mnt/boot


echo -e "\n\033[1;32m=== Размечаем и форматируем HOME ===\033[0m"
parted -s "$HDD_HOME" mklabel gpt
parted -s "$HDD_HOME" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L HOME "${HDD_HOME}1"

echo -e "\n\033[1;32m=== Размечаем и форматируем GAMES ===\033[0m"
parted -s "$HDD_GAMES" mklabel gpt
parted -s "$HDD_GAMES" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L GAMES "${HDD_GAMES}1"

### --- Монтирование ---
echo -e "\n\033[1;32m=== Монтируем систему ===\033[0m"
mount "${SSD}2" /mnt
mkdir -p /mnt/boot
mount "${SSD}1" /mnt/boot

mkdir -p /mnt/home
mount "${HDD_HOME}1" /mnt/home

mkdir -p /mnt/games
mount "${HDD_GAMES}1" /mnt/games

echo -e "\n\033[1;32m=== Монтируем 4ТБ NTFS ===\033[0m"
mkdir -p /mnt/media
# Присваиваем метку если нет
if ! blkid -s LABEL -o value "$HDD_MEDIA" | grep -q .; then
    echo "Присваиваем метку MEDIA для $HDD_MEDIA"
    ntfslabel "$HDD_MEDIA" MEDIA
fi
mount -t ntfs-3g "$HDD_MEDIA" /mnt/media -o uid=1000,gid=1000,noatime

### --- FSTAB (LABEL) ---
echo -e "\n\033[1;32m=== Генерируем fstab (LABEL) ===\033[0m"
FSTAB="/mnt/etc/fstab"
mkdir -p /mnt/etc
: > "$FSTAB"

add_fstab_entry() {
    local label="$1"
    local mountpoint="$2"
    local fstype="$3"
    local opts="$4"
    local dump="$5"
    local pass="$6"
    echo "LABEL=$label    $mountpoint    $fstype    $opts    $dump $pass" >> "$FSTAB"
}

add_fstab_entry "ROOT"   "/"       "ext4"  "defaults,noatime"    0 1
add_fstab_entry "BOOT"   "/boot"   "vfat"  "defaults"            0 2
add_fstab_entry "HOME"   "/home"   "ext4"  "defaults,noatime"    0 2
add_fstab_entry "GAMES"  "/games"  "ext4"  "defaults,noatime"    0 2
add_fstab_entry "MEDIA"  "/media"  "ntfs-3g" "uid=1000,gid=1000,defaults,noatime" 0 0

echo -e "\n\033[1;33mСгенерированный fstab:\033[0m"
cat "$FSTAB"

# --- Установка базовой системы ---
echo -e "\n\033[1;32m Установка базовой системы \033[0m"
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git \
nvidia nvidia-settings nvidia-utils  \
xorg-server xorg-xinit dbus wget \
xfconf xfce4-notifyd xfce4-settings \
network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv telegram-desktop \
pulseaudio-rtp pulseaudio-zeroconf i3 picom polybar kvantum-qt5 python-gobject python-gitdb pavucontrol arandr 

export SSD
# --- Настройки внутри chroot ---
arch-chroot /mnt /bin/bash <<'EOF_CHROOT'
SSD="'"$SSD"'"

USERNAME="mrgraf"
HOME_DIR="/home/$USERNAME"
HOSTNAME="arch"

# --- Пользователи ---
echo -e "\n\033[1;32m Настройка пользователей \033[0m"

# Запрос пароля для root
echo -n "Введите пароль для root: "
read -s ROOTPASS
echo
echo "root:${ROOTPASS}" | chpasswd

# Создание пользователя
useradd -m -G wheel "$USERNAME"

# Запрос пароля для пользователя
echo -n "Введите пароль для пользователя $USERNAME: "
read -s USERPASS
echo
echo "${USERNAME}:${USERPASS}" | chpasswd

# Разрешаем группе wheel использовать sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

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
cmdline: root=LABEL=ROOT rw quiet
module_path: boot():/initramfs-linux.img
EOF

# Копируем необходимые файлы
echo -e "\n\033[1;32m Копируем необходимые файлы Limine \033[0m"
cp /usr/share/limine/limine-bios.sys /boot/limine/
cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/

# Устанавливаем Limine
echo -e "\n\033[1;32m Устанавливаем Limine \033[0m"
limine bios-install "$SSD"

echo -e "\n\033[1;32mLimine успешно установлен и настроен!\033[0m"

# --- Менеджер входа ly ---
echo -e "\n\033[1;32m Менеджер входа ly \033[0m"
pacman -Sy --noconfirm ly
systemctl enable ly

# (Остальной блок с конфигами, шрифтами, AUR — без изменений)

EOF_CHROOT

# --- Финал ---
echo -e "\033[1;34m Финал: размонтирование и завершение \033[0m"
umount -R /mnt
echo -e "\033[1;34m Установка завершена. Можно перезагружаться! \033[0m"
