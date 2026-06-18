#!/bin/bash

set -ouex pipefail

# Copy system_files/ into the image root
cp -avf "/ctx/system_files"/. /

dnf5 install -y fish

### Hardware enablement (ThinkPad T14 + GPD G1 eGPU)

FEDORA_VER="$(rpm -E %fedora)"

# RPMFusion (free + nonfree) for full codecs and the freeworld VA drivers
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

# Mesa (OpenGL + Vulkan) covers both the Intel iGPU and the AMD eGPU
dnf5 install -y mesa-dri-drivers mesa-vulkan-drivers

# VA-API video decode: freeworld (AMD) + intel-media-driver (Tiger Lake)
dnf5 install -y --allowerasing \
    mesa-va-drivers-freeworld \
    intel-media-driver \
    libva-utils

# Full ffmpeg from RPMFusion (replaces Fedora's ffmpeg-free)
dnf5 install -y --allowerasing ffmpeg

# Thunderbolt device authorization for the eGPU (bolt.service is D-Bus activated)
dnf5 install -y bolt

# Intel WiFi firmware: Fedora 44 split the iwlwifi firmware out of linux-firmware
# into iwlwifi-mvm-firmware, pulled only as a weak dep that the bootc base omits.
# Without it the AX201 has no firmware, iwlwifi never probes, and there is no wlan0.
dnf5 install -y iwlwifi-mvm-firmware

# NetworkManager WiFi support: fedora-bootc ships only the NetworkManager core, while
# the WiFi device plugin (NetworkManager-wifi -> libnm-device-plugin-wifi.so) and the
# WPA backend (wpa_supplicant) are weak deps the minimal base omits. Without the plugin
# NM marks the wlan device "unmanaged by default" (reason 69) and never scans, so no
# networks ever appear (e.g. in the DankMaterialShell network widget).
dnf5 install -y NetworkManager-wifi wpa_supplicant

### Kernel: replace the Fedora kernel with CachyOS (COPR repos via system_files)

# Stock kernel version, used below to drop its orphaned files after the swap
OLD_KVER="$(ls /usr/lib/modules)"

# fedora-bootc has no kernel-modules-extra
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core

# The kernel %posttrans initramfs hook fails inside a container build (modules.dep
# isn't ready before the hook runs), which makes dnf5 report failure even though the
# package installs. Tolerate it, assert the install, then build the initramfs manually.
dnf5 -y install kernel-cachyos || true
rpm -q kernel-cachyos-core

KVER="$(rpm -q kernel-cachyos-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"

# Plymouth boot splash + graphical LUKS unlock prompt. This must run BEFORE the
# initramfs is built below: dracut's plymouth module embeds whatever theme is set
# as default, plus the plugin that theme needs, into the initramfs. The deus_ex
# theme (adi1090x/plymouth-themes, pack_2) is a script-plugin theme, so it needs
# plymouth-plugin-script; plymouth-plugin-label renders the password text.
dnf5 -y install plymouth plymouth-scripts plymouth-plugin-script plymouth-plugin-label

curl -fsSL https://github.com/adi1090x/plymouth-themes/archive/refs/heads/master.tar.gz -o /tmp/plymouth-themes.tar.gz
mkdir -p /tmp/plymouth-themes /usr/share/plymouth/themes
tar -xzf /tmp/plymouth-themes.tar.gz -C /tmp/plymouth-themes --strip-components=1
cp -a /tmp/plymouth-themes/pack_2/deus_ex /usr/share/plymouth/themes/
rm -rf /tmp/plymouth-themes /tmp/plymouth-themes.tar.gz

plymouth-set-default-theme deus_ex

# The ostree dracut module is required for bootc to mount the deployment;
# the plymouth module embeds the splash for early boot + LUKS unlock.
depmod -a "${KVER}"
dracut --no-hostonly --kver "${KVER}" --reproducible --add "ostree plymouth" -f "/usr/lib/modules/${KVER}/initramfs.img"
test -f "/usr/lib/modules/${KVER}/initramfs.img"
# Sanity-check the theme actually landed in the initramfs. Dump to a file first:
# piping lsinitrd into `grep -q` makes grep close the pipe on the first match, so
# lsinitrd dies with SIGPIPE (exit 141) which pipefail would turn into a build abort.
lsinitrd "/usr/lib/modules/${KVER}/initramfs.img" > /tmp/initramfs-contents.txt
grep -q 'plymouth/themes/deus_ex/deus_ex.script' /tmp/initramfs-contents.txt
rm -f /tmp/initramfs-contents.txt

rm -rf "/usr/lib/modules/${OLD_KVER}"

# Required by kernel-cachyos to load modules under SELinux
setsebool -P domain_kernel_load_modules on

dnf5 -y install --allowerasing \
    cachyos-settings \
    scx-scheds scx-manager \
    ananicy-cpp cachyos-ananicy-rules

### Desktop: niri + DankMaterialShell

