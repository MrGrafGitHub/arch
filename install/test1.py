from textual.app import App, ComposeResult
from textual.widgets import Static, ProgressBar
from textual.containers import Vertical
import subprocess
import asyncio
import shlex
import os #   Импортируем модуль os для проверки существования файлов

class LogView(Static):
    """
    # Виджет для отображения логов установки.
    """
    def append_line (self, line: str) -> None:
        # Добавляет строку в лог и прокручивает в конец.
        newtext = f"{self.renderable}\n{line}" if self.renderable else line
        self.update(newtext)
        self.scroll_end(animate=False)

class InstallerApp(App):
    
    # Приложение для автоматической установки Arch Linux.
    
    CSS = '''
    Screen {
        layout: vertical;
    }
    #log {
        height: 1fr;
        border: heavy $accent;
        padding: 1;
        overflow-y: auto;
    }
    #status {
        height: auto;
        border: heavy $accent;
        padding: 1;
    }
    '''

    def compose(self) -> ComposeResult:
        # Создает элементы интерфейса.
        yield LogView(id="log")
        with Vertical(id="status"):
            yield Static("[b]Текущий этап установки[/b]", id="status-text")
            yield ProgressBar(total=100, id="progress-bar")

    async def on_mount(self) -> None:
        # Выполняется при монтировании приложения. 
        self.logview = self.query_one ("log", LogView)
        self.statustext = self.query_one ("status-text", Static)
        self.progressbar = self.query_one ("progress-bar", ProgressBar)
        try:
            await self.runinstallation()
            self.setstatus("Установка завершена!", 100)
        except Exception as e:
            self.log(f"[b red]Ошибка установки: {e}[/b red]")

    def setstatus(self, text: str, progress: int) -> None:
        # Обновляет статус установки и прогресс-бар.
        self.statustext.update(f"[b]Текущий этап:[/b] {text}")
        self.progressbar.progress = progress

    def log(self, text: str) -> None:
        # Добавляет запись в лог и записывает в файл. 
        self.logview.append_line(text)
        try: #  Добавляем обработку исключений для записи в лог
            with open("/tmp/installer.log", "a") as f:
                f.write(text + "\n")
        except Exception as e:
            print(f"Ошибка записи в лог-файл: {e}")  # Выводим ошибку в консоль, если запись в файл не удалась

    async def runcmd(self, cmd: list, check=True) -> None:
        # Запускает команду в subprocess и логирует вывод. 
        cmdstr = ' '.join(shlex.quote(c) for c in cmd)
        self.log(f"$ {cmdstr}")
        process = await asyncio.create_subprocess_exec(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        async def readstream(stream, iserr=False):
            # Читает поток вывода subprocess и логирует. 
            while True:
                try:
                    line = await stream.readline()
                except Exception as e:
                    self.log(f"[red]Ошибка чтения потока: {e}[/red]")
                    break
                if not line:
                    break
                try:
                    text = line.decode().strip()
                except UnicodeDecodeError:
                    text = "[red]Невозможно декодировать вывод[/red]"
                if iserr:
                    text = f"[red]{text}[/red]"
                self.log(text)
                await asyncio.sleep(0)

        await asyncio.gather(
            readstream(process.stdout),
            readstream(process.stderr, iserr=True),
        )

        await process.wait()
        if check and process.returncode != 0:
            raise RuntimeError(f"Command failed: {cmdstr} (Return code: {process.returncode})")

    async def runinstallation(self) -> None:
        # Выполняет шаги установки. 
        self.setstatus("Создание разделов", 5)
        await self.runcmd(["parted", "-s", "/dev/sda", "mklabel", "gpt"])
        await self.runcmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "fat32", "1MiB", "300MiB"])
        await self.runcmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "ext4", "300MiB", "100%"])
        await self.runcmd(["mkfs.fat", "-F32", "-n", "boot", "/dev/sda1"])
        await self.runcmd(["mkfs.ext4", "-L", "root", "/dev/sda2"])

        self.setstatus("Монтирование", 10)
        await self.runcmd(["mount", "/dev/sda2", "/mnt"])
        await self.runcmd(["mkdir", "-p", "/mnt/boot"])
        await self.runcmd(["mount", "/dev/sda1", "/mnt/boot"])

        self.setstatus("Установка базовых пакетов", 20)
        await self.runcmd([
            "pacstrap", "/mnt", "base", "base-devel", "linux", "linux-headers",
            "linux-firmware", "limine", "nano", "networkmanager", "sudo", "git",
            "xorg-server", "xorg-xinit", "dbus", "wget", "xfconf", "xfce4-notifyd",
            "xfce4-settings", "network-manager-applet", "ttf-font-awesome",
            "thunar", "thunar-archive-plugin", "thunar-media-tags-plugin", "thunar-volman",
            "ntfs-3g", "pulseaudio", "pulseaudio-alsa", "pulseaudio-bluetooth",
            "pulseaudio-equalizer", "pulseaudio-jack", "pulseaudio-lirc", "xarchiver",
            "unrar", "unzip", "p7zip", "zip", "numlockx", "kitty", "firefox", "rofi",
            "nitrogen", "bash-completion", "lxtask", "flameshot", "keepassxc", "mpv",
            "telegram-desktop", "pulseaudio-rtp", "pulseaudio-zeroconf", "i3", "picom",
            "polybar", "kvantum-qt5", "python-gobject", "python-gitdb", "pavucontrol", "arandr"
        ])

        self.setstatus("Настройка системы", 30)
        await self.runcmd(["arch-chroot", "/mnt", "ln", "-sf", "/usr/share/zoneinfo/Europe/Moscow", "/etc/localtime"])
        await self.runcmd(["arch-chroot", "/mnt", "hwclock", "--systohc"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo LANG=ru_RU.UTF-8 > /etc/locale.conf"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo ru_RU.UTF-8 UTF-8 >> /etc/locale.gen"])
        await self.runcmd(["arch-chroot", "/mnt", "locale-gen"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo KEYMAP=ru > /etc/vconsole.conf"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo FONT=cyr-sun16 >> /etc/vconsole.conf"])
        await self.runcmd(["arch-chroot", "/mnt", "systemctl", "enable", "NetworkManager"])
        await self.runcmd(["arch-chroot", "/mnt", "systemctl", "enable", "dbus"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo root:root | chpasswd"])
        await self.runcmd(["arch-chroot", "/mnt", "useradd", "-m", "-G", "wheel", "mrgraf"])
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo mrgraf:1234 | chpasswd"])
        #  Используем безопасный способ добавления в sudoers
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel"])
        await self.runcmd(["arch-chroot", "/mnt", "chmod", "0440", "/etc/sudoers.d/wheel"])

        #  Обновление системы
        self.setstatus("Обновление системы", 35)
        await self.runcmd(["arch-chroot", "/mnt", "pacman", "-Syu", "--noconfirm"])

        #  Установка и настройка Limine
        self.setstatus("Настройка Limine Bootloader", 40)
        await self.runcmd(["mkdir", "-p", "/mnt/boot/limine"])
        limineconf = (
            "/+Arch Linux\n"
            "comment: loader linux\n"
            "//Linux\n"
            "protocol: linux\n"
            "path: boot():/vmlinuz-linux\n"
            "cmdline: root=LABEL=root rw quiet\n"
            "modulepath: boot():/initramfs-linux.img"
        )
        #  Используем echo для записи в файл, чтобы избежать проблем с интерпретацией символов
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", f"echo \"{limineconf}\" > /boot/limine/limine.conf"])
        await self.runcmd(["cp", "/usr/share/limine/limine-bios.sys", "/mnt/boot/limine/"])
        await self.runcmd(["cp", "/usr/share/limine/limine-bios-cd.bin", "/mnt/boot/limine/"])
        await self.runcmd(["cp", "/usr/share/limine/limine-uefi-cd.bin", "/mnt/boot/limine/"])
        await self.runcmd(["arch-chroot", "/mnt", "limine", "bios-install", "/dev/sda"])

        #  Установка менеджера входа ly
        self.setstatus("Настройка Display Manager", 50)
        await self.runcmd(["arch-chroot", "/mnt", "pacman", "-Sy", "--noconfirm", "ly"])
        await self.runcmd(["arch-chroot", "/mnt", "systemctl", "enable", "ly"])

        #  Создание каталогов и загрузка конфигов
        self.setstatus("Загрузка и настройка конфигураций", 60)
        await self.runcmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/i3"])
        await self.runcmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/neofetch"])
        await self.runcmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/nitrogen"])
        await self.runcmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/polybar"])
        await self.runcmd(["mkdir", "-p", "/mnt/home/mrgraf/Wallpapers"])

        #  Загрузка и распаковка конфигов i3
        i3configurl = "https://github.com/MrGrafGitHub/arch/raw/main/configs/i3.zip"
        await self.runcmd(["wget", "-q", "-O", "/tmp/i3.zip", i3configurl])
        await self.runcmd(["mkdir", "-p", "/tmp/i3-tmp"])
        await self.runcmd(["unzip", "-oq", "/tmp/i3.zip", "-d", "/tmp/i3-tmp"])
        await self.runcmd(["cp", "-rf", "/tmp/i3-tmp/i3/", "/mnt/home/mrgraf/.config/i3/"])
        await self.runcmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/i3"])

        #  Загрузка и распаковка конфигов polybar
        polybarconfigurl = "https://github.com/MrGrafGitHub/arch/raw/main/configs/polybar.zip"
        await self.runcmd(["wget", "-q", "-O", "/tmp/polybar.zip", polybarconfigurl])
        await self.runcmd(["mkdir", "-p", "/tmp/polybar-tmp"])
        await self.runcmd(["unzip", "-oq", "/tmp/polybar.zip", "-d", "/tmp/polybar-tmp"])
        await self.runcmd(["cp", "-rf", "/tmp/polybar-tmp/polybar/", "/mnt/home/mrgraf/.config/polybar/"])
        await self.runcmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/polybar"])

        #  Загрузка и установка шрифтов
        fontsurl = "https://github.com/MrGrafGitHub/arch/raw/main/font/fonts.zip"
        await self.runcmd(["wget", "-q", "-O", "/tmp/fonts.zip", fontsurl])
        await self.runcmd(["mkdir", "-p", "/tmp/fonts-tmp"])
        await self.runcmd(["unzip", "-oq", "/tmp/fonts.zip", "-d", "/tmp/fonts-tmp"])
        await self.runcmd(["cp", "-rf", "/tmp/fonts-tmp/", "/mnt/usr/share/fonts/"])
        await self.runcmd(["arch-chroot", "/mnt", "fc-cache", "-fv"])

        #  Загрузка конфига neofetch
        neofetchconfigurl = "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf"
        await self.runcmd(["wget", "-q", "-O", "/mnt/home/mrgraf/.config/neofetch/config.conf", neofetchconfigurl])
        await self.runcmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/neofetch/config.conf"])

        #  Загрузка обоев
        wallpaperurl = "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/assets/wallpaper.jpg"
        await self.runcmd(["wget", "-q", "-O", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg", wallpaperurl])
        await self.runcmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg"])

        # Настройка nitrogen
        nitrogenconfig = f"[xin-1]\nfile=/home/mrgraf/Wallpapers/wallpaper.jpg\nmode=4\nbgcolor=000000"
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", f"echo \"{nitrogenconfig}\" > /home/mrgraf/.config/nitrogen/bg-saved.cfg"])
        await self.runcmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/nitrogen/bg-saved.cfg"])

        #  Установка yay и AUR пакетов
        self.setstatus("Установка AUR пакетов", 90)
        #  Создаем временный файл sudoers для пользователя mrgraf
        await self.runcmd(["arch-chroot", "/mnt", "bash", "-c", "echo 'mrgraf ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg' > /etc/sudoers.d/aur-temp"])
        await self.runcmd(["arch-chroot", "/mnt", "chmod", "0440", "/etc/sudoers.d/aur-temp"])
        #  Устанавливаем yay и AUR пакеты от имени пользователя mrgraf
        await self.runcmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "set -e && cd /home/mrgraf && if ! command -v yay >/dev/null 2>&1; then git clone https://aur.archlinux.org/yay.git ~/yay && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay; fi"])
        await self.runcmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch sublime-text-4"])
        #  Удаляем временный файл sudoers
        await self.runcmd(["rm", "-f", "/mnt/etc/sudoers.d/aur-temp"])

        self.setstatus("Завершение", 100)
        await self.runcmd(["umount", "-R", "/mnt"])

if __name__ == "__main__":
    app = InstallerApp()
    app.run()
