from textual.app import App, ComposeResult
from textual.widgets import Static, ProgressBar
from textual.containers import Vertical
import subprocess
import asyncio
import shlex

class LogView(Static):
    def append_line(self, line: str) -> None:
        new_text = f"{self.renderable}\n{line}" if self.renderable else line
        self.update(new_text)
        self.scroll_end(animate=False)

class InstallerApp(App):
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
        yield LogView(id="log")
        with Vertical(id="status"):
            yield Static("[b]Current Installation Step[/b]", id="status-text")
            yield ProgressBar(total=100, id="progress-bar")

    async def on_mount(self) -> None:
        self.log_view = self.query_one("#log", LogView)
        self.status_text = self.query_one("#status-text", Static)
        self.progress_bar = self.query_one("#progress-bar", ProgressBar)
        try:
            await self.run_installation()
            self.set_status("Installation Complete!", 100)
        except Exception as e:
            self.log(f"[b red]Installation failed: {e}[/b red]")

    def set_status(self, text: str, progress: int) -> None:
        self.status_text.update(f"[b]Current Step:[/b] {text}")
        self.progress_bar.progress = progress

    def log(self, text: str) -> None:
        self.log_view.append_line(text)
        with open("/tmp/installer.log", "a") as f:
            f.write(text + "\n")

    async def run_cmd(self, cmd: list, check=True) -> None:
        self.log(f"$ {' '.join(shlex.quote(c) for c in cmd)}")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        async def read_stream(stream, is_err=False):
            while True:
                line = await stream.readline()
                if not line:
                    break
                text = line.decode().strip()
                if is_err:
                    text = f"[red]{text}[/red]"
                self.log(text)
                await asyncio.sleep(0)

        await asyncio.gather(
            read_stream(process.stdout),
            read_stream(process.stderr, is_err=True),
        )

        await process.wait()
        if check and process.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")

    async def run_installation(self) -> None:
        self.set_status("Creating Partitions", 5)
        await self.run_cmd(["parted", "-s", "/dev/sda", "mklabel", "gpt"])
        await self.run_cmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "fat32", "1MiB", "300MiB"])
        await self.run_cmd(["parted", "-s", "/dev/sda", "mkpart", "primary", "ext4", "300MiB", "100%"])
        await self.run_cmd(["mkfs.fat", "-F32", "-n", "boot", "/dev/sda1"])
        await self.run_cmd(["mkfs.ext4", "-L", "root", "/dev/sda2"])

        self.set_status("Mounting", 10)
        await self.run_cmd(["mount", "/dev/sda2", "/mnt"])
        await self.run_cmd(["mkdir", "-p", "/mnt/boot"])
        await self.run_cmd(["mount", "/dev/sda1", "/mnt/boot"])

        self.set_status("Installing Base Packages", 20)
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

        self.set_status("Configuring System", 30)
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
        await self.run_cmd(["arch-chroot", "/mnt", "bash", "-c", "echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers"])

        # Обновление системы
        self.set_status("Updating System", 35)
        await self.run_cmd(["arch-chroot", "/mnt", "pacman", "-Syu", "--noconfirm"])

        # Установка и настройка Limine
        self.set_status("Setting up Limine Bootloader", 40)
        await self.run_cmd(["mkdir", "-p", "/mnt/boot/limine"])
        limine_conf = (
            "/+Arch Linux\n"
            "comment: loader linux\n"
            "//Linux\n"
            "protocol: linux\n"
            "path: boot():/vmlinuz-linux\n"
            "cmdline: root=LABEL=root rw quiet\n"
            "module_path: boot():/initramfs-linux.img"
        )
        await self.run_cmd(["bash", "-c", f"cat > /mnt/boot/limine/limine.conf <<'EOF'\n{limine_conf}\nEOF"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-bios.sys", "/mnt/boot/limine/"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-bios-cd.bin", "/mnt/boot/limine/"])
        await self.run_cmd(["cp", "/usr/share/limine/limine-uefi-cd.bin", "/mnt/boot/limine/"])
        await self.run_cmd(["arch-chroot", "/mnt", "limine", "bios-install", "/dev/sda"])

        # Установка менеджера входа ly
        self.set_status("Setting up Display Manager", 50)
        await self.run_cmd(["arch-chroot", "/mnt", "pacman", "-Sy", "--noconfirm", "ly"])
        await self.run_cmd(["arch-chroot", "/mnt", "systemctl", "enable", "ly"])

        # Создание каталогов и загрузка конфигов
        self.set_status("Downloading and Setting Up Configurations", 60)
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/i3"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/neofetch"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/nitrogen"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/.config/polybar"])
        await self.run_cmd(["mkdir", "-p", "/mnt/home/mrgraf/Wallpapers"])

        # Загрузка и распаковка конфигов i3
        await self.run_cmd(["wget", "-q", "-O", "/tmp/i3.zip", "https://github.com/MrGrafGitHub/arch/raw/main/configs/i3.zip"])
        await self.run_cmd(["mkdir", "-p", "/tmp/i3-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/i3.zip", "-d", "/tmp/i3-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/i3-tmp/i3/*", "/mnt/home/mrgraf/.config/i3/"])
        await self.run_cmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/i3"])

        # Загрузка и распаковка конфигов polybar
        await self.run_cmd(["wget", "-q", "-O", "/tmp/polybar.zip", "https://github.com/MrGrafGitHub/arch/raw/main/configs/polybar.zip"])
        await self.run_cmd(["mkdir", "-p", "/tmp/polybar-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/polybar.zip", "-d", "/tmp/polybar-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/polybar-tmp/polybar/*", "/mnt/home/mrgraf/.config/polybar/"])
        await self.run_cmd(["chown", "-R", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/polybar"])

        # Загрузка и установка шрифтов
        await self.run_cmd(["wget", "-q", "-O", "/tmp/fonts.zip", "https://github.com/MrGrafGitHub/arch/raw/main/font/fonts.zip"])
        await self.run_cmd(["mkdir", "-p", "/tmp/fonts-tmp"])
        await self.run_cmd(["unzip", "-oq", "/tmp/fonts.zip", "-d", "/tmp/fonts-tmp"])
        await self.run_cmd(["cp", "-rf", "/tmp/fonts-tmp/*", "/mnt/usr/share/fonts/"])
        await self.run_cmd(["arch-chroot", "/mnt", "fc-cache", "-fv"])

        # Загрузка конфига neofetch
        await self.run_cmd(["wget", "-q", "-O", "/mnt/home/mrgraf/.config/neofetch/config.conf", "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/configs/neofetch/config.conf"])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/neofetch/config.conf"])

        # Загрузка обоев
        await self.run_cmd(["wget", "-q", "-O", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg", "https://raw.githubusercontent.com/MrGrafGitHub/arch/main/assets/wallpaper.jpg"])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/Wallpapers/wallpaper.jpg"])

        # Настройка nitrogen
        nitrogen_config = f"[xin_-1]\nfile=/home/mrgraf/Wallpapers/wallpaper.jpg\nmode=4\nbgcolor=#000000"
        await self.run_cmd(["bash", "-c", f"cat > /mnt/home/mrgraf/.config/nitrogen/bg-saved.cfg <<'EOF'\n{nitrogen_config}\nEOF"])
        await self.run_cmd(["chown", "mrgraf:mrgraf", "/mnt/home/mrgraf/.config/nitrogen/bg-saved.cfg"])

        # Установка yay и AUR пакетов
        self.set_status("Installing AUR Packages", 90)
        await self.run_cmd(["bash", "-c", "echo 'mrgraf ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/makepkg' > /mnt/etc/sudoers.d/aur-temp"])
        await self.run_cmd(["chmod", "0440", "/mnt/etc/sudoers.d/aur-temp"])
        await self.run_cmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "set -e && cd /home/mrgraf && if ! command -v yay >/dev/null 2>&1; then git clone https://aur.archlinux.org/yay.git ~/yay && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay; fi"])
        await self.run_cmd(["arch-chroot", "/mnt", "sudo", "-u", "mrgraf", "bash", "-c", "yay -S --noconfirm --needed audacious-gtk3 audacious-plugins-gtk3 autotiling neofetch sublime-text-4"])
        await self.run_cmd(["rm", "-f", "/mnt/etc/sudoers.d/aur-temp"])

        self.set_status("Finalizing", 100)
        await self.run_cmd(["umount", "-R", "/mnt"])

if __name__ == "__main__":
    app = InstallerApp()
    app.run()
