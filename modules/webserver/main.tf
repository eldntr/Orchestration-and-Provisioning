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
  base_volume_id = var.ubuntu_image_id
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

output "webserver_ip" {
  value = libvirt_domain.webserver.network_interface.0.addresses[0]
}