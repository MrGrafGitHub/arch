#!/bin/bash
set -e

if [ -d /sys/firmware/efi ]; then
    MODE="2"  # UEFI
    echo -e "\033[1;32mОбнаружен режим UEFI. Устанавливаем как UEFI.\033[0m"
else
    MODE="1"  # BIOS
    echo -e "\033[1;33mОбнаружен режим BIOS (Legacy). Устанавливаем как BIOS.\033[0m"
fi

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
    echo -e "\033[1;31mОшибка: нужно выбрать 1 или 2.\033[0m"
    exit 1
fi

# --- Определение дисков ---
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

### --- Разметка SSD в зависимости от режима ---
if [[ "$MODE" == "1" ]]; then
    echo -e "\n\033[1;32m=== Размечаем и форматируем SSD (BIOS+GPT) ===\033[0m"
    parted -s "$SSD" mklabel gpt
    parted -s "$SSD" mkpart primary 1MiB 2MiB
    parted -s "$SSD" set 1 bios_grub on
    parted -s "$SSD" mkpart primary fat32 2MiB 302MiB
    parted -s "$SSD" mkpart primary ext4 302MiB 100%
    mkfs.fat -F32 -n BOOT "${SSD}2"
    mkfs.ext4 -L ROOT "${SSD}3"
    ROOT_PART="${SSD}3"
    BOOT_PART="${SSD}2"
else
    echo -e "\n\033[1;32m=== Размечаем и форматируем SSD (UEFI+GPT) ===\033[0m"
    parted -s "$SSD" mklabel gpt
    parted -s "$SSD" mkpart primary fat32 1MiB 301MiB
    parted -s "$SSD" set 1 esp on
    parted -s "$SSD" mkpart primary ext4 301MiB 100%
    mkfs.fat -F32 -n EFI "${SSD}1"
    mkfs.ext4 -L ROOT "${SSD}2"
    ROOT_PART="${SSD}2"
    BOOT_PART="${SSD}1"
fi

### --- Монтирование ---
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

echo -e "\n\033[1;32m=== Размечаем и форматируем HOME ===\033[0m"
parted -s "$HDD_HOME" mklabel gpt
parted -s "$HDD_HOME" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L HOME "${HDD_HOME}1"
mkdir -p /mnt/home
mount "${HDD_HOME}1" /mnt/home

echo -e "\n\033[1;32m=== Размечаем и форматируем GAMES ===\033[0m"
parted -s "$HDD_GAMES" mklabel gpt
parted -s "$HDD_GAMES" mkpart primary ext4 1MiB 100%
mkfs.ext4 -L GAMES "${HDD_GAMES}1"
mkdir -p /mnt/games
mount "${HDD_GAMES}1" /mnt/games

echo -e "\n\033[1;32m=== Монтируем 4ТБ NTFS ===\033[0m"
mkdir -p /mnt/media
if ! blkid -s LABEL -o value "$HDD_MEDIA" | grep -q .; then
    echo "Присваиваем метку MEDIA для $HDD_MEDIA"
    ntfslabel "$HDD_MEDIA" MEDIA
fi
mount -t ntfs-3g "$HDD_MEDIA" /mnt/media -o uid=1000,gid=1000,noatime

### --- FSTAB ---
echo -e "\n\033[1;32m=== Генерируем fstab ===\033[0m"
FSTAB="/mnt/etc/fstab"
mkdir -p /mnt/etc
: > "$FSTAB"

add_fstab_entry() {
    echo "LABEL=$1    $2    $3    $4    $5 $6" >> "$FSTAB"
}

if [[ "$MODE" == "1" ]]; then
    add_fstab_entry "ROOT" "/" "ext4" "defaults,noatime" 0 1
    add_fstab_entry "BOOT" "/boot" "vfat" "defaults" 0 2
else
    add_fstab_entry "ROOT" "/" "ext4" "defaults,noatime" 0 1
    add_fstab_entry "EFI" "/boot" "vfat" "defaults" 0 2
fi
add_fstab_entry "HOME" "/home" "ext4" "defaults,noatime" 0 2
add_fstab_entry "GAMES" "/games" "ext4" "defaults,noatime" 0 2
add_fstab_entry "MEDIA" "/media" "ntfs-3g" "uid=1000,gid=1000,defaults,noatime" 0 0

echo -e "\n\033[1;33mСгенерированный fstab:\033[0m"
cat "$FSTAB"

# --- Установка системы ---
echo -e "\n\033[1;32m=== Устанавливаем базовую систему ===\033[0m"
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

export SSD MODE

arch-chroot /mnt /bin/bash <<'EOF_CHROOT'
SSD="'"$SSD"'"
MODE="'"$MODE"'"

USERNAME="mrgraf"
HOSTNAME="arch"

# --- Настройка пользователя ---
echo -n "Введите пароль для root: "
read -s ROOTPASS
echo
echo "root:${ROOTPASS}" | chpasswd

useradd -m -G wheel "$USERNAME"
echo -n "Введите пароль для пользователя $USERNAME: "
read -s USERPASS
echo
echo "${USERNAME}:${USERPASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

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

pacman -Syu --noconfirm

# --- Устанавливаем Limine ---
mkdir -p /boot/limine
cat > /boot/limine/limine.conf <<EOF
/+Arch Linux
comment: loader linux

//Linux
protocol: linux
path: boot():/vmlinuz-linux
cmdline: root=LABEL=ROOT rw quiet
module_path: boot():/initramfs-linux.img
EOF

if [[ "$MODE" == "1" ]]; then
    cp /usr/share/limine/limine-bios.sys /boot/limine/
    cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
    cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/
    limine bios-install "$SSD"
else
    limine-install /boot
fi

# --- Менеджер входа ---
pacman -Sy --noconfirm ly
systemctl enable ly

mkinitcpio -P

EOF_CHROOT

# --- Финал ---
echo -e "\033[1;34m Размонтируем и завершаем установку \033[0m"
umount -R /mnt
echo -e "\033[1;34m Готово! Перезагрузи систему. \033[0m"
