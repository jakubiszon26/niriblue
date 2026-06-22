# niriblue recipes — run with: ujust <recipe>
# Some recipes are adapted from ublue-os/bazzite (MIT), trimmed for a plain
# Fedora bootc + niri system (no gum / ublue helpers).

# List available recipes
default:
    @just --justfile /usr/share/niriblue/just/niriblue.just --list

# Open the niriblue Portal (GUI for these recipes)
portal:
    setsid niriblue-portal /usr/share/niriblue/portal/portal.yml >/dev/null 2>&1 &

# Update everything: system image, flatpaks, sysexts, Nix/home-manager
update:
    #!/usr/bin/bash
    set -uo pipefail
    echo ">> System image (bootc)"
    sudo bootc upgrade
    echo ">> Flatpaks"
    flatpak update -y || true
    if command -v sysexts-manager >/dev/null; then
        echo ">> sysexts"
        sudo sysexts-manager update || true
    fi
    if command -v nix >/dev/null; then
        echo ">> Nix"
        nix profile upgrade --all || true
    fi
    if command -v home-manager >/dev/null; then
        echo ">> home-manager"
        home-manager switch --flake "$HOME/.config/home-manager#niriblue" || true
    fi

# Set up home-manager for the current user (one-time; opt-in dev-tooling layer)
setup-home-manager:
    #!/usr/bin/bash
    set -euo pipefail
    if ! command -v nix >/dev/null; then
        echo "Nix is not installed yet -- first-boot setup may still be running."
        echo "Check it with:  systemctl status niriblue-nix-setup"
        exit 1
    fi
    cfg="$HOME/.config/home-manager"
    mkdir -p "$cfg"
    # Seed the starter for accounts that predate it (/etc/skel only reaches NEW accounts).
    cp -n /etc/skel/.config/home-manager/flake.nix "$cfg/flake.nix" 2>/dev/null || true
    cp -n /etc/skel/.config/home-manager/home.nix  "$cfg/home.nix"  2>/dev/null || true
    # Fill in this account (replaces the CHANGEME placeholder; a no-op once it is set).
    sed -i "s/CHANGEME/$USER/g" "$cfg/home.nix"
    echo ">> Activating home-manager (first run downloads nixpkgs + home-manager)…"
    nix run github:nix-community/home-manager -- switch -b backup --flake "$cfg#niriblue"
    echo "Done. Edit ~/.config/home-manager/home.nix, then: home-manager switch --flake ~/.config/home-manager#niriblue"

# Reclaim space: prune containers, unused flatpaks, and old journal logs
clean-system:
    #!/usr/bin/bash
    set -uo pipefail
    podman system prune -af || true
    podman volume prune -f || true
    flatpak uninstall --unused -y || true
    sudo journalctl --vacuum-time=7d || true
    echo "Done."

# Roll back to the previous system deployment
rollback:
    #!/usr/bin/bash
    set -uo pipefail
    bootc status || true
    sudo bootc rollback
    echo "Rollback staged. Reboot to apply: systemctl reboot"

# Reboot directly into the BIOS/UEFI setup screen
bios:
    systemctl reboot --firmware-setup

# Show system/hardware info
device-info:
    fastfetch

# Kill stuck wine/proton processes (gaming)
fix-proton-hang:
    #!/usr/bin/bash
    pkill -9 -if wine || true
    pkill -9 -if proton || true
    echo "Killed stuck wine/proton processes."

# Add the current user to libvirt/kvm groups and start libvirtd
setup-virtualization:
    #!/usr/bin/bash
    set -euo pipefail
    sudo usermod -aG libvirt,kvm "$USER"
    sudo systemctl enable --now libvirtd.service
    echo "Added $USER to libvirt,kvm — log out and back in for it to take effect."

