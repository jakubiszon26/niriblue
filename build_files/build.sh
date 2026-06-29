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

# Complete device firmware for general hardware support. Fedora 39+ stopped *requiring*
# the firmware subpackages from linux-firmware: they attach as weak deps via
# Supplements:modalias(), which the minimal bootc base does not honour. So on the base
# image you get a stripped firmware set and any device whose blob is missing silently
# fails to probe (this is why WiFi and audio each needed a reactive fix before). Since
# this image is meant to run on other people's unknown hardware, pull the full consumer
# device-firmware set up front instead of chasing devices one at a time.
#
# (The convenience meta `linux-firmware-all` only exists on newer Fedora, not F44, so we
# list the subpackages explicitly. Datacenter NIC/switch firmware -- qed, netronome,
# liquidio, mlxsw_spectrum, mrvlprestera -- is intentionally excluded: never on the
# laptops/desktops this image targets.)
dnf5 install -y \
    iwlwifi-mvm-firmware iwlwifi-dvm-firmware iwlegacy-firmware \
    atheros-firmware realtek-firmware mt7xxx-firmware brcmfmac-firmware \
    libertas-firmware nxpwireless-firmware tiwilink-firmware \
    cirrus-audio-firmware \
    amd-gpu-firmware intel-gpu-firmware nvidia-gpu-firmware

# CPU microcode. The Fedora kernel ships it via an early-boot initramfs cpio, but we swap
# in the CachyOS kernel and build the initramfs by hand below, so install the microcode
# packages explicitly to be sure dracut picks them up.
dnf5 install -y microcode_ctl amd-ucode-firmware

# NetworkManager WiFi support: fedora-bootc ships only the NetworkManager core, while
# the WiFi device plugin (NetworkManager-wifi -> libnm-device-plugin-wifi.so) and the
# WPA backend (wpa_supplicant) are weak deps the minimal base omits. Without the plugin
# NM marks the wlan device "unmanaged by default" (reason 69) and never scans, so no
# networks ever appear (e.g. in the DankMaterialShell network widget).
dnf5 install -y NetworkManager-wifi wpa_supplicant

### Hardware services: peripherals that "just work" on a desktop image but are weak
### deps the minimal bootc base omits (firmware updates, thermal, Bluetooth, printing,
### scanning, mobile broadband, iDevice USB). Installed here so the image works on
### arbitrary hardware out of the box, not only on the author's machine.

# Firmware/BIOS updates via LVFS (fwupd). The refresh timer keeps the metadata current
# so the software center (Discover) can surface device firmware updates; actual flashing
# stays manual.
dnf5 install -y fwupd
systemctl enable fwupd-refresh.timer

# Intel thermal management. Without thermald thin laptops can throttle hard or run hot
# because nothing applies the platform's passive thermal policy.
dnf5 install -y thermald
systemctl enable thermald.service

# Bluetooth stack. bluez provides the daemon; PipeWire's built-in bluez5 SPA plugin +
# the already-installed wireplumber handle A2DP audio (SBC/AAC). aptX/LDAC are not added
# here (RPMFusion-only, patent-encumbered) -- can be layered later if needed.
dnf5 install -y bluez bluez-tools
systemctl enable bluetooth.service

# Printing, driverless first: cups + cups-filters for the spooler/filters, ipp-usb for
# driverless IPP-over-USB (most printers since ~2017), gutenprint-cups for older models,
# cups-pk-helper so the desktop can manage printers via PolicyKit. cups.socket activates
# cupsd on demand; ipp-usb is udev-activated per device.
#
# hplip adds HP's printer/scanner stack (hpcups driver + hpaio SANE backend) for the many
# older/USB HP devices that are not fully driverless; the hp-setup GUI comes with it.
dnf5 install -y cups cups-filters cups-pk-helper ipp-usb gutenprint-cups hplip
systemctl enable cups.socket

# Scanning, driverless first: sane-backends + sane-airscan (eSCL/WSD, works over the
# same ipp-usb path as printing for modern all-in-ones). GUI front-end ships as a Flatpak.
dnf5 install -y sane-backends sane-airscan

