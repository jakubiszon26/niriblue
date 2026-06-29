# niriblue
![logo](https://github.com/jakubiszon26/niriblue/blob/main/assets/niriblue_logo.png)
My custom [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/) desktop image: a **Plasma-first** KDE (Wayland) desktop tuned for the most consistent Breeze experience and broad hardware support, with a Steam gamescope session for gaming. Highly opinionated.

`ghcr.io/jakubiszon26/niriblue:latest` (cosign-signed)

> **Note on the name:** the image keeps the `niriblue` name (and `ghcr.io` path, cosign key,
> branding) for continuity, but it is now a pure KDE Plasma image — the old niri +
> DankMaterialShell session has been removed.

## Highlights

- **Base:** `fedora-bootc:44` with the **CachyOS kernel** + `cachyos-settings`, `scx` schedulers, and `ananicy-cpp`.
- **Desktop:** **full KDE Plasma Wayland** — the one and only desktop, on clean upstream **Breeze** (no Fedora spin theming). Login is handled by Fedora 44's **Plasma Login Manager** (PLM, a Breeze-only fork of SDDM), the single display manager. The **Steam/gamescope** session stays selectable from the login screen.
- **System Settings, no CLI required:** the full set of Plasma KCMs is installed so the whole machine is configurable from the GUI — Info Center, Printers (`print-manager`), Firewall (`plasma-firewall` + firewalld), Colour Management (`colord-kde`), Drawing Tablet, Thunderbolt, Disks/SMART, Online Accounts (`kaccounts`), Encrypted Vaults (`plasma-vault`), Network, Bluetooth, Power, GTK app theming and the login screen itself.
- **Apps:** KDE is the native default ecosystem — Dolphin, Konsole, Kate, KCalc, Gwenview, Okular, Spectacle, Ark, Skanpage, Haruna, KDE Partition Manager. Plus Zen, KDE Connect, virt-manager and a few cross-desktop Flatpaks (LibreOffice, Flatseal, …) on first boot.
- **Software center:** KDE **Discover** for Flatpaks (Flathub). **OS image updates apply automatically** via bootc's `bootc-fetch-apply-updates.timer` (staged in the background, applied on the next reboot) — no terminal, no fragile PackageKit backend. `ujust update` / the Portal remain for on-demand updates.
- **Hardware:** Mesa + Vulkan, VA-API (Intel + AMD freeworld), full ffmpeg, the complete consumer device-firmware set + microcode, Thunderbolt (`bolt`), fingerprint auth, Bluetooth, fwupd/thermald/ModemManager. **Peripherals:** printers (`cups`, `ipp-usb`, `gutenprint`, `hplip`), scanners (`sane` + `sane-airscan`), and drawing tablets (`libwacom` + Plasma's Drawing Tablet KCM).
- **Localisation:** the full glibc locale set (`glibc-all-langpacks`) so any language/region is selectable from System Settings; hunspell spell-check (en/pl).
- **Gaming:** Steam gamescope session and wine.
- **Extras:** rootless Docker (opt-in), libvirt/KVM, Nix + home-manager, Flatpak/Flathub, `sysexts-manager` (add/removable system extensions — none installed by default), `ujust` recipes + **niriblue Portal** (a GTK GUI front-end for them).

## Usage

Rebase an existing Fedora bootc system:

```bash
sudo bootc switch ghcr.io/jakubiszon26/niriblue:latest
sudo systemctl reboot
```

## Layout

- `Containerfile` — image definition.
- `build_files/build.sh` — all package installs and system setup.
- `system_files/` — files copied into the image root (configs, repos, units, skel).
- `Justfile` / `ujust` — build and helper recipes.
- **niriblue Portal** — a GTK4 GUI for the `ujust` recipes (run `ujust portal` or launch "niriblue Portal" from the app menu). Adapted from the [Bazzite Portal](https://github.com/ublue-os/yafti-gtk); its tabs/actions live in `system_files/usr/share/niriblue/portal/portal.yml`.

## Disclaimer
This is a personal project built for my own setup. It's public in case it's useful to someone, but it comes with no support, no guarantees, and no promise of stability.
