#!/usr/bin/env bash
# Zabbix Vault 初期化スクリプト
# ansible/secrets/zabbix_vault.yml を Ansible Vault で暗号化して作成する。
#
# 使用方法:
#   cd ansible/
#   bash scripts/init-zabbix-vault.sh
#
# 前提条件:
#   - secrets/vault_pass が存在すること（既存のvaultパスワードファイル）
#   - 各変数の値を事前に用意しておくこと

set -euo pipefail

VAULT_FILE="secrets/zabbix_vault.yml"
VAULT_PASS_FILE="secrets/vault_pass"

if [[ ! -f "${VAULT_PASS_FILE}" ]]; then
  echo "[ERROR] ${VAULT_PASS_FILE} が見つかりません。先に secrets/vault_pass を作成してください。" >&2
  exit 1
fi

if [[ -f "${VAULT_FILE}" ]]; then
  echo "[WARN] ${VAULT_FILE} は既に存在します。上書きしますか？ (yes/no)"
  read -r answer
  if [[ "${answer}" != "yes" ]]; then
    echo "中止しました。"
    exit 0
  fi
fi

echo "=== Zabbix Vault 変数設定 ==="
echo "各変数の値を入力してください（入力内容はエコーされません）。"
echo ""

read -rsp "zabbix_db_password (Zabbix DB ユーザパスワード): " ZABBIX_DB_PASSWORD; echo
read -rsp "patroni_replication_password (Patroni レプリケーションユーザパスワード): " PATRONI_REPLICATION_PASSWORD; echo
read -rsp "keepalived_auth_pass (Keepalived VRRP 認証パスワード: 最大8文字): " KEEPALIVED_AUTH_PASS; echo
read -rsp "haproxy_stats_password (HAProxy Stats ページパスワード): " HAPROXY_STATS_PASSWORD; echo
read -rsp "zabbix_admin_password (Zabbix Web Admin 初期パスワード): " ZABBIX_ADMIN_PASSWORD; echo

# 一時ファイルに平文で書き出してから暗号化
TMP_FILE=$(mktemp)
trap 'rm -f "${TMP_FILE}"' EXIT

cat > "${TMP_FILE}" <<EOF
---
# Zabbix 機密変数 (Ansible Vault 暗号化)
# 生成日時: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

zabbix_db_password: "${ZABBIX_DB_PASSWORD}"
patroni_replication_password: "${PATRONI_REPLICATION_PASSWORD}"
keepalived_auth_pass: "${KEEPALIVED_AUTH_PASS}"
haproxy_stats_password: "${HAPROXY_STATS_PASSWORD}"
zabbix_admin_password: "${ZABBIX_ADMIN_PASSWORD}"
EOF

ansible-vault encrypt "${TMP_FILE}" \
  --vault-password-file "${VAULT_PASS_FILE}" \
  --output "${VAULT_FILE}"

echo ""
echo "[OK] ${VAULT_FILE} を作成しました。"
echo "     このファイルは .gitignore により Git 管理対象外です。"
