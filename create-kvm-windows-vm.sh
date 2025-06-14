#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -eo pipefail

# ===================================================================================
# **README**
# ===================================================================================
# KVM Windows Installer for Ubuntu - Enhanced Edition
#
# Description:
#   This script automates the creation of a KVM virtual machine for Windows.
#   It handles dependency checks, driver downloads, and VM creation with
#   optimized settings for performance and compatibility.
#
# Features:
#   - Dependency validation and automatic installation.
#   - Automatic download of VirtIO drivers for best performance.
#   - Interactive prompts for easy setup.
#   - Command-line flags for automation and advanced configuration.
#   - Pre-flight checks for KVM support and network status.
#   - Optimized `virt-install` command for modern Windows (10/11).
#
# Usage:
#   1. Place your Windows ISO in '~/Downloads/windows.iso'.
#   2. Make the script executable: chmod +x create_kvm_windows_vm_enhanced.sh
#   3. Run with sudo:
#      - For interactive setup: sudo ./create_kvm_windows_vm_enhanced.sh
#      - For automated setup: sudo ./create_kvm_windows_vm_enhanced.sh --name "Win11" --ram 8192 --cores 4 --disk 120G
#
# ===================================================================================

# **Script Configuration & Constants**
# ===================================================================================
readonly SCRIPT_NAME=$(basename "$0")
readonly VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

# **Color Definitions**
# ===================================================================================
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_BOLD='\033[1m'

# **Helper Functions for Logging**
# ===================================================================================
msg() {
    echo -e "${C_GREEN}[*]${C_RESET} ${C_BOLD}$1${C_RESET}"
}

warn() {
    echo -e "${C_YELLOW}[!]${C_RESET} ${C_BOLD}$1${C_RESET}"
}

error() {
    echo -e "${C_RED}[ERROR]${C_RESET} ${C_BOLD}$1${C_RESET}" >&2
}

# **Core Functions**
# ===================================================================================

# Displays script usage information
usage() {
    cat <<EOF
${C_BOLD}Usage:${C_RESET} sudo ./${SCRIPT_NAME} [OPTIONS]

${C_BOLD}Description:${C_RESET}
  Creates a KVM virtual machine optimized for Windows 10/11.

${C_BOLD}Options:${C_RESET}
  -n, --name      VM Name (Default: Windows11-VM)
  -o, --os        OS Variant for virt-install (Default: win11)
  -r, --ram       RAM size in MB (Default: 8192)
  -c, --cores     Number of CPU cores (Default: 4)
  -d, --disk      Disk size in GB (e.g., 100G) (Default: 100G)
  -i, --iso       Path to the Windows ISO file (Default: /home/\$SUDO_USER/Downloads/windows.iso)
  -h, --help      Show this help message

${C_BOLD}Example:${C_RESET}
  sudo ./${SCRIPT_NAME} --name "MyWinVM" --ram 16384 --cores 8
EOF
    exit 0
}

# Cleanup function that runs on script exit or error
cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # Add any cleanup tasks here, e.g., removing temporary files
    msg "Script finished."
}

# Verify that the system has KVM support and modules are loaded
verify_kvm_support() {
    msg "Checking for KVM support..."
    if ! grep -q -E '^(vmx|svm)$' /proc/cpuinfo; then
        error "CPU virtualization is not supported or not enabled in your BIOS/UEFI."
        exit 1
    fi

    if ! lsmod | grep -q kvm; then
        error "KVM kernel modules are not loaded. Try running: 'sudo modprobe kvm_intel' or 'sudo modprobe kvm_amd'"
        exit 1
    fi
    msg "KVM support verified."
}

