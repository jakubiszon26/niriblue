# niriblue recipes — run with: ujust <recipe>
# Some recipes are adapted from ublue-os/bazzite (MIT), trimmed for a plain
# Fedora bootc + niri system (no gum / ublue helpers).

# List available recipes
default:
    @just --justfile /usr/share/niriblue/just/niriblue.just --list

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
