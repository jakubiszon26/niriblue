# niriblue software layering (IMAGE / systemd-sysext / Nix / Flatpak) is documented in
# LAYERING.md at the repo root. Read it before adding software here: only foundational,
# early-boot, kernel/driver and compositor pieces belong in this image; late-boot native
# apps go to sysexts, per-user CLI/dev tooling to Nix, and GUI apps to Flatpak.

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY assets /assets

# Build the PackageKit-bootc backend from source -- it has no RPM or COPR, only a
# meson build that vendors PackageKit's internal backend headers via a submodule.
# Done in a throwaway stage so the toolchain (meson/ninja/gcc/-devel) never lands
# in the final image; only the built .so + python helper are COPY'd across. Same
# fedora-bootc:44 base as the final image so the backend compiles against the exact
# PackageKit ABI it will be loaded by at runtime. It is a generic PackageKit backend,
# so KDE Discover (plasma-discover-packagekit) drives OS image updates through it.
FROM quay.io/fedora/fedora-bootc:44 AS pk-bootc-builder
RUN dnf5 -y install git gcc meson ninja-build pkgconf-pkg-config \
        PackageKit-devel glib2-devel && \
    git clone --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/FyraLabs/PackageKit-bootc.git /src && \
    cd /src && \
    meson setup builddir --prefix=/usr --buildtype=release && \
    meson compile -C builddir && \
    DESTDIR=/out meson install -C builddir

# Base Image
FROM quay.io/fedora/fedora-bootc:44
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### PackageKit-bootc backend (compiled in the pk-bootc-builder stage above).
## libpk_backend_bootc.so -> /usr/lib64/packagekit-backend/, bootcBackend.py ->
## /usr/share/PackageKit/helpers/bootc/. PackageKit is switched to this backend
## (DefaultBackend=bootc) inside build.sh, and KDE Discover drives it.
COPY --from=pk-bootc-builder /out/ /

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
