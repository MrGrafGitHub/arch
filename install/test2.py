from textual.app import App, ComposeResult
from textual.widgets import Static, ProgressBar
from textual.containers import Vertical
import subprocess
import asyncio
import shlex
import os #   Импортируем модуль os для проверки существования файлов

class LogView(Static):
   def __init__(self, **kwargs):
      super().__init__(**kwargs)
      self.lines = []

   def append_line(self, line: str) -> None:
      self.lines.append(line)
      # Храним максимум строк (например, 100), чтобы не раздувать память
      if len(self.lines) > 100:
         self.lines.pop(0)
      self.update("\n".join(self.lines))
      # Авто-прокрутка (если нужна, зависит от контейнера и текстового рендера)
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
        self.log_view = self.query_one ("#log", LogView)
        self.status_text = self.query_one ("#status-text", Static)
        self.progress_bar = self.query_one ("#progress-bar", ProgressBar)
    
        async def install_wrapper():
            try:
                await self.run_installation()
                self.set_status("Установка завершена!", 100)
            except Exception as e:
                self.write_log(f"[b red]Ошибка установки: {e}[/b red]")

        asyncio.create_task(install_wrapper())

    def set_status(self, text: str, progress: int) -> None:
        # Обновляет статус установки и прогресс-бар.
        self.status_text.update(f"[b]Текущий этап:[/b] {text}")
        self.progress_bar.progress = progress

    def write_log(self, text: str) -> None:
        # Добавляет запись в лог и записывает в файл. 
        self.log_view.append_line(text)
        try: #  Добавляем обработку исключений для записи в лог
            with open("/tmp/installer.log", "a") as f:
                f.write(text + "\n")
        except Exception as e:
            print(f"Ошибка записи в лог-файл: {e}")  # Выводим ошибку в консоль, если запись в файл не удалась

    async def run_cmd(self, cmd: list, check=True) -> None:
        # Запускает команду в subprocess и логирует вывод. 
        cmdstr = ' '.join(shlex.quote(c) for c in cmd)
        self.write_log(f"$ {cmdstr}")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        async def read_stream(stream, iserr=False):
            # Читает поток вывода subprocess и логирует. 
            while True:
                try:
                    line = await stream.readline()
                except Exception as e:
                    self.write_log(f"[red]Ошибка чтения потока: {e}[/red]")
                    break
                if not line:
                    break
                try:
                    text = line.decode().strip()
                except UnicodeDecodeError:
                    text = "[red]Невозможно декодировать вывод[/red]"
                if iserr:
                    text = f"[red]{text}[/red]"
                self.write_log(text)
                await asyncio.sleep(0)

        await asyncio.gather(
            read_stream(process.stdout),
            read_stream(process.stderr, iserr=True),
        )

        await process.wait()
        if check and process.returncode != 0:
            raise RuntimeError(f"Command failed: {cmdstr} (Return code: {process.returncode})")

    async def run_installation(self) -> None:
        # Выполняет шаги установки. 
        self.set_status("Создание разделов", 5)
        await self.run_cmd(["parted", "-s", "/dev/sda", "mklabel", "gpt"])
        await self.run_cmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "fat32", "1MiB", "300MiB"])
        await self.run_cmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "ext4", "300MiB", "100%"])
        await self.run_cmd(["mkfs.fat", "-F32", "-n", "boot", "/dev/sda1"])
        await self.run_cmd(["mkfs.ext4", "-L", "root", "/dev/sda2"])

        self.set_status("Монтирование", 10)
        await self.run_cmd(["mount", "/dev/sda2", "/mnt"])
        await self.run_cmd(["mkdir", "-p", "/mnt/boot"])
        await self.run_cmd(["mount", "/dev/sda1", "/mnt/boot"])

        self.set_status("Установка базовых пакетов", 20)
        await self.run_cmd([
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

        self.set_status("Настройка системы", 30)
        await self.run_cmd(["arch-chroot", "/mnt", "ln", "-sf", "/usr/share/zoneinfo/Europe/Moscow", "/etc/localtime"])
        await self.run_cmd(["arch-chroot", "/mnt", "hwclock", "--systohc"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo LANG=ru_RU.UTF-8 > /etc/locale.conf"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo ru_RU.UTF-8 UTF-8 >> /etc/locale.gen"])
        await self.run_cmd(["arch-chroot", "/mnt", "locale-gen"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo KEYMAP=ru > /etc/vconsole.conf"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo FONT=cyr-sun16 >> /etc/vconsole.conf"])
        await self.run_cmd(["arch-chroot", "/mnt", "systemctl", "enable", "NetworkManager"])
        await self.run_cmd(["arch-chroot", "/mnt", "systemctl", "enable", "dbus"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo root:root | chpasswd"])
        await self.run_cmd(["arch-chroot", "/mnt", "useradd", "-m", "-G", "wheel", "mrgraf"])
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo mrgraf:1234 | chpasswd"])
        #  Используем безопасный способ добавления в sudoers
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel"])
        await self.run_cmd(["arch-chroot", "/mnt", "chmod", "0440", "/etc/sudoers.d/wheel"])

        #  Обновление системы
        self.set_status("Обновление системы", 35)
        await self.run_cmd(["arch-chroot", "/mnt", "pacman", "-Syu", "--noconfirm"])

        #  Установка и настройка Limine
        # Создаем файл limine.conf локально
        limine_path = "/mnt/boot/limine/limine.conf"
        with open(limine_path, "w", encoding="utf-8") as f:
            f.write(
                "/+Arch Linux\n"
                "comment: loader linux\n"
                "//Linux\n"
                "protocol: linux\n"
                "path: boot():/vmlinuz-linux\n"
                "cmdline: root=LABEL=root rw quiet\n"
                "modulepath: boot():/initramfs-linux.img\n"
            )
        #  Используем echo для записи в файл, чтобы избежать проблем с интерпретацией символов
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", f"echo \"{limineconf}\" > /boot/limine/limine.conf"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-bios.sys", "/mnt/boot/limine/"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-bios-cd.bin", "/mnt/boot/limine/"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-uefi-cd.bin", "/mnt/boot/limine/"])
        await self.run_cmd(["arch-chroot", "/mnt", "limine", "bios-install", "/dev/sda"])

        #  Установка менеджера входа ly
        self.set_status("Настройка Display Manager", 50)
        await self.run_cmd(["arch-chroot", "/mnt", "pacman", "-Sy", "--noconfirm", "ly"])
        await self.run_cmd(["arch-chroot", "/mnt", "systemctl", "enable", "ly"])

        #  Создание каталогов и загрузка конфигов
        self.set_status("Загрузка и настройка конфигураций", 60)
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/i3"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/neofetch"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/nitrogen"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/polybar"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/Wallpapers"])

        #  Загрузка и распаковка конфигов i3
        i3configurl = "https://github.com/MrGrafGitHub/arch/raw/main/configs/i3.zip"
        await self.run_cmd(["wget", "-q", "-O", "/tmp/i3.zip", i3configurl])
        await self.run_cmd(["mkdir", "-p", "/tmp/i3-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/i3.zip", "-d", "/tmp/i3-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/i3-tmp/i3/", "/mnt/home/mrgraf/.config/i3/"])
        await self.run_cmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/i3"])

        #  Загрузка и распаковка конфигов polybar
        polybarconfigurl = "https://github.com/MrGrafGitHub/arch/raw/main/configs/polybar.zip"
        await self.run_cmd(["wget", "-q", "-O", "/tmp/polybar.zip", polybarconfigurl])
        await self.run_cmd(["mkdir", "-p", "/tmp/polybar-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/polybar.zip", "-d", "/tmp/polybar-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/polybar-tmp/polybar/", "/mnt/home/mrgraf/.config/polybar/"])
        await self.run_cmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/polybar"])

        #  Загрузка и установка шрифтов
        fontsurl = "https://github.com/MrGrafGitHub/arch/raw/main/font/fonts.zip"
        await self.run_cmd(["wget", "-q", "-O", "/tmp/fonts.zip", fontsurl])
        await self.run_cmd(["mkdir", "-p", "/tmp/fonts-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/fonts.zip", "-d", "/tmp/fonts-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/fonts-tmp/", "/mnt/usr/share/fonts/"])
        await self.run_cmd(["arch-chroot", "/mnt", "fc-cache", "-fv"])

        #  Загрузка конфига neofetch
        neofetchconfigurl = "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf"
        await self.run_cmd(["wget", "-q", "-O", "/mnt/home/mrgraf/.config/neofetch/config.conf", neofetchconfigurl])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/neofetch/config.conf"])

        #  Загрузка обоев
        wallpaperurl = "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/assets/wallpaper.jpg"
        await self.run_cmd(["wget", "-q", "-O", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg", wallpaperurl])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg"])

        # Настройка nitrogen
        nitrogenconfig = f"[xin-1]\nfile=/home/mrgraf/Wallpapers/wallpaper.jpg\nmode=4\nbgcolor=000000"
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", f"echo \"{nitrogenconfig}\" > /home/mrgraf/.config/nitrogen/bg-saved.cfg"])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/nitrogen/bg-saved.cfg"])

        #  Установка yay и AUR пакетов
        self.set_status("Установка AUR пакетов", 90)
        #  Создаем временный файл sudoers для пользователя mrgraf
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo 'mrgraf ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg' > /etc/sudoers.d/aur-temp"])
        await self.run_cmd(["arch-chroot", "/mnt", "chmod", "0440", "/etc/sudoers.d/aur-temp"])
        #  Устанавливаем yay и AUR пакеты от имени пользователя mrgraf
        await self.run_cmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "set -e && cd /home/mrgraf && if ! command -v yay >/dev/null 2>&1; then git clone https://aur.archlinux.org/yay.git ~/yay && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay; fi"])
        await self.run_cmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch sublime-text-4"])
        #  Удаляем временный файл sudoers
        await self.run_cmd(["rm", "-f", "/mnt/etc/sudoers.d/aur-temp"])

        self.set_status("Завершение", 100)
        await self.run_cmd(["umount", "-R", "/mnt"])

if __name__ == "__main__":
    app = InstallerApp()
    app.run()
