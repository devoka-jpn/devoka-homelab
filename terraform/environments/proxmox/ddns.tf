# DDNS サーバ VM（docs/specs/ddns.md 参照）
#
# hip1tk-pvdns01: Primary DNS / DHCP サーバ (192.168.11.53)
# hip1tk-pvdns02: Secondary DNS / DHCP サーバ (192.168.11.54)
#
# 両 VM ともに hip1tk-ppprox01 へ配置する。
# 将来的に hip1tk-pvdns02 を hip1tk-ppprox02 へ移設する際は
# node_name を変更して terraform apply を実施すること。

module "dns_primary" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvdns01"
  vm_id          = 200
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "192.168.11.53/24"
  gateway        = "192.168.11.1"
  username       = var.vm_username
  password       = var.hip1tk_pvdns01_password
  ssh_public_key = var.vm_ssh_public_key
}

module "dns_secondary" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvdns02"
  vm_id          = 201
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "192.168.11.54/24"
  gateway        = "192.168.11.1"
  username       = var.vm_username
  password       = var.hip1tk_pvdns02_password
  ssh_public_key = var.vm_ssh_public_key
}

output "dns_primary" {
  description = "Primary DNS サーバの情報"
  value = {
    vm_id      = module.dns_primary.vm_id
    vm_name    = module.dns_primary.vm_name
    ip_address = module.dns_primary.ip_address
  }
}

output "dns_secondary" {
  description = "Secondary DNS サーバの情報"
  value = {
    vm_id      = module.dns_secondary.vm_id
    vm_name    = module.dns_secondary.vm_name
    ip_address = module.dns_secondary.ip_address
  }
}