# quickshell-git is pinned on purpose: it builds against Qt 6.11 (matching Fedora and
# the KDE apps below). Plain "quickshell" pins Qt 6.10 and would force a qt6 downgrade
# that conflicts with okular/kde-connect/filelight.
dnf5 -y install niri dms dms-greeter quickshell-git kanshi

# oniri: auto-maximizes the only window in a niri workspace (used via
# `spawn-at-startup "oniri"` in the niri config). Not packaged for Fedora, so pull
# the upstream prebuilt static-musl binary and verify its checksum before installing.
ONIRI_VER="1.2.2"
curl -fsSL "https://github.com/Antiz96/oniri/releases/download/v${ONIRI_VER}/oniri-${ONIRI_VER}-x86_64" -o /usr/bin/oniri
curl -fsSL "https://github.com/Antiz96/oniri/releases/download/v${ONIRI_VER}/oniri-${ONIRI_VER}-x86_64.sha256" -o /tmp/oniri.sha256
echo "$(awk '{print $1}' /tmp/oniri.sha256)  /usr/bin/oniri" | sha256sum -c -
chmod 0755 /usr/bin/oniri
rm -f /tmp/oniri.sha256

# Autostart the DMS shell in every niri session. dms.service is a systemd *user*
# unit (ExecStart=dms run --session); the `dms` CLI normally enables it per-user, so
# fresh accounts never get it and the catch-all `disable *` user-preset keeps it off.
# Enable it image-wide via a global user-unit symlink, scoped to niri.service.wants
# so it does NOT also launch in the Steam/gamescope session.
mkdir -p /etc/systemd/user/niri.service.wants
ln -sf /usr/lib/systemd/user/dms.service /etc/systemd/user/niri.service.wants/dms.service

# Default niri config: /etc/skel for new accounts, /etc/niri as the system
# fallback (used by users created before the config existed / with no ~/.config/niri).
# Symlink /etc/niri -> the skel copy so there is a single source of truth: editing
# system_files/etc/skel/.config/niri/ updates both. The link is relative (resolved
# from /etc) and must point this way round -- skel holds the real files because
# useradd copies skel contents verbatim into new home dirs.
ln -snf skel/.config/niri /etc/niri

# Wallpapers referenced by the DMS session.json seed in /etc/skel
mkdir -p /usr/share/backgrounds/niriblue
cp /ctx/assets/light.png /ctx/assets/dark.png /usr/share/backgrounds/niriblue/

# Branding logos referenced by the DMS settings.json seed in /etc/skel
# (dock launcher + bar launcher button). Shipped system-wide so every account's
# settings.json can point at a stable absolute path instead of a user home dir.
mkdir -p /usr/share/niriblue/assets
cp /ctx/assets/flame.svg /ctx/assets/flame_pixel.svg /usr/share/niriblue/assets/

dnf5 -y install pipewire wireplumber pipewire-pulseaudio pipewire-alsa

# XDG portals (gtk fallback, gnome for screencast) + secret service
dnf5 -y install xdg-desktop-portal-gtk xdg-desktop-portal-gnome gnome-keyring

# Power profiles: DMS's profile widget (Quickshell UPower PowerProfiles) talks to the
# net.hadess.PowerProfiles D-Bus interface, which nothing in the base image provides.
# power-profiles-daemon supplies it (D-Bus activated; enable so it's always available).
dnf5 -y install power-profiles-daemon
systemctl enable power-profiles-daemon.service

# X11-on-Wayland (Steam/Discord) + polkit agent
dnf5 -y install xwayland-satellite mate-polkit

dnf5 -y install greetd-selinux
dnf5 -y install google-noto-sans-fonts google-noto-emoji-fonts

systemctl enable greetd.service
systemctl set-default graphical.target

### Steam / gamescope session

# Provides wayland-sessions/steam.desktop (selectable in the greeter) and pulls in
# steam, gamescope and mangohud
dnf5 -y install gamescope-session-guide

# Route the Steam session through niriblue-gamescope-session (shipped via
# system_files), which auto-targets a connected eGPU display instead of always
# landing on the laptop's internal panel. steam.desktop is owned by the RPM, so
# patch its Exec= here, *after* the install, otherwise it would be overwritten.
chmod 0755 /usr/bin/niriblue-gamescope-session
sed -i 's|^Exec=gamescope-session$|Exec=niriblue-gamescope-session|' \
    /usr/share/wayland-sessions/steam.desktop

### Applications (external repos via system_files: vscode.repo, zen-browser COPR)

rpm --import https://packages.microsoft.com/keys/microsoft.asc

# okular, gnome-calculator, gnome-text-editor, loupe and mpv are installed as
# Flatpaks instead (see system_files/usr/share/niriblue/flatpaks.list)
dnf5 -y install \
    kitty nautilus \
    discord \
    distrobox kde-connect \
    wine winetricks gamemode vulkan-tools \
    file-roller unzip 7zip unrar \
    fprintd fprintd-pam \
    gnome-disk-utility gparted filelight \
    fuse fuse-libs flatpak fastfetch \
    papirus-icon-theme \
    code zen-browser

# Enable fingerprint authentication (T14 reader)
authselect enable-feature with-fingerprint

