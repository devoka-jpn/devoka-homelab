variable "vm_name" {
  description = "VM のホスト名"
  type        = string
}

variable "vm_id" {
  description = "Proxmox 上の VM ID"
  type        = number
}

variable "node_name" {
  description = "VM を配置する Proxmox ノード名"
  type        = string
}

variable "template_vm_id" {
  description = "クローン元テンプレートの VM ID"
  type        = number
  default     = 9000
}

variable "ip_address" {
  description = "VM に割り当てる IP アドレス（CIDR 表記: '192.168.11.53/24' または DHCP: 'dhcp'）"
  type        = string
  default     = "dhcp"
}

variable "gateway" {
  description = "デフォルトゲートウェイ IP アドレス（DHCP 使用時は null）"
  type        = string
  default     = null
}

variable "username" {
  description = "Cloud-init で作成する OS ユーザ名"
  type        = string
}

variable "password" {
  description = "Cloud-init で設定する OS ユーザのパスワード"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Cloud-init で登録する SSH 公開鍵"
  type        = string
  sensitive   = true
}
