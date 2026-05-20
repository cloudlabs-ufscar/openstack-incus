terraform {
  required_providers {
    incus = { source = "lxc/incus", version = ">= 0.1.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "incus" {}
provider "tls" {}

resource "tls_private_key" "kolla_ssh" {
  algorithm = "ED25519"
}

data "incus_network" "ext_net" {
  name = var.ext_network
}

# Volume Cinder anexado APENAS ao Controller
resource "incus_storage_volume" "cinder_disk" {
  name         = "osd-${var.cluster_name}-controller"
  pool         = var.storage_pool
  content_type = "block"
  target       = var.target_node
}

# --- PERFIL E INSTÂNCIA DO CONTROLLER ---
resource "incus_profile" "controller" {
  name = "os-controller-${var.cluster_name}"
  config = {
    "security.nesting"     = "true"
    "cloud-init.user-data" = templatefile("${path.module}/cloud_init_controller.yaml.tpl", {
      vip_address   = var.vip_address
      router_id     = var.router_id
      cluster_name  = var.cluster_name
      compute_count = var.compute_count
      priv_key      = tls_private_key.kolla_ssh.private_key_openssh
      pub_key       = tls_private_key.kolla_ssh.public_key_openssh
    })
  }
  device {
    name = "eth1"
    type = "nic"
    properties = { network = data.incus_network.ext_net.name, name = "eth1" }
  }
}

resource "incus_instance" "controller" {
  name     = "${var.cluster_name}-controller"
  image    = "images:ubuntu/24.04/cloud"
  type     = "virtual-machine"
  profiles = ["default", incus_profile.controller.name]
  target   = var.target_node

  config = {
    "limits.cpu"    = "8"
    "limits.memory" = "16GiB"
  }
  device {
    name = "root"
    type = "disk"
    properties = { pool = var.storage_pool, path = "/", size = "50GiB" }
  }
  device {
    name = "sdb"
    type = "disk"
    properties = { pool = var.storage_pool, source = incus_storage_volume.cinder_disk.name }
  }
  device {
    name = "cloudinit"
    type = "disk"
    properties = { source = "cloud-init:config" }
  }
}

# --- PERFIL E INSTÂNCIAS DOS COMPUTES ---
resource "incus_profile" "compute" {
  name = "os-compute-${var.cluster_name}"
  config = {
    "security.nesting"     = "true"
    "cloud-init.user-data" = templatefile("${path.module}/cloud_init_compute.yaml.tpl", {
      pub_key = tls_private_key.kolla_ssh.public_key_openssh
    })
  }
  device {
    name = "eth1"
    type = "nic"
    properties = { network = data.incus_network.ext_net.name, name = "eth1" }
  }
}

resource "incus_instance" "compute" {
  count    = var.compute_count
  name     = "${var.cluster_name}-compute-${count.index + 1}"
  image    = "images:ubuntu/24.04/cloud"
  type     = "virtual-machine"
  profiles = ["default", incus_profile.compute.name]
  target   = var.target_node

  config = {
    "limits.cpu"    = "8" # Computes precisam de CPU para subir as VMs de teste
    "limits.memory" = "16GiB"
  }
  device {
    name = "root"
    type = "disk"
    properties = { pool = var.storage_pool, path = "/", size = "50GiB" }
  }
  device {
    name = "cloudinit"
    type = "disk"
    properties = { source = "cloud-init:config" }
  }
}