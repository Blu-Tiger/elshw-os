#!/bin/bash
set -e

mkdir -p ./build
cd build

KERNEL_VERSION="6.19.12"
ALPINE_VERSION="3.23.3"
LIMLINE_VERSION="11"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-minirootfs-${ALPINE_VERSION}-x86_64.tar.gz"
SCRIPT_VERSION="0.1"
INITRAMFS_DIR="$(pwd)/initramfs"
KERNEL_SRC="$(pwd)/linux-${KERNEL_VERSION}"
KERNEL_FILE="${KERNEL_SRC}/arch/x86/boot/bzImage"
ISO_NAME="elshw-l${LIMLINE_VERSION}-k${KERNEL_VERSION}-a${ALPINE_VERSION}-v${SCRIPT_VERSION}.iso"
STAGING_DIR="iso_staging"

RESET="\e[0m"; BOLD="\e[1m"; DIM="\e[2m"
RED="\e[1;31m"; GREEN="\e[1;32m"; YELLOW="\e[1;33m"; CYAN="\e[1;36m"; WHITE="\e[1;37m"


check_commands() {
    echo -e "${CYAN}${BOLD}▶ Checking required commands...${RESET}"
    local missing=()

    for cmd in wget tar make gcc mtools mkfs.fat xorriso; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ! command -v grub-mkrescue &>/dev/null && ! command -v grub2-mkrescue &>/dev/null; then
        missing+=("grub-mkrescue / grub2-mkrescue")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}✖ Missing required commands: ${missing[*]}${RESET}"
        echo -e "${YELLOW}Please install the missing dependencies manually and run the script again.${RESET}"
        exit 1
    fi

    if command -v grub-mkrescue &>/dev/null; then
        export GRUB_MKRESCUE_CMD="grub-mkrescue"
    else
        export GRUB_MKRESCUE_CMD="grub2-mkrescue"
    fi

    echo -e "  ${GREEN}All commands available.${RESET}"
}

check_commands

if [ ! -f "alpine-minirootfs-${ALPINE_VERSION}-x86_64.tar.gz" ]; then
    echo -e "${CYAN}${BOLD}▶ Downloading Alpine minirootfs...${RESET}"
    wget -q --show-progress "$ALPINE_URL"
fi

echo -e "${CYAN}${BOLD}▶ Extracting Alpine rootfs...${RESET}"
mkdir -p "$INITRAMFS_DIR"
sudo tar -xf alpine-minirootfs-${ALPINE_VERSION}-x86_64.tar.gz -C "$INITRAMFS_DIR" \
    --exclude="./init" \
    --exclude="./elshw.sh"
sudo cp /etc/resolv.conf "$INITRAMFS_DIR/etc/"

echo -e "${CYAN}${BOLD}▶ Installing packages in chroot...${RESET}"
sudo chroot "$INITRAMFS_DIR" /bin/sh -c \
    "export PATH=/usr/bin:/usr/sbin:/bin:/sbin && \
     apk update && \
     apk add bash dmidecode pciutils util-linux iw iproute2 acpid"
sudo rm -f "$INITRAMFS_DIR/etc/resolv.conf"

echo -e "${CYAN}${BOLD}▶ Stripping initramfs...${RESET}"
SIZE_BEFORE=$(sudo du -sh "$INITRAMFS_DIR" | cut -f1)
sudo rm -rf \
    "$INITRAMFS_DIR/usr/lib/apk" \
    "$INITRAMFS_DIR/var/cache/apk" \
    "$INITRAMFS_DIR/etc/apk" \
    "$INITRAMFS_DIR/sbin/apk" \
    "$INITRAMFS_DIR/usr/share/man" \
    "$INITRAMFS_DIR/usr/share/doc" \
    "$INITRAMFS_DIR/usr/share/locale" \
    "$INITRAMFS_DIR/usr/share/zoneinfo" \
    "$INITRAMFS_DIR/usr/lib/libunistring.so.*" \
    "$INITRAMFS_DIR/usr/lib/libbrotlienc.so.*" \
    "$INITRAMFS_DIR/usr/lib/libzstd.so.*" \
    "$INITRAMFS_DIR/usr/lib/libcurl.so.*" \
    "$INITRAMFS_DIR/usr/lib/libssl.so.*" \
    "$INITRAMFS_DIR/usr/lib/libcrypto.so.*"
