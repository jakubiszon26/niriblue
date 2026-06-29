# niriblue
![logo](https://github.com/jakubiszon26/niriblue/blob/main/assets/niriblue_logo.png)
My custom [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/) desktop image: a first-class **KDE Plasma** (Wayland) desktop with the [niri](https://github.com/YaLTeR/niri) compositor + [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) kept as a second-class, Dvorak-first session. Highly opinionated.

`ghcr.io/jakubiszon26/niriblue:latest` (cosign-signed)

## Highlights

- **Base:** `fedora-bootc:44` with the **CachyOS kernel** + `cachyos-settings`, `scx` schedulers, and `ananicy-cpp`.
- **Desktops:** **full KDE Plasma Wayland — first-class**, with its own display manager, Fedora 44's **Plasma Login Manager** (clean upstream Breeze, no Fedora theming). The **niri + DankMaterialShell** session is kept as a second-class, selectable session (dvorak-first keybinds). PLM is the single login manager; greetd/DMS-greeter and SDDM are disabled.
- **Apps:** KDE is the default ecosystem, native — Dolphin, Kate, KCalc, Gwenview, Okular, Spectacle, Ark, Skanpage, Haruna, KDE Partition Manager (no more GNOME apps/Flatpaks). Plus Kitty, Zen, KDE Connect, virt-manager and a few cross-desktop Flatpaks (LibreOffice, Flatseal, …) on first boot.
- **Software center:** KDE **Discover** (Flatpaks via Flathub + OS image updates through the PackageKit-bootc backend; update notifier enabled).
- **Hardware:** Mesa + Vulkan, VA-API (Intel + AMD freeworld), full ffmpeg, Thunderbolt (`bolt`), fingerprint auth, HP printers (`hplip`).
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
- `system_files/` — files copied into the image root (configs, repos, units, niri/DMS skel).
- `Justfile` / `ujust` — build and helper recipes.
- **niriblue Portal** — a GTK4 GUI for the `ujust` recipes (run `ujust portal` or launch "niriblue Portal" from the app menu). Adapted from the [Bazzite Portal](https://github.com/ublue-os/yafti-gtk); its tabs/actions live in `system_files/usr/share/niriblue/portal/portal.yml`.

## Disclaimer
This is a personal project built for my own setup. It's public in case it's useful to someone, but it comes with no support, no guarantees, and no promise of stability.