# Initialize rootless Docker for the current user (one-time)
setup-docker-rootless:
    #!/usr/bin/bash
    set -euo pipefail
    dockerd-rootless-setuptool.sh install
    systemctl --user enable --now docker.service
    sudo loginctl enable-linger "$USER"
    echo "Rootless Docker is ready."

# Run Ollama (AMD ROCm/GPU) in Docker; needs setup-docker-rootless first
setup-ollama:
    #!/usr/bin/bash
    set -euo pipefail
    if ! docker info >/dev/null 2>&1; then
        echo "Docker is not running. Run 'ujust setup-docker-rootless' first."
        exit 1
    fi
    docker pull docker.io/ollama/ollama:rocm
    docker rm -f ollama 2>/dev/null || true
    docker run -d --restart=always --name ollama \
        --device /dev/kfd --device /dev/dri \
        --group-add video --security-opt seccomp=unconfined \
        -v ollama:/root/.ollama \
        -p 127.0.0.1:11434:11434 \
        docker.io/ollama/ollama:rocm
    echo "Ollama is up on 127.0.0.1:11434 — e.g. docker exec -it ollama ollama run llama3.2"
    echo "If the GPU is not used (RX 7600M XT/gfx1102), add: -e HSA_OVERRIDE_GFX_VERSION=11.0.0"

# Stop and remove the Ollama container (keeps the models volume)
remove-ollama:
    #!/usr/bin/bash
    docker rm -f ollama 2>/dev/null || true
    echo "Ollama container removed."

# ---------------------------------------------------------------------------
# Optional apps (opt-in; none of this is in the image — see LAYERING.md).
# Userspace tools, distrobox, and add/removable system extensions (sysexts).
# ---------------------------------------------------------------------------

# Install distrobox into ~/.local (userspace, per-user; no image rebuild)
install-distrobox:
    #!/usr/bin/bash
    set -euo pipefail
    curl -fsSL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix "$HOME/.local"
    echo "distrobox installed to ~/.local/bin."
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) echo "Note: ~/.local/bin is not on your PATH yet — log out/in or add it." ;;
    esac

