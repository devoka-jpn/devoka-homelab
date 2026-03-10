# Zabbix エンタープライズ冗長構成 VM（docs/specs/zabbix.md 参照）
#
# 構成概要:
#   hip1tk-pvzbxlb01/02 (VMID 300/301) : HAProxy + Keepalived + etcd
#   hip1tk-pvzbxsv01/02 (VMID 302/303) : Zabbix Server HA Cluster (sv01 は etcd も担当)
#   hip1tk-pvzbxfe01/02 (VMID 304/305) : Zabbix Frontend (Nginx + PHP-FPM)
#   hip1tk-pvzbxdb01/02 (VMID 306/307) : PostgreSQL 16 + TimescaleDB + Patroni
#
# IP アドレス: DHCP（cloud-init DHCP 設定。DDNS により hostname.devoka-jpn.com で解決）
# Keepalived VIP: 192.168.11.200（Kea DHCP の配布範囲から除外すること）
#
# 初期配置: 全 VM を hip1tk-ppprox01 へ配置。
# 将来的に各 VM を異なる Proxmox ノードへ移設して物理冗長性を確保する。

# ───────────────────────────────────────────────
# Load Balancer 層 (HAProxy + Keepalived + etcd)
# ───────────────────────────────────────────────

module "zabbix_lb01" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxlb01"
  vm_id          = 300
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_lb01_password
  ssh_public_key = var.vm_ssh_public_key
}

module "zabbix_lb02" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxlb02"
  vm_id          = 301
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_lb02_password
  ssh_public_key = var.vm_ssh_public_key
}

# ───────────────────────────────────────────────
# Zabbix Server 層 (HA Cluster)
# ───────────────────────────────────────────────

module "zabbix_sv01" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxsv01"
  vm_id          = 302
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_sv01_password
  ssh_public_key = var.vm_ssh_public_key
}

module "zabbix_sv02" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxsv02"
  vm_id          = 303
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_sv02_password
  ssh_public_key = var.vm_ssh_public_key
}

# ───────────────────────────────────────────────
# Zabbix Frontend 層 (Nginx + PHP-FPM)
# ───────────────────────────────────────────────

module "zabbix_fe01" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxfe01"
  vm_id          = 304
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_fe01_password
  ssh_public_key = var.vm_ssh_public_key
}

module "zabbix_fe02" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxfe02"
  vm_id          = 305
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_fe02_password
  ssh_public_key = var.vm_ssh_public_key
}

# ───────────────────────────────────────────────
# データベース層 (PostgreSQL + TimescaleDB + Patroni)
# ───────────────────────────────────────────────

module "zabbix_db01" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxdb01"
  vm_id          = 306
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_db01_password
  ssh_public_key = var.vm_ssh_public_key
}

module "zabbix_db02" {
  source = "../../modules/vm"

  vm_name        = "hip1tk-pvzbxdb02"
  vm_id          = 307
  node_name      = var.proxmox_node_name
  template_vm_id = var.vm_template_id
  ip_address     = "dhcp"
  username       = var.zabbix_vm_username
  password       = var.zabbix_db02_password
  ssh_public_key = var.vm_ssh_public_key
}

# ───────────────────────────────────────────────
# Outputs
# ───────────────────────────────────────────────

output "zabbix_lb01" {
  description = "Zabbix LB1 (HAProxy MASTER)"
  value = {
    vm_id   = module.zabbix_lb01.vm_id
    vm_name = module.zabbix_lb01.vm_name
  }
}

output "zabbix_lb02" {
  description = "Zabbix LB2 (HAProxy BACKUP)"
  value = {
    vm_id   = module.zabbix_lb02.vm_id
    vm_name = module.zabbix_lb02.vm_name
  }
}

output "zabbix_sv01" {
  description = "Zabbix Server 1 (Active)"
  value = {
    vm_id   = module.zabbix_sv01.vm_id
    vm_name = module.zabbix_sv01.vm_name
  }
}

output "zabbix_sv02" {
  description = "Zabbix Server 2 (Standby)"
  value = {
    vm_id   = module.zabbix_sv02.vm_id
    vm_name = module.zabbix_sv02.vm_name
  }
}

output "zabbix_fe01" {
  description = "Zabbix Frontend 1"
  value = {
    vm_id   = module.zabbix_fe01.vm_id
    vm_name = module.zabbix_fe01.vm_name
  }
}

output "zabbix_fe02" {
  description = "Zabbix Frontend 2"
  value = {
    vm_id   = module.zabbix_fe02.vm_id
    vm_name = module.zabbix_fe02.vm_name
  }
}

output "zabbix_db01" {
  description = "Zabbix DB Primary (Patroni)"
  value = {
    vm_id   = module.zabbix_db01.vm_id
    vm_name = module.zabbix_db01.vm_name
  }
}

output "zabbix_db02" {
  description = "Zabbix DB Replica (Patroni)"
  value = {
    vm_id   = module.zabbix_db02.vm_id
    vm_name = module.zabbix_db02.vm_name
  }
}

output "zabbix_vip" {
  description = "Zabbix アクセス VIP (Keepalived)"
  value       = "192.168.11.200"
}
