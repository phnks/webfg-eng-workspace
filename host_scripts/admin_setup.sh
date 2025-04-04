#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo ">>> Admin Setup Script for Developer VM Environment (Debian/Ubuntu-based systems)"
echo ">>> This script will attempt to install/update VirtualBox from the Oracle repository"
echo ">>> and install Vagrant using apt."
echo ">>>"
echo ">>> NOTE: This script requires sudo privileges to install packages."
echo ">>> NOTE: The VirtualBox Extension Pack should still be installed manually from https://www.virtualbox.org/wiki/Downloads"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
   echo "!!! This script must be run using sudo: sudo ./admin_setup.sh" 1>&2
   exit 1
fi

# Ensure the Oracle VirtualBox repository is configured before running this script.
# (Key added and virtualbox.list created in previous steps)

echo ""
echo ">>> Updating package lists (including Oracle VirtualBox repo)..."
apt-get update -y

echo ""
echo ">>> Installing/Updating VirtualBox (target: virtualbox-7.0)..."
# Attempt to install virtualbox-7.0 from the Oracle repository
# This should pull the correct dependencies for the host system (incl. Python 3.10+)
apt-get install -y virtualbox-7.0
echo "VirtualBox 7.0 installation attempted."
echo "Verifying installation:"
VBoxManage --version || echo "VBoxManage command not found after installation attempt."


echo ""
echo ">>> Preparing to install Vagrant from HashiCorp repository..."

echo ">>> Ensuring prerequisites for adding repositories are installed..."
apt-get install -y gnupg software-properties-common

echo ">>> Removing potentially conflicting old Vagrant versions (if any)..."
# Ignore errors if packages are not installed
apt-get remove -y vagrant vagrant-libvirt || true

echo ">>> Adding HashiCorp GPG key..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
# Ensure the key file is readable by apt
chmod 644 /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo ">>> Adding HashiCorp repository..."
# Use lsb_release to get the codename (e.g., focal, jammy)
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

echo ">>> Updating package lists (including HashiCorp repo)..."
apt-get update -y

echo ">>> Installing latest Vagrant from HashiCorp repository..."
apt-get install -y vagrant
echo "Vagrant installation attempted."
echo "Verifying installation:"
vagrant --version || echo "Vagrant command not found after installation attempt."

echo ""
echo ">>> Admin setup script finished."
echo ">>> Please ensure VirtualBox Extension Pack is installed manually if needed."
