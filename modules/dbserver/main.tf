terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

variable "ubuntu_image_id" {
  description = "The ID of the base Ubuntu image"
  type        = string
}

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
      - apt-get update && apt-get install -y cloud-guest-utils openssh-server
      - growpart /dev/vda 1
      - resize2fs /dev/vda1
      - systemctl enable ssh
      - systemctl start ssh
    EOF
}

resource "libvirt_volume" "dbserver_qcow2" {
  name           = "dbserver.qcow2"
  base_volume_id = var.ubuntu_image_id
  pool           = "default"
  size           = 10 * 1024 * 1024 * 1024  # 10GB in bytes
}

resource "null_resource" "resize_dbserver_disk" {
  depends_on = [libvirt_volume.dbserver_qcow2]

  provisioner "local-exec" {
    command = "sudo qemu-img resize /var/lib/libvirt/images/dbserver.qcow2 +10G"
  }
}

resource "libvirt_cloudinit_disk" "dbserver_cloudinit" {
  name      = "dbserver-cloudinit.iso"
  pool      = "default"
  user_data = data.template_file.dbserver_user_data.rendered

  depends_on = [null_resource.resize_dbserver_disk]
}

resource "libvirt_domain" "dbserver" {
  name   = "dbserver"
  memory = 4096
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

output "dbserver_ip" {
  value = libvirt_domain.dbserver.network_interface.0.addresses[0]
}