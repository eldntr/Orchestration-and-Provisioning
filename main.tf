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
resource "null_resource" "download_ubuntu_image" {
  provisioner "local-exec" {
    command = <<EOT
      if [ ! -f /var/lib/libvirt/images/focal-server-cloudimg-amd64.img ]; then
        wget -O /var/lib/libvirt/images/focal-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img;
      fi
    EOT
  }
}

resource "libvirt_volume" "ubuntu_image" {
  name   = "ubuntu.qcow2"
  pool   = "default"
  source = "/var/lib/libvirt/images/focal-server-cloudimg-amd64.img"
  format = "qcow2"

  depends_on = [null_resource.download_ubuntu_image]
}

module "webserver" {
  source = "./modules/webserver"
  ubuntu_image_id = libvirt_volume.ubuntu_image.id
}

module "dbserver" {
  source = "./modules/dbserver"
  ubuntu_image_id = libvirt_volume.ubuntu_image.id
}

# Outputs
output "webserver_ip" {
  value = module.webserver.webserver_ip
}

output "dbserver_ip" {
  value = module.dbserver.dbserver_ip
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"

  content = <<EOF
[local]
localhost ansible_connection=local

[webserver]
webserver ansible_host=${module.webserver.webserver_ip} ansible_user=ansible

[dbserver]
dbserver ansible_host=${module.dbserver.dbserver_ip} ansible_user=ansible
EOF
}