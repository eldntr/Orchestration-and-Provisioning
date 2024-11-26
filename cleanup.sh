#!/bin/bash

# Stop and undefine existing domains
echo "Stopping and undefining existing domains..."

sudo virsh destroy webserver 2>/dev/null
sudo virsh undefine webserver --remove-all-storage 2>/dev/null
sudo virsh destroy dbserver 2>/dev/null
sudo virsh undefine dbserver --remove-all-storage 2>/dev/null

# Check if any leftover UUIDs or references exist
echo "Ensuring UUIDs are fully cleared for webserver and dbserver..."
sudo virsh list --all | grep -E 'webserver|dbserver' && echo "Warning: Residual domain detected."

# Delete volumes in the default pool if they exist
echo "Deleting existing volumes..."

sudo virsh vol-delete webserver.qcow2 --pool default 2>/dev/null
sudo virsh vol-delete dbserver.qcow2 --pool default 2>/dev/null
sudo virsh vol-delete ubuntu.qcow2 --pool default 2>/dev/null

# Remove cloud-init ISO files
echo "Removing cloud-init ISO files..."

sudo rm -f /var/lib/libvirt/images/webserver-cloudinit.iso
sudo rm -f /var/lib/libvirt/images/dbserver-cloudinit.iso

# Ensure AppArmor is disabled
echo "Checking and disabling AppArmor if active..."
if sudo systemctl is-active --quiet apparmor; then
    sudo systemctl stop apparmor
    APPARMOR_DISABLED=1
else
    APPARMOR_DISABLED=0
fi

# Disable SELinux if enabled
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Disabling SELinux temporarily..."
    sudo setenforce 0
    SELINUX_DISABLED=1
else
    SELINUX_DISABLED=0
fi

# Re-confirm and set permissions for the images directory and individual files
echo "Setting permissions for /var/lib/libvirt/images..."
sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images
sudo chmod -R 755 /var/lib/libvirt/images

# Explicitly set permissions for ubuntu.qcow2 if it exists
if [ -f /var/lib/libvirt/images/ubuntu.qcow2 ]; then
    sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/ubuntu.qcow2
    sudo chmod 644 /var/lib/libvirt/images/ubuntu.qcow2
fi

# Validate the state before running OpenTofu
echo "Verifying domains are removed before applying OpenTofu..."
sudo virsh list --all | grep -E 'webserver|dbserver' && echo "Error: Residual domain still present. Manual intervention required." || echo "All clean."

# Run OpenTofu apply
echo "Running OpenTofu apply..."
tofu apply

# Re-enable AppArmor and SELinux if they were disabled
if [ "$APPARMOR_DISABLED" -eq 1 ]; then
    echo "Re-enabling AppArmor..."
    sudo systemctl start apparmor
fi

if [ "$SELINUX_DISABLED" -eq 1 ]; then
    echo "Re-enabling SELinux..."
    sudo setenforce 1
fi

# Final validation of dbserver disk size
echo "Validating dbserver disk resize..."
sudo qemu-img info /var/lib/libvirt/images/dbserver.qcow2
