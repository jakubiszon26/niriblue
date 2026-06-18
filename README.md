# niriblue
![logo](https://github.com/jakubiszon26/niriblue/blob/main/assets/niriblue_logo.png)
My custom [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/) desktop image built around the [niri](https://github.com/YaLTeR/niri) compositor and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), tuned for a ThinkPad T14 and my personal use.

`ghcr.io/jakubiszon26/niriblue:latest` (cosign-signed)

## Highlights

- **Base:** `fedora-bootc:44` with the **CachyOS kernel** + `cachyos-settings`, `scx` schedulers, and `ananicy-cpp`.
- **Desktop:** niri + DankMaterialShell, `greetd` with the DMS greeter.
- **Hardware:** Mesa + Vulkan, VA-API (Intel + AMD freeworld), full ffmpeg, Thunderbolt (`bolt`), fingerprint auth.
- **Gaming:** Steam gamescope session and wine.
- **Apps:** RPMs (Kitty, Nautilus, Zen, VS Code, KDE Connect, virt-manager, …) plus various Flatpaks installed on first boot.
- **Extras:** Tailscale, rootless Docker (opt-in), libvirt/KVM, Homebrew, Flatpak/Flathub, `ujust` recipes.

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
