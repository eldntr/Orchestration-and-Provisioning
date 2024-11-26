terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.14"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Define Ubuntu Cloud Image
resource "libvirt_volume" "ubuntu_image" {
  name   = "ubuntu.qcow2"
  pool   = "default"
  source = "/var/lib/libvirt/images/focal-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Webserver VM
data "template_file" "webserver_user_data" {
  template = <<EOF
#cloud-config
hostname: webserver
users:
  - name: ansible
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    ssh_authorized_keys:
      - ${file("~/.ssh/id_rsa.pub")}
EOF
}

resource "libvirt_cloudinit_disk" "webserver_cloudinit" {
  name     = "webserver-cloudinit.iso"
  pool     = "default"
  user_data = data.template_file.webserver_user_data.rendered
}

resource "libvirt_volume" "webserver_qcow2" {
  name           = "webserver.qcow2"
  base_volume_id = libvirt_volume.ubuntu_image.id
  pool           = "default"
}

resource "libvirt_domain" "webserver" {
  name   = "webserver"
  memory = 4096
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.webserver_cloudinit.id

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.webserver_qcow2.id
  }
}

# Database Server VM Cloud-Init Configuration
data "template_file" "dbserver_user_data" {
  template = <<-EOF
    #cloud-config
    hostname: dbserver
    users:
      - name: ansible
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        shell: /bin/bash
        ssh_authorized_keys:
          - ${file("~/.ssh/id_rsa.pub")}
    runcmd:
      - apt-get update && apt-get install -y cloud-guest-utils
      - growpart /dev/vda 1
      - resize2fs /dev/vda1
    EOF
}

# Create disk volume for dbserver
resource "libvirt_volume" "dbserver_qcow2" {
  name           = "dbserver.qcow2"
  base_volume_id = libvirt_volume.ubuntu_image.id
  pool           = "default"
  size           = 10 * 1024 * 1024 * 1024  # 10GB in bytes
}

# Resize the disk after it is created
resource "null_resource" "resize_dbserver_disk" {
  depends_on = [libvirt_volume.dbserver_qcow2]

  provisioner "local-exec" {
    command = "sudo qemu-img resize /var/lib/libvirt/images/dbserver.qcow2 +10G"
  }
}

# Create the Cloud-init Disk for dbserver
resource "libvirt_cloudinit_disk" "dbserver_cloudinit" {
  name      = "dbserver-cloudinit.iso"
  pool      = "default"
  user_data = data.template_file.dbserver_user_data.rendered

  depends_on = [null_resource.resize_dbserver_disk]
}

# Create dbserver domain (VM)
resource "libvirt_domain" "dbserver" {
  name   = "dbserver"
  memory = 8192
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.dbserver_cloudinit.id

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.dbserver_qcow2.id
  }

  depends_on = [libvirt_cloudinit_disk.dbserver_cloudinit]
}

# Outputs
output "webserver_ip" {
  value = libvirt_domain.webserver.network_interface.0.addresses[0]
}

output "dbserver_ip" {
  value = libvirt_domain.dbserver.network_interface.0.addresses[0]
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"

  content = <<EOF
[local]
localhost ansible_connection=local

[webserver]
webserver ansible_host=${libvirt_domain.webserver.network_interface.0.addresses[0]} ansible_user=ansible

[dbserver]
dbserver ansible_host=${libvirt_domain.dbserver.network_interface.0.addresses[0]} ansible_user=ansible
EOF
}