SIZE_AFTER=$(sudo du -sh "$INITRAMFS_DIR" | cut -f1)

echo ""
echo "  Before:" "$SIZE_BEFORE"
echo "  After:"  "$SIZE_AFTER"
echo ""

echo -e "${CYAN}${BOLD}▶ Configuring ACPI power button...${RESET}"
sudo mkdir -p "$INITRAMFS_DIR/etc/acpi/PWRF"
printf '#!/bin/sh\npoweroff -f\n' | sudo tee "$INITRAMFS_DIR/etc/acpi/PWRF/00000080" > /dev/null
sudo chmod +x "$INITRAMFS_DIR/etc/acpi/PWRF/00000080"

sudo mkdir -p "$INITRAMFS_DIR/etc/acpi/events"
sudo cat << 'EOF' | sudo tee "$INITRAMFS_DIR/etc/acpi/events/powerbtn" > /dev/null
event=button/power.*
action=/etc/acpi/PWRF/00000080
EOF


echo -e "${CYAN}${BOLD}▶ Installing init and elshw.sh...${RESET}"
sudo cp ../src/fs-init "$INITRAMFS_DIR/init"
sudo cp ../elshw.sh "$INITRAMFS_DIR/elshw.sh"
sudo chmod +x "$INITRAMFS_DIR/init" "$INITRAMFS_DIR/elshw.sh"
sudo sed -i 's/\r$//' "$INITRAMFS_DIR/init" "$INITRAMFS_DIR/elshw.sh"

if [ ! -d "$KERNEL_SRC" ]; then
    echo -e "${CYAN}${BOLD}▶ Downloading Linux kernel ${KERNEL_VERSION}...${RESET}"
    wget -c -q --show-progress "$KERNEL_URL"
    echo -e "${CYAN}${BOLD}▶ Extracting kernel source...${RESET}"
    tar -xf "linux-${KERNEL_VERSION}.tar.xz"
fi

sudo chown -R $(whoami):$(whoami) . 2>/dev/null || true

sudo chown -R $(whoami):$(whoami) "$INITRAMFS_DIR"

cd "$KERNEL_SRC"
echo -e "${CYAN}${BOLD}▶ Applying kernel config...${RESET}"
cp ../../src/kernel-config .config
scripts/config --set-str CONFIG_INITRAMFS_SOURCE "$INITRAMFS_DIR"
make olddefconfig

echo -e "${CYAN}${BOLD}▶ Compiling kernel with $(nproc) threads...${RESET}"
make -j$(nproc) bzImage 2>&1 | tee ../build.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo -e "${RED}${BOLD}✖ Kernel build failed. Check build.log:${RESET}"
    grep -E "error:|fatal:" ../build.log | head -20
    exit 1
fi
cd ..

echo -e "${CYAN}${BOLD}▶ Building ISO...${RESET}"
rm -rf "$STAGING_DIR"
if [ ! -d "limine" ]; then
    echo -e "${CYAN}${BOLD}▶ Downloading Limine bootloader...${RESET}"
    git clone https://github.com/limine-bootloader/limine.git --branch v${LIMLINE_VERSION}.x-binary --depth=1

    echo -e "${CYAN}${BOLD}▶ Compiling Limine host utility...${RESET}"
    make -C limine
fi
mkdir -p "$STAGING_DIR/boot"
mkdir -p "$STAGING_DIR/boot/limine"
mkdir -p "$STAGING_DIR/EFI/BOOT"

cp "$KERNEL_FILE" "$STAGING_DIR/boot/vmlinuz"
cp ../src/limine.conf "$STAGING_DIR/boot/limine/limine.conf"

cp -v limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin "$STAGING_DIR/boot/limine/"

cp -v limine/BOOTX64.EFI "$STAGING_DIR/EFI/BOOT/"
cp -v limine/BOOTIA32.EFI "$STAGING_DIR/EFI/BOOT/"

mkdir -p ../iso
echo -e "${CYAN}${BOLD}▶ Generating Limine ISO...${RESET}"

rm -r "../iso/$ISO_NAME"

xorriso -as mkisofs -b boot/limine/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/limine/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$STAGING_DIR" -o "../iso/$ISO_NAME"

./limine/limine bios-install "../iso/$ISO_NAME"
rm -rf "$STAGING_DIR"

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║       ✔ Build complete!              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${RESET}"
ls -lh "../iso/$ISO_NAME"