# Install JetBrains Toolbox into ~/.local (userspace; self-installs on first launch)
install-jetbrains-toolbox:
    #!/usr/bin/bash
    set -euo pipefail
    echo ">> Finding the latest JetBrains Toolbox release…"
    url="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release&platform=linux' \
            | grep -oP '"linux":\s*\{\s*"link":\s*"\K[^"]+')"
    if [ -z "${url:-}" ]; then
        echo "Could not determine the download URL (JetBrains API unreachable?)." >&2
        exit 1
    fi
    tmp="$(mktemp -d)"
    echo ">> Downloading $url"
    curl -fsSL "$url" -o "$tmp/toolbox.tar.gz"
    tar -xzf "$tmp/toolbox.tar.gz" -C "$tmp"
    bin="$(ls "$tmp"/jetbrains-toolbox-*/jetbrains-toolbox | head -1)"
    echo ">> Launching Toolbox once so it installs itself to ~/.local/share/JetBrains…"
    setsid "$bin" >/dev/null 2>&1 &
    echo "JetBrains Toolbox is starting; it adds its own app-menu entry and autostart."

# Install a community system extension (native /usr app). e.g. ujust install-sysext vscode
install-sysext name="":
    #!/usr/bin/bash
    set -euo pipefail
    NAME="{{name}}"
    if [ -z "$NAME" ]; then
        echo "Usage: ujust install-sysext <name>"
        echo "Community sysexts include:"
        echo "  vscode  tailscale  google-chrome  mullvad-vpn  bitwarden"
        echo "  nordvpn  nordvpn-gui  1password-cli  1password-gui"
        exit 1
    fi
    if ! command -v sysexts-manager >/dev/null; then
        echo "sysexts-manager is not ready yet (first-boot setup may still be running)."
        echo "Check it with:  systemctl status niriblue-sysext-setup"
        exit 1
    fi
    CHANNEL="https://extensions.fcos.fr/community"
    echo ">> Adding $NAME from the community channel…"
    sudo sysexts-manager add "$NAME" "$CHANNEL"
    echo ">> Enabling $NAME…"
    sudo sysexts-manager enable "$NAME"
    echo ">> Merging into /usr…"
    sudo sysexts-manager refresh
    echo "Done. $NAME is installed. Update it later with: ujust update"

# Remove a system extension previously installed with install-sysext
remove-sysext name="":
    #!/usr/bin/bash
    set -euo pipefail
    NAME="{{name}}"
    if [ -z "$NAME" ]; then
        echo "Usage: ujust remove-sysext <name>"
        exit 1
    fi
    sudo sysexts-manager disable "$NAME" || true
    sudo sysexts-manager remove "$NAME"
    sudo sysexts-manager refresh
    echo "Removed $NAME."

# List system extensions managed by sysexts-manager
list-sysexts:
    sysexts-manager status

# Install VS Code as a system extension
install-vscode: (install-sysext "vscode")

# Install Tailscale (tailscaled + CLI) as a system extension
install-tailscale: (install-sysext "tailscale")
    #!/usr/bin/bash
    set -euo pipefail
    echo ">> Enabling tailscaled…"
    sudo systemctl enable --now tailscaled.service
    echo "Tailscale is up. Connect with:  sudo tailscale up"

# Install NordVPN (daemon/CLI + GUI) as system extensions
install-nordvpn: (install-sysext "nordvpn") (install-sysext "nordvpn-gui")
    #!/usr/bin/bash
    set -euo pipefail
    echo ">> Enabling nordvpnd…"
    sudo systemctl enable --now nordvpnd.service || true
    sudo usermod -aG nordvpn "$USER" || true
    echo "NordVPN installed. Log out/in for the nordvpn group, then: nordvpn login"

# Install DaVinci Resolve in a distrobox container (adapted from bazzite / zelikos/davincibox)
install-davincibox:
    #!/usr/bin/bash
    set -euo pipefail
    # distrobox is userspace here, so it may not be on PATH — resolve it explicitly.
    if command -v distrobox >/dev/null; then
        DBX=distrobox
    elif [ -x "$HOME/.local/bin/distrobox" ]; then
        DBX="$HOME/.local/bin/distrobox"
    else
        echo "distrobox is not installed. Run 'ujust install-distrobox' first."
        exit 1
    fi
    IMAGE="ghcr.io/zelikos/davincibox-opencl:latest"   # OpenCL build: works on Intel + AMD
    CONTAINER="davincibox"
    # The DaVinci Resolve installer is not redistributable — the user downloads it.
    ZIP="$(ls -1t "$HOME"/Downloads/DaVinci_Resolve_*.zip "$HOME"/DaVinci_Resolve_*.zip 2>/dev/null | head -1 || true)"
    if [ -z "$ZIP" ]; then
        echo "Could not find a DaVinci Resolve installer .zip."
        echo "Download the Linux installer from"
        echo "  https://www.blackmagicdesign.com/products/davinciresolve"
        echo "place the (still zipped) .zip in ~/Downloads, then re-run this."
        exit 1
    fi
    echo ">> Creating the davincibox container (first run pulls the image)…"
    "$DBX" create -i "$IMAGE" -n "$CONTAINER" -Y || true
    work="$(mktemp -d)"
    echo ">> Unpacking $ZIP…"
    unzip -o -q "$ZIP" -d "$work"
    RUN="$(ls -1 "$work"/DaVinci_Resolve_*.run | head -1)"
    ( cd "$work" && "$RUN" --appimage-extract >/dev/null )
    echo ">> Installing DaVinci Resolve inside the container (this is slow)…"
    "$DBX" enter "$CONTAINER" -- setup-davinci "$work/squashfs-root/AppRun" distrobox
    rm -rf "$work"
    echo "Done. DaVinci Resolve was exported to your app menu."