# Mobile broadband / WWAN modems (some ThinkPads ship one). ModemManager is the NM
# backend for cellular; mobile-broadband-provider-info supplies the APN database.
dnf5 install -y ModemManager mobile-broadband-provider-info
systemctl enable ModemManager.service

# Apple device support over USB (tethering, file/photo access via gvfs).
dnf5 install -y usbmuxd libimobiledevice

# Realtime scheduling broker so PipeWire/clients can get RT priority under load
# (rtkit-daemon is D-Bus activated; no explicit enable needed).
dnf5 install -y rtkit

### Kernel: replace the Fedora kernel with CachyOS (COPR repos via system_files)

# Track the latest CachyOS kernel from the bieszczaders COPR rather than pinning a
# version. Rationale: the COPR garbage-collects old builds (only the newest keeps its
# binary RPMs), so a hard pin would break the daily build the moment upstream ships a
# newer kernel and would force manual version bumps. Floating keeps the kernel current
# automatically; if a given kernel build is broken the image build fails in CI and the
# last good published image stays in place, so users never receive a broken kernel.
# (Every published image is still itself immutable/reproducible by digest.)

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

# First-login helper that pops niri's hotkey overlay once (spawn-at-startup).
chmod 0755 /usr/bin/niriblue-first-run-keybinds

# Wallpapers referenced by the DMS session.json seed in /etc/skel
mkdir -p /usr/share/backgrounds/niriblue
cp /ctx/assets/light.png /ctx/assets/dark.png /usr/share/backgrounds/niriblue/

# Branding logos referenced by the DMS settings.json seed in /etc/skel
# (dock launcher + bar launcher button). Shipped system-wide so every account's
# settings.json can point at a stable absolute path instead of a user home dir.
mkdir -p /usr/share/niriblue/assets
cp /ctx/assets/flame.svg /ctx/assets/flame_pixel.svg /usr/share/niriblue/assets/

dnf5 -y install pipewire wireplumber pipewire-pulseaudio pipewire-alsa

# SOF DSP firmware for internal audio. Nearly all modern Intel laptops (Tiger Lake and
# newer) and many recent AMD ones drive their internal codec through the SOF DSP, which
# needs its firmware + topology blobs (/usr/lib/firmware/intel/sof{,-tplg}). These live
# in alsa-sof-firmware -- a separate package from linux-firmware(-all), shipped as a weak
# dep the bootc base omits. Without it the DSP never boots, the codec never registers
# (/proc/asound/cards empty), PipeWire falls back to "Dummy Output", and only external
# sinks with their own controller (eGPU/HDMI) produce sound. (Speaker-amp firmware for
# the Cirrus CS35L41/56 amps found on newer laptops comes from cirrus-audio-firmware above.)
dnf5 -y install alsa-sof-firmware

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

### Applications (external repos via system_files: zen-browser COPR)

# okular, gnome-calculator, gnome-text-editor, loupe and mpv are installed as
# Flatpaks instead (see system_files/usr/share/niriblue/flatpaks.list). vscode and
# tailscale are NOT shipped by default -- add them post-install via sysexts-manager
# (see LAYERING.md), so users who do not want them are not forced to carry them.
dnf5 -y install \
    kitty nautilus \
    kde-connect \
    wine winetricks gamemode vulkan-tools \
    file-roller unzip 7zip unrar \
    fprintd fprintd-pam \
    gnome-disk-utility gparted filelight \
    fuse fuse-libs flatpak \
    papirus-icon-theme \
    zen-browser \
    kf6-kimageformats 

# Enable fingerprint authentication (T14 reader)
authselect enable-feature with-fingerprint

# Apply the default PDF handler from mimeapps.list
update-desktop-database /usr/share/applications || true


