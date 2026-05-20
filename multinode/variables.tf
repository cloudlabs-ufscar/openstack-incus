variable "cluster_name" {
  description = "Nome base do cluster OpenStack"
  type        = string
}

variable "target_node" {
  description = "Nó do cluster Incus onde as VMs devem ser alocadas"
  type        = string
}

variable "vip_address" {
  description = "IP Virtual (VIP) da rede de gerência"
  type        = string
}

variable "router_id" {
  description = "ID único do Keepalived"
  type        = number
}

variable "ext_network" {
  description = "Rede externa existente gerenciada pelo Incus"
  type        = string
  default     = "br-ex"
}

variable "storage_pool" {
  description = "Pool de armazenamento onde o disco será criado"
  type        = string
  default     = "local"
}

variable "compute_count" {
  description = "Quantidade de nós de computação (Compute Nodes)"
  type        = number
  default     = 2
}