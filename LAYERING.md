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

**niriblue ships NO sysexts by default.** `niriblue-sysext-setup` only bootstraps the
`sysexts-manager` tool itself on first boot; the user installs whatever they want after
install, so nobody is forced to carry apps they do not use:

```bash
sudo sysexts-manager add vscode https://extensions.fcos.fr/community
sudo sysexts-manager enable vscode      # downloads + merges into /usr
# same pattern for tailscale, etc.
```

Use a sysext **only** for things that overlay `/usr` and can load late in boot. Do **not**
use a sysext for anything that needs `/etc` at early boot or that ships kernel modules —
sysexts overlay `/usr` (read-only) and are merged late, after early boot. A service from a
sysext (e.g. `tailscaled`) is fine because it is enabled/started late, not at early boot.

### 3. Nix — per-user profile (upstream Nix + home-manager)
Self-contained CLI / dev tooling, declarative and per-user, no image rebuild. **This
replaces distrobox and Homebrew.** Installed at first boot by `niriblue-nix-setup` into a
`/var`-backed store mounted at `/nix` (survives bootc upgrades). `niriblue-nix-setup` also
turns on `nix-command` + `flakes` (in `/etc/nix/nix.custom.conf`), so flakes work out of
the box.

Each user opts into home-manager once with `ujust setup-home-manager`: it seeds the
`/etc/skel` starter (also into accounts that predate it), fills in the account, and runs
the first `home-manager switch`. After that, edit `~/.config/home-manager/home.nix` and
re-run `home-manager switch --flake ~/.config/home-manager#niriblue` (or `ujust update`).

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

## First boot

The sysext, Nix and Flatpak layers install at **first boot**, not at image build (they
live in `/var`, which is machine-local state on bootc). `niriblue-firstboot` runs the
three steps in sequence while the Plymouth splash is still up and **before the greeter**,
so the desktop only appears once setup is done, with on-screen progress. (For the sysext
step this means only the `sysexts-manager` tool itself — niriblue installs no sysexts by
default; see layer 2.)

It is resilient by design:

- It **always** releases to the desktop (even if a step fails or there is no network on
  first boot) — you are never locked out.
- Anything unfinished is retried on **every later boot** by the standalone
  `niriblue-{flatpak,sysext,nix}-setup.service` units (idempotent, marker-guarded), which
  are ordered after `niriblue-firstboot` so they never race it.

Flatpak is the long pole; if a faster first boot is preferred, move it out of the gate in
`/usr/libexec/niriblue-firstboot` and let it stream in after the desktop instead.

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
account (created on an earlier image) will not have it. `ujust setup-home-manager` handles
both cases: it `cp -n`'s the starter from `/etc/skel` if missing, fills in the account,
and runs the first switch — so existing accounts just run the same command.

