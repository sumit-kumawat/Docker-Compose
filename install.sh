#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Detect OS with fallback methods
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=${VERSION_ID:-}
        # Handle special cases
        case "$OS" in
            rhel|rocky|almalinux|oracle|centos|fedora|amzn)
                # RHEL family
                FAMILY="rhel"
                ;;
            ubuntu|debian|linuxmint|kali|proxmox)
                # Debian family
                FAMILY="debian"
                ;;
            sles|opensuse*)
                # SUSE family
                FAMILY="suse"
                ;;
            alpine)
                FAMILY="alpine"
                ;;
            arch|manjaro)
                FAMILY="arch"
                ;;
            *)
                # Try to detect family by package manager
                if command -v apt &>/dev/null; then
                    FAMILY="debian"
                    OS="debian"
                elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
                    FAMILY="rhel"
                    OS="rhel"
                elif command -v zypper &>/dev/null; then
                    FAMILY="suse"
                    OS="suse"
                elif command -v apk &>/dev/null; then
                    FAMILY="alpine"
                    OS="alpine"
                elif command -v pacman &>/dev/null; then
                    FAMILY="arch"
                    OS="arch"
                else
                    print_error "Unable to detect OS family"
                fi
                ;;
        esac
    else
        print_error "Unsupported OS - /etc/os-release not found"
    fi
    print_status "Detected OS: $OS ($FAMILY family)"
}

# Install Docker using official convenience script (fallback for unsupported OSes)
install_docker_official() {
    print_status "Using official Docker installation script..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
}

# Debian/Ubuntu family installation
install_debian() {
    print_status "Installing Docker on Debian/Ubuntu family..."
    
    # Update package index
    apt update -qq
    
    # Install prerequisites
    apt install -y -qq apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the stable repository
    if [ "$OS" = "ubuntu" ] && [ -n "$VERSION_ID" ]; then
        # Use Ubuntu's codename
        UBUNTU_CODENAME=$(lsb_release -cs)
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    elif [ "$OS" = "linuxmint" ] || [ "$OS" = "kali" ]; then
        # For derivatives, use Ubuntu or Debian base
        if [ -f /etc/upstream-release/lsb-release ]; then
            . /etc/upstream-release/lsb-release
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $DISTRIB_CODENAME stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null
        else
            # Fallback to Debian
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null
        fi
    else
        # Debian or other derivatives
        DEBIAN_CODENAME=$(lsb_release -cs)
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $DEBIAN_CODENAME stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    # Install Docker
    apt update -qq
    apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Install docker-compose v2 plugin
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
}

# RHEL family (RHEL, CentOS, Rocky, Alma, Oracle, Fedora, Amazon Linux)
install_rhel() {
    print_status "Installing Docker on RHEL family..."
    
    # Determine package manager
    if command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
    else
        PKG_MGR="yum"
    fi
    
    # Install prerequisites
    $PKG_MGR install -y yum-utils device-mapper-persistent-data lvm2 curl
    
    # Add Docker repository
    if [ "$OS" = "fedora" ]; then
        $PKG_MGR config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    elif [ "$OS" = "amzn" ] || [ "$OS" = "amazon" ]; then
        # Amazon Linux uses CentOS 7 repo
        $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        # Amazon Linux 2 uses systemd
    elif [ "$OS" = "oracle" ]; then
        # Oracle Linux uses RHEL repo
        $PKG_MGR config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    else
        # RHEL, CentOS, Rocky, Alma
        $PKG_MGR config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    fi
    
    # Install Docker
    $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Install docker-compose v2 plugin
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
}

# SUSE family (SLES, openSUSE)
install_suse() {
    print_status "Installing Docker on SUSE family..."
    
    # Add Docker repository
    if [ "$OS" = "sles" ]; then
        zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
    else
        # openSUSE
        zypper addrepo https://download.docker.com/linux/opensuse/docker-ce.repo
    fi
    
    # Refresh repositories
    zypper refresh
    
    # Install Docker
    zypper install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Install docker-compose v2 plugin
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
}

# Alpine Linux
install_alpine() {
    print_status "Installing Docker on Alpine Linux..."
    
    # Install prerequisites
    apk add --no-cache curl
    
    # Install Docker from community repository
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
    apk update
    apk add --no-cache docker docker-cli-compose
    
    # Start Docker service
    rc-update add docker default
    service docker start
    
    # Install docker-compose v2 plugin separately
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
}

# Arch Linux family (Arch, Manjaro)
install_arch() {
    print_status "Installing Docker on Arch Linux family..."
    
    # Update package database
    pacman -Sy
    
    # Install Docker
    pacman -S --noconfirm docker docker-compose
    
    # Start Docker service
    systemctl enable --now docker
}

# CloudLinux special handling
install_cloudlinux() {
    print_status "Installing Docker on CloudLinux..."
    # CloudLinux is RHEL-based
    FAMILY="rhel"
    install_rhel
}

# Proxmox special handling
install_proxmox() {
    print_status "Installing Docker on Proxmox..."
    # Proxmox is Debian-based
    FAMILY="debian"
    install_debian
}

# Main installation logic
detect_os

# Special case: Detect if OS is CloudLinux or Proxmox specifically
if [ "$OS" = "cloudlinux" ]; then
    install_cloudlinux
elif [ "$OS" = "proxmox" ]; then
    install_proxmox
else
    # Install based on family
    case "$FAMILY" in
        debian)
            install_debian
            ;;
        rhel)
            install_rhel
            ;;
        suse)
            install_suse
            ;;
        alpine)
            install_alpine
            ;;
        arch)
            install_arch
            ;;
        *)
            print_warning "Unsupported or unknown OS family: $FAMILY"
            print_status "Attempting official Docker installation script as fallback..."
            install_docker_official
            ;;
    esac
fi

# Enable and start Docker service
print_status "Enabling and starting Docker service..."
systemctl enable --now docker 2>/dev/null || print_warning "systemctl not available, Docker may need manual start"

# Install docker-compose v2 plugin (if not already installed)
if ! docker compose version &>/dev/null; then
    print_status "Installing Docker Compose v2 plugin..."
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
fi

# Also install legacy docker-compose v1 for compatibility if not present
if ! command -v docker-compose &>/dev/null; then
    print_status "Installing legacy Docker Compose v1 binary for compatibility..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Verify installations
print_status "Verifying installation..."
docker --version
if docker compose version &>/dev/null; then
    docker compose version
elif command -v docker-compose &>/dev/null; then
    docker-compose --version
else
    print_warning "Docker Compose not found in PATH"
fi

# Add user to docker group (non-root use)
if [ "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    print_status "Adding user $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
    echo "You may need to log out and back in to use Docker without sudo."
elif [ "$USER" ] && [ "$USER" != "root" ]; then
    print_status "Adding user $USER to docker group..."
    usermod -aG docker "$USER"
    echo "You may need to log out and back in to use Docker without sudo."
fi

print_status "Docker and Docker Compose installation completed successfully!"

# Show usage info
echo ""
echo "=============================================="
echo "Docker installed successfully!"
echo "Usage:"
echo "  docker --version"
echo "  docker compose version      (v2 plugin)"
echo "  docker-compose --version    (v1 legacy)"
echo "=============================================="
