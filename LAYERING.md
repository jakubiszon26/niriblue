# Software layering in niriblue

Software in niriblue is placed in one of four layers, chosen by **depth of system
integration**: the deeper something has to hook into boot/kernel/userspace, the closer
to the image it lives. Keep future build edits consistent with this rule.

## The four layers

### 1. IMAGE — `Containerfile` + `build_files/build.sh`
Foundational, early-boot, kernel and driver-level pieces, and the desktop shell itself.
Anything that must exist before/while userspace comes up, or that cannot be a late-boot
`/usr` overlay, belongs here.

Examples in this image: the CachyOS **kernel**, the full **device-firmware** set +
microcode, **niri** + **DankMaterialShell** + greeter, XDG
**portals**, **eGPU**/Thunderbolt bits (`bolt`, kargs), audio stack, the hardware
daemons (fwupd/thermald/bluez/cups/sane/ModemManager), the Steam/gamescope session,
`libvirt`. These need `/etc` and units present at early boot and/or ship kernel modules,
so they cannot move to a sysext.

### 2. systemd-sysext — `sysexts-manager`, community channel
Native FHS apps that want system integration but should be **add/removable without
rebuilding the image**. Managed at runtime via `sysexts-manager`
(`extensions.fcos.fr/community`); images live in `/var/lib/extensions` (machine state).

In this image: **vscode**, **tailscale**. Bootstrapped on first boot by
`niriblue-sysext-setup`.

Use a sysext **only** for things that overlay `/usr` and can load late in boot. Do **not**
use a sysext for anything that needs `/etc` at early boot or that ships kernel modules —
sysexts overlay `/usr` (read-only) and are merged late, after early boot. A service from a
sysext (e.g. `tailscaled`) is fine because it is enabled/started late, not at early boot.

### 3. Nix — per-user profile (upstream Nix + home-manager)
Self-contained CLI / dev tooling, declarative and per-user, no image rebuild. **This
replaces distrobox and Homebrew.** Installed at first boot by `niriblue-nix-setup` into a
`/var`-backed store mounted at `/nix` (survives bootc upgrades).

### 4. Flatpak — GUI apps
Sandboxed graphical applications. Flathub + the app list are set up on first boot by
`niriblue-flatpak-setup` (`/usr/share/niriblue/flatpaks.list`). Already in place; leave it.

## Decision guide

| Need | Layer |
|------|-------|
| Kernel, driver, firmware, compositor, portal, early-boot unit | **IMAGE** |
| Native `/usr` app, late-boot, must be add/removable without rebuild | **sysext** |
| CLI / dev tool, per-user, declarative | **Nix** |
| Sandboxed GUI app | **Flatpak** |

## Gotchas

### sysexts are enabled statically in `/var` across deployments
sysexts managed by `sysexts-manager` are enabled in `/var`, which is shared by **all**
bootc deployments. Consequences:

- **After a major Fedora rebase** (e.g. 44 → 45), sysexts must be **updated to match the
  new release** (`sudo sysexts-manager update`) — a sysext built for f44 will not match
  f45. Plan to refresh them as part of any major rebase.
- **update-then-rollback breaks them**: if you update sysexts and then roll the image back
  to a previous deployment, the (newer) sysexts may no longer match and can fail to load,
  because the enablement lives in `/var`, not per-deployment.

### home-manager starter only reaches NEW accounts
The starter under `/etc/skel/.config/home-manager/` is copied by `useradd`, so it only
lands in homes of accounts created **after** it shipped. An **existing** `/var/home`
account (created on an earlier image) will not have it. To seed an existing home:

```bash
mkdir -p ~/.config/home-manager
cp -n /etc/skel/.config/home-manager/{flake.nix,home.nix} ~/.config/home-manager/
# edit home.nix: set home.username / home.homeDirectory to your account, then:
home-manager switch --flake ~/.config/home-manager#niriblue
```

### Transitional: vscode/tailscale exist as both RPM and sysext
Currently `code` and `tailscale` are installed as RPMs **and** provided as sysexts (the
sysext overlays `/usr` and shadows the RPM binaries). The RPMs + their repos are removed
in a later change, only after the sysext path is verified on a real boot — so there is
never a window without an editor or VPN.