# Apply the default PDF handler from mimeapps.list
update-desktop-database /usr/share/applications || true

# JetBrains Toolbox has no RPM; 3.x ships as a directory (bin/ + jbr/), not a single
# AppImage. Stage it under /usr/lib and link the launcher into PATH; Toolbox relocates
# itself to $HOME and self-updates on first run.
curl -fsSL "https://data.services.jetbrains.com/products/download?code=TBA&platform=linux" -o /tmp/jbtoolbox.tar.gz
mkdir -p /tmp/jbtoolbox
tar -xzf /tmp/jbtoolbox.tar.gz -C /tmp/jbtoolbox
TBX_SRC="$(find /tmp/jbtoolbox -maxdepth 1 -mindepth 1 -type d | head -1)"
mkdir -p /usr/lib/jetbrains-toolbox
cp -a "${TBX_SRC}/." /usr/lib/jetbrains-toolbox/
ln -sf /usr/lib/jetbrains-toolbox/bin/jetbrains-toolbox /usr/bin/jetbrains-toolbox
rm -rf /tmp/jbtoolbox /tmp/jbtoolbox.tar.gz

# Homebrew build dependencies
dnf5 -y install git procps-ng file gcc gcc-c++ make

chmod 0755 /usr/libexec/niriblue-flatpak-setup /usr/libexec/niriblue-brew-setup

systemctl enable niriblue-flatpak-setup.service
systemctl enable niriblue-brew-setup.service
systemctl enable systemd-sysext.service

### Networking: Tailscale (repo shipped via system_files/etc/yum.repos.d/tailscale.repo)

rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg

dnf5 -y install tailscale

# tailscaled is socket/daemon-activated; enable it so `tailscale up` works out of the box
systemctl enable tailscaled.service

### Containers (rootless Docker) + virtualization

rpm --import https://download.docker.com/linux/fedora/gpg

dnf5 -y install \
    libvirt-daemon-kvm qemu-kvm libvirt-daemon-config-network \
    virt-manager virt-install edk2-ovmf

dnf5 -y install \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras \
    slirp4netns

# ollama is intentionally not installed: the Fedora package pulls the entire ROCm
# stack (~5 GB). It is provided on demand via `ujust setup-ollama`.
dnf5 -y install just

systemctl enable libvirtd.service

# Disable the rootful Docker daemon; users opt into rootless via `ujust setup-docker-rootless`
systemctl disable docker.service docker.socket || true

chmod 0755 /usr/bin/ujust

### System users: reconcile shadow databases and bake users into the image
# (1) fedora-bootc can ship an /etc/gshadow holding a group entry (e.g. utempter)
#     that has no matching line in /etc/group. At first boot systemd-sysusers aborts
#     its entire (atomic) run on the resulting `/etc/gshadow: Group "..." already
#     exists` conflict, so NONE of the system users get created -- greetd included --
#     and the graphical login never comes up. The same inconsistency silently breaks
#     the useradd in dms-greeter's RPM preinstall scriptlet. grpconv rebuilds
#     /etc/gshadow from /etc/group, dropping the orphaned entries.
grpconv

# (2) dms-greeter runs its session as a dedicated "greeter" user (see its tmpfiles.d,
#     which owns /var/cache/dms-greeter as greeter:greeter, and /etc/greetd/config.toml).
#     That user is normally created by the package's preinstall useradd, but that
#     no-ops silently if shadow state was inconsistent during the build. Create it
#     idempotently so the greeter always has a valid owner -- otherwise dms-greeter
#     aborts at launch ("cache directory does not exist") and greetd never shows a login.
getent group greeter >/dev/null || groupadd -r greeter
getent passwd greeter >/dev/null || \
    useradd -r -g greeter -d /var/lib/greeter -s /bin/bash -c "System Greeter" greeter

# (3) Create every remaining system user now so first boot has nothing left to do.
systemd-sysusers

### Branding: present as niriblue while staying Fedora-compatible
# ID is changed to niriblue but ID_LIKE=fedora keeps Fedora-family detection working
# (only code matching ID=fedora *exactly* stops matching). VERSION_ID stays 44 so
# $releasever and the COPR/RPMFusion repos keep resolving. /etc/os-release is a symlink
# to this file, so both paths report niriblue.
sed -i \
    -e 's/^NAME=.*/NAME="niriblue"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="niriblue (Fedora 44)"/' \
    -e 's/^ID=fedora$/ID=niriblue\nID_LIKE=fedora/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="niriblue"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/jakubiszon26/niriblue"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/jakubiszon26/niriblue/issues"|' \
    /usr/lib/os-release
printf 'VARIANT="niriblue"\nVARIANT_ID=niriblue\n' >> /usr/lib/os-release
grep -q '^ID=niriblue$' /usr/lib/os-release  # fail the build if the rebrand didn't take

# Drop dnf/runtime leftovers so they are not baked into /var
dnf5 clean all
rm -rf /var/cache/* /var/lib/dnf/* /var/log/* /var/lib/geoclue /var/lib/rpm-state/* /tmp/* /run/* || true
