variable "proxmox_endpoint" {
  description = "Proxmox VE APIエンドポイントURL (例: https://192.168.11.11:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE APIトークン (形式: USER@REALM!TOKENID=SECRET)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "自己署名証明書を許可するか（ホームラボ用途では true）"
  type        = bool
  default     = true
}

variable "vm_template_id" {
  description = "VMクローン元のテンプレートID"
  type        = number
  default     = 9000
}

variable "proxmox_node_name" {
  description = "VM を作成する Proxmox ノード名（Proxmox Web UI のノード名と一致させること）"
  type        = string
  default     = "hip1tk-ppprox01"
}

variable "vm_username" {
  description = "Cloud-init で作成する OS ユーザ名"
  type        = string
  default     = "bind-user"
}

# ───────────────────────────────────────────────
# Zabbix VM 共通設定
# ───────────────────────────────────────────────

variable "zabbix_vm_username" {
  description = "Zabbix 系 VM の Cloud-init OS ユーザ名"
  type        = string
  default     = "zabbix-user"
}

# ───────────────────────────────────────────────
# Zabbix VM パスワード（terraform/secrets/terraform.tfvars で管理）
# ───────────────────────────────────────────────

variable "zabbix_lb01_password" {
  description = "hip1tk-pvzbxlb01 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_lb02_password" {
  description = "hip1tk-pvzbxlb02 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_sv01_password" {
  description = "hip1tk-pvzbxsv01 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_sv02_password" {
  description = "hip1tk-pvzbxsv02 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_fe01_password" {
  description = "hip1tk-pvzbxfe01 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_fe02_password" {
  description = "hip1tk-pvzbxfe02 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_db01_password" {
  description = "hip1tk-pvzbxdb01 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

variable "zabbix_db02_password" {
  description = "hip1tk-pvzbxdb02 の Cloud-init パスワード"
  type        = string
  sensitive   = true
}

# ───────────────────────────────────────────────
# DNS VM パスワード（既存）
# ───────────────────────────────────────────────

variable "hip1tk_pvdns01_password" {
  description = "hip1tk-pvdns01 の Cloud-init パスワード（terraform/secrets/terraform.tfvars で管理）"
  type        = string
  sensitive   = true
}

variable "hip1tk_pvdns02_password" {
  description = "hip1tk-pvdns02 の Cloud-init パスワード（terraform/secrets/terraform.tfvars で管理）"
  type        = string
  sensitive   = true
}

variable "vm_ssh_public_key" {
  description = "Cloud-init で登録する SSH 公開鍵（hip1tk-pvdesk01 の公開鍵を設定。terraform/secrets/terraform.tfvars で管理）"
  type        = string
  sensitive   = true
}
