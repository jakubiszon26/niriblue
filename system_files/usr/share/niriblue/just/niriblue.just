# niriblue recipes — run with: ujust <recipe>
# Some recipes are adapted from ublue-os/bazzite (MIT), trimmed for a plain
# Fedora bootc + niri system (no gum / ublue helpers).

# List available recipes
default:
    @just --justfile /usr/share/niriblue/just/niriblue.just --list

# Update everything: system image, flatpaks, Homebrew
update:
    #!/usr/bin/bash
    set -uo pipefail
    echo ">> System image (bootc)"
    sudo bootc upgrade
    echo ">> Flatpaks"
    flatpak update -y || true
    if [ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]; then
        echo ">> Homebrew"
        /var/home/linuxbrew/.linuxbrew/bin/brew update && /var/home/linuxbrew/.linuxbrew/bin/brew upgrade || true
    fi

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