# Install required packages if they are missing
install_dependencies() {
    msg "Checking for required packages..."
    local packages=("qemu-kvm" "libvirt-daemon-system" "libvirt-clients" "bridge-utils" "virtinst" "ovmf" "virt-viewer")
    local missing_packages=()

    for pkg in "${packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        warn "The following required packages are missing: ${missing_packages[*]}"
        read -p "Do you want to install them now? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            sudo apt-get update
            sudo apt-get install -y "${missing_packages[@]}"
        else
            error "Cannot proceed without required packages. Aborting."
            exit 1
        fi
    else
        msg "All required packages are installed."
    fi

    msg "Ensuring user '${SUDO_USER}' is in 'libvirt' and 'kvm' groups..."
    if ! getent group libvirt | grep -q "\b${SUDO_USER}\b" || ! getent group kvm | grep -q "\b${SUDO_USER}\b"; then
        sudo usermod -aG libvirt,kvm "${SUDO_USER}"
        warn "User '${SUDO_USER}' has been added to the 'libvirt' and 'kvm' groups."
        warn "You MUST log out and log back in, or start a new shell for the changes to take effect."
        read -p "Press Enter to continue, or Ctrl+C to abort and log out now."
    fi
}

# Check libvirt network status and offer to start it
check_libvirt_network() {
    msg "Checking libvirt default network status..."
    if ! sudo virsh net-info default | grep -q "Active:.*yes"; then
        warn "The default libvirt network is not active."
        read -p "Do you want to attempt to start it now? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            sudo virsh net-start default || { error "Failed to start default network."; exit 1; }
            msg "Default network started."
        else
            error "Cannot proceed without an active libvirt network. Aborting."
            exit 1
        fi
    else
        msg "Libvirt default network is active."
    fi
}

# Download VirtIO drivers if not found locally
get_virtio_drivers() {
    local virtio_iso_path="/home/${SUDO_USER}/virtio-win.iso"
    if [ ! -f "$virtio_iso_path" ]; then
        msg "Downloading latest VirtIO drivers for Windows..."
        if ! wget -O "$virtio_iso_path" "$VIRTIO_URL"; then
            error "Failed to download VirtIO drivers. Please check your internet connection or the URL: ${VIRTIO_URL}"
            exit 1
        fi
        msg "VirtIO drivers downloaded successfully to ${virtio_iso_path}"
    else
        msg "Existing VirtIO drivers found at ${virtio_iso_path}"
    fi
    # Return the path for the create_vm function
    echo "$virtio_iso_path"
}

