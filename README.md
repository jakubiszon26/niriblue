# niriblue
![logo](https://github.com/jakubiszon26/niriblue/blob/main/assets/niriblue_logo.png)
My custom [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/) desktop image built around the [niri](https://github.com/YaLTeR/niri) compositor and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), highly opinionated, Dvorak-first.

`ghcr.io/jakubiszon26/niriblue:latest` (cosign-signed)

## Highlights

- **Base:** `fedora-bootc:44` with the **CachyOS kernel** + `cachyos-settings`, `scx` schedulers, and `ananicy-cpp`.
- **Desktops:** niri + DankMaterialShell (default) **and a full KDE Plasma Wayland session** — pick either from the DMS greeter's session list. Clean upstream Breeze, no Fedora theming. `greetd` with the DMS greeter and dvorak-first keybinds.
- **Hardware:** Mesa + Vulkan, VA-API (Intel + AMD freeworld), full ffmpeg, Thunderbolt (`bolt`), fingerprint auth, HP printers (`hplip`).
- **Gaming:** Steam gamescope session and wine.
- **Apps:** KDE is the default app ecosystem — Dolphin, Kate, KCalc, Gwenview, Okular, Spectacle, Ark, Skanpage, Haruna ship natively; plus Kitty, Zen, KDE Connect, virt-manager and a few cross-desktop Flatpaks (LibreOffice, Flatseal, …) installed on first boot.
- **Software center:** KDE **Discover** (Flatpaks via Flathub + OS image updates through the PackageKit-bootc backend).
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