### Desktop 2: full KDE Plasma (Wayland) as a SECOND session alongside niri
#
# niri + DMS stays the default; Plasma is added as a second, fully-featured Wayland
# session. plasma-workspace-wayland drops /usr/share/wayland-sessions/plasma.desktop,
# which the DMS greeter's session picker lists automatically (greetd still launches
# `dms-greeter --command niri`, so niri is the default and Plasma is one click away).
# dms.service is scoped to niri.service.wants, so the DMS shell never leaks into Plasma.
#
# Hand-picked package set (not the Fedora `kde-desktop-environment` group): keeps Plasma
# on clean upstream Breeze with no Fedora spin theming, and -- crucially -- avoids the
# group's webcam/Firefox/extras bloat. The login-manager handling below is the important
# part (see the masking step).
dnf5 -y install \
    plasma-workspace plasma-workspace-wayland plasma-desktop \
    plasma-systemsettings kwin-wayland \
    powerdevil kscreen plasma-nm plasma-pa bluedevil \
    plasma-systemmonitor plasma-thunderbolt plasma-disks \
    kscreenlocker kdeplasma-addons kde-cli-tools kmenuedit krunner \
    xdg-desktop-portal-kde kde-gtk-config breeze-gtk \
    kwalletmanager kfind

# CRITICAL: keep greetd as the ONE and only display manager.
#
# Fedora 44 KDE ships the new Plasma Login Manager (plasmalogin.service); installing the
# Plasma packages pulls it (and/or sddm) in, and its RPM preset ENABLES it. With greetd
# also enabled, the Plasma login manager wins the race for VT1, hijacks login, shows its
# own "Plasma Setup" first-run wizard, and the niri session never comes up. (This is
# exactly what broke both sessions on the first attempt.) Disable + mask both competing
# DMs so only the DMS greeter under greetd ever runs; mask is idempotent and works even
# if the unit is not installed, so it also blocks any future re-enable by a preset.
systemctl disable plasmalogin.service sddm.service 2>/dev/null || true
systemctl mask plasmalogin.service sddm.service 2>/dev/null || true
# Re-assert greetd as the active login manager (it was enabled earlier; make it explicit
# here so the ordering relative to the Plasma install is unambiguous).
systemctl enable greetd.service

# Core KDE application suite (native, part of a "full Plasma"): file manager, terminal,
# editor, calculator, image/document/screenshot/archive tools, scanning and media. These
# are ADDED, not swapped in -- niri keeps its existing apps (nautilus/kitty/flatpaks)
# untouched, so nothing about the working niri session changes.
dnf5 -y install \
    dolphin dolphin-plugins konsole kate kcalc \
    gwenview okular spectacle ark \
    skanpage haruna

### Software center: KDE Discover + PackageKit-bootc backend
#
# Replaces GNOME Software. Discover handles Flatpaks via plasma-discover-flatpak (Flathub
# is added on first boot by niriblue-flatpak-setup) and OS image updates via PackageKit
# (plasma-discover-packagekit). The PackageKit-bootc backend (compiled in the
# pk-bootc-builder Containerfile stage and COPY'd into the image) is reused unchanged --
# it is a generic PackageKit backend, so Discover drives it through PackageKit exactly as
# GNOME Software did. Switch PackageKit's default backend from dnf to bootc: on a bootc
# system there is no RPM layering for the dnf backend to manage.
dnf5 -y install \
    plasma-discover plasma-discover-flatpak plasma-discover-packagekit \
    PackageKit
if grep -q '^DefaultBackend=' /etc/PackageKit/PackageKit.conf; then
    sed -i 's/^DefaultBackend=.*/DefaultBackend=bootc/' /etc/PackageKit/PackageKit.conf
else
    printf '\n[Daemon]\nDefaultBackend=bootc\n' >> /etc/PackageKit/PackageKit.conf
fi

### niriblue Portal: GTK4 GUI front-end for the ujust recipes (the niriblue
### counterpart of the Bazzite Portal / ublue-os yafti-gtk). It lives in the IMAGE
### layer rather than as a Flatpak because it drives host tooling (`ujust`, bootc,
### flatpak, sysexts-manager, kitty) directly -- a sandboxed Flatpak could not.
# The script (/usr/bin/niriblue-portal), config (/usr/share/niriblue/portal/portal.yml),
# desktop entry, icon and metainfo all ship via system_files. It needs the GTK4/Adwaita
# Python bindings (PyGObject) + PyYAML; gtk4/libadwaita are already pulled in by
# nautilus but are listed here so the dependency is explicit.
dnf5 -y install python3-gobject python3-pyyaml gtk4 libadwaita
chmod 0755 /usr/bin/niriblue-portal
gtk4-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

