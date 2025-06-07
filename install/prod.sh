curl -O https://raw.githubusercontent.com/MrGrafGitHub/arch/main/install/???.sh

chmod +x test.sh

./test.sh


это черновой вариант
Нужно добавить дополнительно ещё несколько дисков
автоматический перенос домашней директории на другой диск, либо изначально там формировать его
тем самым отдавая линуксу ссд
автомонитирование в fstab ntfs диска и второго который будет ext4
так же добавить подгрузку своей конфигурации i3 
и конфигурации других приложений.
так же добавить подгрузку тем сразу в систему.

добавить установку приложений из аура после всех манипуляций, чтоб сам быстро поставил


добавить в chroot-скрипт прямо перед обновлением пакетов
перед строкой

-pacman -Syu --noconfirm-

# Включаем multilib и цвет, не затрагивая остальное
sed -i '/^\[multilib\]/,/^Include/ s/^#//' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf





USER="mrgraf"
HOME_DIR="/home/$USER"
REPO_RAW_BASE="https://raw.githubusercontent.com/yourusername/yourrepo/main/configs"

# Создать нужные директории
mkdir -p "$HOME_DIR/.config/xfce4/panel"
mkdir -p "$HOME_DIR/.config/neofetch"
sudo mkdir -p /etc/pulse
sudo mkdir -p /usr/share/icons/custom-cursors
sudo mkdir -p /usr/share/themes/custom-themes

# Скачать конфиги
curl -o "$HOME_DIR/.config/xfce4/panel/xfce4-panel.xml" "$REPO_RAW_BASE/xfce4-panel.xml"
curl -o "$HOME_DIR/.config/neofetch/config.conf" "$REPO_RAW_BASE/neofetch.conf"
sudo curl -o /etc/pulse/default.pa "$REPO_RAW_BASE/pulse/default.pa"
sudo curl -o /etc/pulse/system.pa "$REPO_RAW_BASE/pulse/system.pa"
sudo curl -o /etc/environment "$REPO_RAW_BASE/environment"
sudo curl -o /etc/fstab "$REPO_RAW_BASE/fstab"

# Темы, иконки и курсоры (пример — архивы)
curl -L -o /tmp/icons.tar.gz "$REPO_RAW_BASE/icons.tar.gz"
curl -L -o /tmp/themes.tar.gz "$REPO_RAW_BASE/themes.tar.gz"
curl -L -o /tmp/cursors.tar.gz "$REPO_RAW_BASE/cursors.tar.gz"

sudo tar -xzf /tmp/icons.tar.gz -C /usr/share/icons/
sudo tar -xzf /tmp/themes.tar.gz -C /usr/share/themes/
sudo tar -xzf /tmp/cursors.tar.gz -C /usr/share/icons/

# Правим владельца для пользователя
chown -R $USER:$USER "$HOME_DIR/.config/xfce4"

echo "Конфиги и темы успешно загружены и установлены"





# --- Установка yay и AUR пакетов от пользователя $USERNAME ---

echo -e "\n\033[1;32mУстановка AUR пакетов от имени $USERNAME\033[0m"

# Дать пользователю временно доступ к sudo без пароля (иначе makepkg будет ругаться)
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/aur-temp

# Создаём временную директорию
sudo -u $USERNAME bash <<'EOC'

cd ~

# Клонируем yay
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Устанавливаем AUR пакеты
yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3

EOC

# Удаляем временные права
rm /etc/sudoers.d/aur-temp







#!/bin/bash
set -e

# --- Настройки ---
HOSTNAME="arch-vm"
USERNAME="mrgraf"
USERPASS="1234"
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
echo -e "\n\033[1;32mУстановка базовой системы\033[0m"
pacstrap /mnt base base-devel linux linux-headers linux-firmware limine nano networkmanager sudo git xf86-video-vmware \
xorg-server xorg-xinit xfce4-netload-plugin xfce4-notifyd xfce4-panel  dbus \
xfce4-pulseaudio-plugin xfce4-session xfce4-settings xfce4-systemload-plugin xfce4-whiskermenu-plugin \
xfce4-xkb-plugin xfconf network-manager-applet ttf-font-awesome \
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman ntfs-3g \
pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-equalizer pulseaudio-jack pulseaudio-lirc \
xarchiver unrar unzip p7zip \
numlockx kitty firefox rofi nitrogen bash-completion lxtask flameshot keepassxc mpv neofetch \
pulseaudio-rtp pulseaudio-zeroconf i3-wm 

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
systemctl enable NetworkManager
systemctl enable dbus

# --- Пользователи ---
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# --- Обновление ---
pacman -Syu --noconfirm

# --- СТАВИМ ЗАГРУЗЧИК Limine ---
echo "Установка Limine"

# Убедимся, что есть директория /boot/limine
mkdir -p /boot/limine

# Создаём конфиг Limine
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
cp /usr/share/limine/limine-bios.sys /boot/limine/
cp /usr/share/limine/limine-bios-cd.bin /boot/limine/
cp /usr/share/limine/limine-uefi-cd.bin /boot/limine/

# Устанавливаем Limine
limine bios-install $DISK

echo -e "\n\033[1;32mLimine успешно установлен и настроен!\033[0m"

# --- Менеджер входа ly ---
pacman -Sy --noconfirm ly
systemctl enable ly



EOF_CHROOT

# --- Финал ---
echo "Финал: размонтирование и завершение"
umount -R /mnt
echo "Установка завершена. Можно перезагружаться!"
