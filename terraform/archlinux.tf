
provider "libvirt" {
  uri = "qemu:///system"
}

variable "archlinux_hostname_prefix" {
  default = "arch"
}

variable "diskpool" {
  default = "default"
}

variable "archlinux_node_count" {
  default = 2
}

# ArchLinux base image
resource "libvirt_volume" "os_image_archlinux" {
  name = "os_image_archlinux"
  source = "archlinux-minimal-cloud.qcow2"
}

# ArchLinux member volumes
resource "libvirt_volume" "node_volume_archlinux" {
  name = "node${count.index}_volume_archlinux"
  pool = "${var.diskpool}"
  base_volume_id = "${libvirt_volume.os_image_archlinux.id}"
  format = "qcow2"
  count = "${var.archlinux_node_count}"
}

# Use CloudInit to add the ArchLinux instance
resource "libvirt_cloudinit_disk" "archlinux_cloudinit" {
  name = "cloudinit_archlinux_${count.index}.iso"
  user_data = "${data.template_file.archlinux_user_data[count.index].rendered}"
  count = "${var.archlinux_node_count}"
}

# ---

resource "libvirt_domain" "node-arch" {
  name   = "arch-${count.index}"
  memory = "2048"
  vcpu   = 2
  qemu_agent = true

  network_interface {
    bridge = "br1"
    #mac    = "52:54:00:b2:2f:00"
    hostname = "arch-${count.index}"
    #wait_for_lease = true
  }

  boot_device {
    dev = ["hd", "network"]
  }

  disk {
    volume_id = "${element(libvirt_volume.node_volume_archlinux.*.id, count.index)}"
  }

  count = "${var.archlinux_node_count}"

  cloudinit = "${libvirt_cloudinit_disk.archlinux_cloudinit[count.index].id}"

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  console {
    type = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = "true"
  }

}

# ---

data "template_file" "archlinux_user_data" {
  template = "${file("${path.module}/cloud_init_archlinux.cfg")}"

  vars = {
    hostname = "${var.archlinux_hostname_prefix}-${count.index}"
  }

  count = "${var.archlinux_node_count}"
}

