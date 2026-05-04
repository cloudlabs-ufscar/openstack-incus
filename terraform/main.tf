terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = ">= 0.1.0"
    }
  }
}

provider "incus" {}

data "incus_network" "ext_net" {
  name = var.ext_network
}

resource "incus_storage_volume" "cinder_disk" {
  name         = "osd-${var.cluster_name}"
  pool         = var.storage_pool
  content_type = "block"
  target       = var.target_node
}

resource "incus_profile" "openstack" {
  name = "os-profile-${var.cluster_name}"
  config = {
    "security.nesting"     = "true"
    "cloud-init.user-data" = templatefile("${path.module}/cloud_init.yaml.tpl", {
      vip_address = var.vip_address
      router_id   = var.router_id
    })
  }
  device {
    name = "eth1"
    type = "nic"
    properties = {
      network = data.incus_network.ext_net.name
      name    = "eth1"
    }
  }
}

resource "incus_instance" "openstack" {
  name     = var.cluster_name
  image    = "images:ubuntu/24.04/cloud"
  type     = "virtual-machine"
  profiles = ["default", incus_profile.openstack.name]
  target   = var.target_node

  config = {
    "limits.cpu"    = "8"
    "limits.memory" = "16GiB"
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      pool = var.storage_pool
      path = "/"
      size = "50GiB"
    }
  }

  device {
    name = "sdb"
    type = "disk"
    properties = {
      pool   = var.storage_pool
      source = incus_storage_volume.cinder_disk.name
    }
  }
}