# git stays in the image: Nix flakes / home-manager (the dev-tooling layer) expect it in
# PATH. The rest of the old Homebrew build toolchain (gcc/make/...) is gone -- per-user
# build tooling now comes from Nix, not a system-wide compiler set.
dnf5 -y install git

chmod 0755 /usr/libexec/niriblue-flatpak-setup

systemctl enable niriblue-flatpak-setup.service
systemctl enable systemd-sysext.service

### Nix (per-user dev-tooling layer; see LAYERING.md). Upstream Nix is installed at
### first boot by niriblue-nix-setup into a /var-backed store -- it cannot be baked into
### the image because /nix is machine-local state on bootc, not part of the image.

# Empty mountpoint baked into the image; niriblue-nix-setup bind-mounts the /var store here.
mkdir -p /nix

# semanage (policycoreutils-python-utils) is needed by niriblue-nix-setup to label the
# Nix store for SELinux; restorecon ships in policycoreutils (already present).
dnf5 -y install policycoreutils-python-utils

chmod 0755 /usr/libexec/niriblue-nix-setup
systemctl enable niriblue-nix-setup.service

### sysexts (add/removable native FHS apps; see LAYERING.md). systemd-sysext.service is
### already enabled above. niriblue-sysext-setup bootstraps ONLY the sysexts-manager tool
### itself at first boot (it lives in /var/lib/extensions, machine state, so it can't be
### baked into the image). niriblue ships NO sysexts by default -- users add whatever they
### want post-install with `sysexts-manager add <name> <url> && sysexts-manager enable`.
chmod 0755 /usr/libexec/niriblue-sysext-setup
systemctl enable niriblue-sysext-setup.service

### First-boot progress gate (see LAYERING.md). niriblue-firstboot runs the three setup
### steps above in sequence on the very first boot, with on-screen progress on the
### Plymouth splash, and is ordered before greetd so the desktop does not appear until it
### finishes. It always releases the gate (so no network never locks the user out); the
### standalone setup units above remain the per-boot retry net for anything unfinished.
chmod 0755 /usr/libexec/niriblue-firstboot
systemctl enable niriblue-firstboot.service

### Containers (rootless Docker) + virtualization

rpm --import https://download.docker.com/linux/fedora/gpg

dnf5 -y install \
    libvirt-daemon-kvm qemu-kvm libvirt-daemon-config-network \
    virt-manager virt-install edk2-ovmf

dnf5 -y install \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras \
    slirp4netns

# distrobox + podman: distrobox (DistroShelf flatpak is its GUI front-end) needs a
# rootless container backend to be usable by a normal account. The image's docker is
# rootful and disabled by default (opt-in via ujust), so podman -- rootless out of the
# box and distrobox's default backend -- is installed alongside so distrobox works for
# any user without setup.
dnf5 -y install distrobox podman

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
# NOTE: ID *must stay* "fedora". bootc-image-builder picks its build manifest from
# "<ID>-<VERSION_ID>" and has no ID_LIKE fallback (osbuild/bootc-image-builder#690,
# repo archived 2026-06-18), so a custom ID=niriblue breaks disk/ISO builds with
# "could not find def file for distro niriblue-44". $releasever and the COPR/RPMFusion
# repos also key on ID/VERSION_ID. The brand lives in the cosmetic fields instead
# (NAME/PRETTY_NAME/VARIANT/VARIANT_ID/URLs). /etc/os-release symlinks here, so both
# paths report the niriblue branding while ID stays Fedora-compatible.
sed -i \
    -e 's/^NAME=.*/NAME="niriblue"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="niriblue (Fedora 44)"/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="niriblue"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/jakubiszon26/niriblue"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/jakubiszon26/niriblue/issues"|' \
    /usr/lib/os-release
printf 'VARIANT="niriblue"\nVARIANT_ID=niriblue\n' >> /usr/lib/os-release
grep -q '^VARIANT_ID=niriblue$' /usr/lib/os-release  # fail the build if the rebrand didn't take

# Drop dnf/runtime leftovers so they are not baked into /var
dnf5 clean all
rm -rf /var/cache/* /var/lib/dnf/* /var/log/* /var/lib/geoclue /var/lib/rpm-state/* /tmp/* /run/* || true
