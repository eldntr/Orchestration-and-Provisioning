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
package_upgrade: true
packages:
  - apache2
  - git
runcmd:
  - git clone https://github.com/rm77/web-sample-6.git /var/www/html/
  - chown -R www-data:www-data /var/www/html/
  - systemctl restart apache2
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

# Database Server VM
data "template_file" "dbserver_user_data" {
  template = <<EOF
#cloud-config
hostname: dbserver
users:
  - name: ansible
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    ssh_authorized_keys:
      - ${file("~/.ssh/id_rsa.pub")}
package_upgrade: true
packages:
  - mysql-server
  - phpmyadmin
runcmd:
  - echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  - echo "phpmyadmin phpmyadmin/app-password-confirm password ''" | debconf-set-selections
  - echo "phpmyadmin phpmyadmin/mysql/admin-pass password rootpassword" | debconf-set-selections
  - echo "phpmyadmin phpmyadmin/mysql/app-pass password ''" | debconf-set-selections
  - echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
  - DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin
  - systemctl restart apache2
EOF
}

resource "libvirt_cloudinit_disk" "dbserver_cloudinit" {
  name     = "dbserver-cloudinit.iso"
  pool     = "default"
  user_data = data.template_file.dbserver_user_data.rendered
}

resource "libvirt_volume" "dbserver_qcow2" {
  name           = "dbserver.qcow2"
  base_volume_id = libvirt_volume.ubuntu_image.id
  pool           = "default"
}

resource "libvirt_domain" "dbserver" {
  name   = "dbserver"
  memory = 2048
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.dbserver_cloudinit.id

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.dbserver_qcow2.id
  }
}

# Outputs
output "webserver_ip" {
  value = libvirt_domain.webserver.network_interface.0.addresses[0]
}

output "dbserver_ip" {
  value = libvirt_domain.dbserver.network_interface.0.addresses[0]
}
