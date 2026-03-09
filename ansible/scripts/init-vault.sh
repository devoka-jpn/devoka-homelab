#!/usr/bin/env bash
# =============================================================================
# init-vault.sh: TSIG キーを生成して Ansible Vault 暗号化済み vault.yml を作成する
#
# 使用方法:
#   1. ansible/secrets/vault_pass にVaultパスワードを記録する
#      例: echo "your-strong-vault-password" > ansible/secrets/vault_pass
#          chmod 600 ansible/secrets/vault_pass
#
#   2. このスクリプトを実行する
#      cd devoka-homelab/ansible
#      bash scripts/init-vault.sh
#
# 注意:
#   - vault_pass は .gitignore で除外済み。絶対に Git にコミットしないこと。
#   - 既存の vault.yml がある場合は上書きされる。
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/.."
VAULT_PASS_FILE="${ANSIBLE_DIR}/secrets/vault_pass"
VAULT_FILE="${ANSIBLE_DIR}/group_vars/dns_servers/vault.yml"

# --- 前提確認 ---
if [ ! -f "${VAULT_PASS_FILE}" ]; then
  echo "[ERROR] Vault パスワードファイルが存在しません: ${VAULT_PASS_FILE}"
  echo "  以下を実行してから再度お試しください:"
  echo "    echo 'your-vault-password' > ${VAULT_PASS_FILE}"
  echo "    chmod 600 ${VAULT_PASS_FILE}"
  exit 1
fi

if ! command -v ansible-vault &>/dev/null; then
  echo "[ERROR] ansible-vault が見つかりません。Ansible をインストールしてください。"
  exit 1
fi

if ! command -v openssl &>/dev/null; then
  echo "[ERROR] openssl が見つかりません。"
  exit 1
fi

# --- TSIG キー生成 ---
echo "[INFO] TSIG キーを生成しています..."
DDNS_KEY_SECRET=$(openssl rand -base64 32)
TRANSFER_KEY_SECRET=$(openssl rand -base64 32)

# --- 一時ファイルに平文 YAML を書き込み ---
TMPFILE=$(mktemp /tmp/vault_XXXXXX.yml)
trap "rm -f ${TMPFILE}" EXIT

cat > "${TMPFILE}" <<EOF
---
# TSIG キー（Ansible Vault 暗号化）
# ddns-key: kea-dhcp-ddns → BIND9 への動的更新認証
vault_ddns_key_secret: "${DDNS_KEY_SECRET}"

# transfer-key: BIND9 Primary → Secondary ゾーン転送認証
vault_transfer_key_secret: "${TRANSFER_KEY_SECRET}"
EOF

# --- Ansible Vault で暗号化して保存 ---
ansible-vault encrypt "${TMPFILE}" \
  --vault-password-file="${VAULT_PASS_FILE}" \
  --output="${VAULT_FILE}"

echo "[INFO] vault.yml を作成しました: ${VAULT_FILE}"
echo "[INFO] 内容を確認するには以下を実行してください:"
echo "    ansible-vault view ${VAULT_FILE} --vault-password-file=${VAULT_PASS_FILE}"
