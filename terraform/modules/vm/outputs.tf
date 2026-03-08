output "vm_id" {
  description = "作成された VM の ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "vm_name" {
  description = "作成された VM のホスト名"
  value       = proxmox_virtual_environment_vm.this.name
}

output "ip_address" {
  description = "作成された VM の IP アドレス（CIDR 表記）"
  value       = var.ip_address
}