# Main function to orchestrate VM creation
main() {
    # --- Root User Check ---
    if [[ "$EUID" -ne 0 ]]; then
        error "This script requires root privileges for package installation and VM management. Please run with 'sudo'."
        exit 1
    fi
    
    # --- Default VM Parameters ---
    local vm_name="Windows11-VM"
    local os_variant="win11"
    local ram_size="8192"
    local cpu_cores="4"
    local disk_size="100G"
    local iso_path="/home/${SUDO_USER}/Downloads/windows.iso"

    # --- Argument Parsing ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name) vm_name="$2"; shift 2 ;;
            -o|--os) os_variant="$2"; shift 2 ;;
            -r|--ram) ram_size="$2"; shift 2 ;;
            -c|--cores) cpu_cores="$2"; shift 2 ;;
            -d|--disk) disk_size="$2"; shift 2 ;;
            -i|--iso) iso_path="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) error "Unknown option: $1"; usage ;;
        esac
    done

    # --- Interactive Prompts if no arguments were given ---
    if [[ -z "$BASH_ARGC" ]]; then # Check if script was run without args
        echo -e "${C_BLUE}--- Customize VM Settings (leave blank for defaults) ---${C_RESET}"
        read -p "Enter VM Name (default: $vm_name): " input && vm_name=${input:-$vm_name}
        read -p "Enter RAM in MB (default: $ram_size): " input && ram_size=${input:-$ram_size}
        read -p "Enter CPU Cores (default: $cpu_cores): " input && cpu_cores=${input:-$cpu_cores}
        read -p "Enter Disk Size (e.g. 120G) (default: $disk_size): " input && disk_size=${input:-$disk_size}
        read -p "Enter Path to Windows ISO (default: $iso_path): " input && iso_path=${input:-$iso_path}
        echo -e "${C_BLUE}-------------------------------------------------------${C_RESET}"
    fi

    # --- Pre-flight Checks ---
    verify_kvm_support
    install_dependencies
    check_libvirt_network
    local virtio_iso_path
    virtio_iso_path=$(get_virtio_drivers)
    
    # --- Final Check for Windows ISO ---
    if [ ! -f "$iso_path" ]; then
        error "Windows ISO not found at '${iso_path}'"
        error "Please specify the correct path with the --iso flag or place it in the default location."
        exit 1
    fi

    local disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
    if [ -f "$disk_path" ]; then
        error "A disk file already exists for this VM name at '${disk_path}'."
        warn "Please choose a different name or delete the existing file."
        exit 1
    fi

    # --- Create VM ---
    msg "Starting VM creation for '${vm_name}' with the following settings:"
    echo -e "  ${C_BLUE}OS Variant:${C_RESET} $os_variant"
    echo -e "  ${C_BLUE}RAM:${C_RESET} $ram_size MB"
    echo -e "  ${C_BLUE}VCPUs:${C_RESET} $cpu_cores"
    echo -e "  ${C_BLUE}Disk:${C_RESET} $disk_path ($disk_size)"
    echo -e "  ${C_BLUE}Windows ISO:${C_RESET} $iso_path"
    echo -e "  ${C_BLUE}VirtIO ISO:${C_RESET} $virtio_iso_path"

    read -p "Do you want to proceed with creation? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        msg "VM creation aborted by user."
        exit 0
    fi

    msg "Creating virtual disk..."
    sudo qemu-img create -f qcow2 "$disk_path" "$disk_size"

    msg "Launching VM installer..."
    if ! sudo virt-install \
        --name "$vm_name" \
        --os-variant "$os_variant" \
        --ram "$ram_size" \
        --vcpus "$cpu_cores" \
        --boot uefi \
        --machine q35 \
        --cpu host-passthrough,kvm_hidden=on \
        # --cpu EPYC,kvm_hidden=on # Alternative: Use a specific CPU model instead of host-passthrough
        --disk "path=$disk_path,format=qcow2,bus=virtio,cache=none" \
        # 'cache=none' is safest against data loss. For higher performance, consider 'writeback', but be aware of risks.
        --disk "path=$iso_path,device=cdrom,bus=sata" \
        --disk "path=$virtio_iso_path,device=cdrom,bus=sata" \
        --network network=default,model=virtio \
        --graphics spice,listen=none \
        --video qxl \
        --sound ich9 \
        --controller type=usb,model=qemu-xhci,ports=15 \
        --tpm emulator,type=tpm-tis,version=2.0 \
        --noautoconsole; then
        error "virt-install command failed. Please check the output above for errors."
        error "You might need to clean up the failed installation manually with: 'sudo virsh undefine ${vm_name} --remove-all-storage'"
        exit 1
    fi
    
    # --- Post-Installation Instructions ---
    echo ""
    msg "VM '${vm_name}' has been created and the installer has started."
    warn "${C_BOLD}IMPORTANT INSTALLATION STEPS:${C_RESET}"
    echo "  1. When Windows setup can't find a disk, click 'Load driver'."
    echo "  2. Browse to the VirtIO CD > vioscsi > ${os_variant} > amd64 and select the driver."
    echo "  3. After the driver loads, your virtual disk will appear. Proceed with installation."
    echo "  4. After Windows is installed, open Device Manager."
    echo "  5. For any devices with yellow warning icons (like Ethernet), right-click -> Update Driver -> Browse my computer."
    echo "  6. Point the driver search to the VirtIO CD drive to install all remaining drivers."
    echo ""
    msg "To manage your VM, use 'virt-manager' or 'virsh':"
    echo -e "  ${C_BLUE}Connect to VM console:${C_RESET} virt-viewer --connect qemu:///system ${vm_name}"
    echo -e "  ${C_BLUE}Start VM:${C_RESET}              sudo virsh start ${vm_name}"
    echo -e "  ${C_BLUE}Shutdown VM:${C_RESET}           sudo virsh shutdown ${vm_name}"
}

# --- Script Entrypoint ---
trap cleanup SIGINT SIGTERM ERR EXIT
main "$@"
