# SPEC: DDNS サーバ冗長構成

## 1. 目的

ホームラボ LAN（`192.168.11.0/24`）において以下の機能を提供する。

- LAN 内クライアントへの IP アドレス動的配布（DHCP）
- DHCP で配布されたクライアントへのホスト名による名前解決（Dynamic DNS）
- IaaS 基盤（Proxmox VE ノード・管理 VM）の静的エントリによる名前解決
- 外部ドメインへの名前解決フォワーディング（スプリットホライズン構成）
- Primary / Secondary 冗長構成による可用性確保

---

## 2. VM インベントリ

| Hostname | VMID | 役割 | 配置ノード | IP アドレス | クローン元 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| hip1tk-pvdns01 | 200 | Primary DNS / DHCP サーバ | hip1tk-ppprox01 | 192.168.11.53/24 | VMID 9000 |
| hip1tk-pvdns02 | 201 | Secondary DNS / DHCP サーバ | hip1tk-ppprox01（将来: hip1tk-ppprox02） | 192.168.11.54/24 | VMID 9000 |

VM スペック（vCPU / RAM / Disk）はテンプレート（VMID 9000）のデフォルト値を踏襲する。

---

## 3. ネットワーク設計

### 3.1 スコープ

| 項目 | 値 |
| :--- | :--- |
| ネットワーク | `192.168.11.0/24` |
| ゲートウェイ | `192.168.11.1` |
| 内部ドメイン名 | `devoka-jpn.com` |
| DNS リスニングポート | 53/UDP, 53/TCP |
| DHCP リスニングポート | 67/UDP |
| Kea HA 通信ポート | 8000/TCP（`kea-ctrl-agent` REST API、Primary ↔ Secondary 間） |

### 3.2 DHCP プール設計

| 用途 | レンジ |
| :--- | :--- |
| インフラ予約（固定 IP 領域） | `192.168.11.1` 〜 `192.168.11.99` |
| DHCP 動的配布プール | `192.168.11.100` 〜 `192.168.11.200` |
| 将来予備 | `192.168.11.201` 〜 `192.168.11.254` |

### 3.3 固定 IP インベントリ（DNS 静的エントリ）

| Hostname | FQDN | IP アドレス | 備考 |
| :--- | :--- | :--- | :--- |
| gateway | `gateway.devoka-jpn.com` | 192.168.11.1 | L3 スイッチ / ルータ |
| hip1tk-ppprox01 | `hip1tk-ppprox01.devoka-jpn.com` | 192.168.11.11 | Proxmox VE ノード |
| hip1tk-ppprox02 | `hip1tk-ppprox02.devoka-jpn.com` | 192.168.11.12 | Proxmox VE ノード |
| hip1tk-ppprox03 | `hip1tk-ppprox03.devoka-jpn.com` | 192.168.11.13 | Proxmox VE ノード |
| hip1tk-pvdns01 | `hip1tk-pvdns01.devoka-jpn.com` | 192.168.11.53 | Primary DNS / DHCP |
| hip1tk-pvdns02 | `hip1tk-pvdns02.devoka-jpn.com` | 192.168.11.54 | Secondary DNS / DHCP |
| hip1tk-pvdesk01 | `hip1tk-pvdesk01.devoka-jpn.com` | 動的（DDNS） | IaaS 管理踏み台 VM |

---

## 4. DNS 設計

### 4.1 スプリットホライズン（Split-horizon）構成

`devoka-jpn.com` は公的に取得済みのドメインであるため、BIND9 をスプリットホライズン構成で運用する。

| クエリ対象 | 動作 |
| :--- | :--- |
| `*.devoka-jpn.com`（内部ゾーン） | BIND9 が権威応答。LAN 内ホストの A / PTR レコードを返す |
| その他の外部ドメイン | ゲートウェイ（`192.168.11.1`）へフォワード |

`acl` により内部ネットワーク（`192.168.11.0/24`）からのクエリのみ内部 View で処理し、外部からの意図しないアクセスを遮断する。

### 4.2 ゾーン設計

| ゾーン名 | Primary | Secondary | 用途 |
| :--- | :--- | :--- | :--- |
| `devoka-jpn.com` | hip1tk-pvdns01 | hip1tk-pvdns02 | 正引きゾーン |
| `11.168.192.in-addr.arpa` | hip1tk-pvdns01 | hip1tk-pvdns02 | 逆引きゾーン |

### 4.3 ゾーン転送（AXFR / IXFR）

- Primary（192.168.11.53）→ Secondary（192.168.11.54）への自動ゾーン転送を構成する。
- 転送は TSIG キー（`transfer-key`）による認証を必須とし、承認外ホストからの転送要求を拒否する。

---

## 5. DDNS 設計

### 5.1 コンポーネント構成

| コンポーネント | 役割 |
| :--- | :--- |
| `kea-dhcp4` | DHCPv4 サーバ本体。IP 配布・HA 状態同期を担う |
| `kea-dhcp-ddns`（D2） | DHCP イベントを受け取り BIND9 へ動的更新（nsupdate）を送信する専用デーモン |
| `kea-ctrl-agent` | REST API エンドポイント。HA ピア間の通信および運用管理に使用 |
| `bind9`（named） | 権威 DNS サーバ。DDNS 更新を受け付け、Secondary へゾーン転送する |

### 5.2 動的更新フロー

```
DHCP クライアント
    │  DHCPREQUEST / DHCPRELEASE
    ▼
kea-dhcp4（Primary or Secondary）
    │  DDNS 更新要求（JSON over localhost）
    ▼
kea-dhcp-ddns（D2デーモン）
    │  nsupdate（TSIG: ddns-key）
    ▼
BIND9 Primary（hip1tk-pvdns01）
    │  ゾーン転送（TSIG: transfer-key）
    ▼
BIND9 Secondary（hip1tk-pvdns02）
```

`kea-dhcp4` と `kea-dhcp-ddns` は同一ホスト上でローカル通信する。各 VM に両デーモンを配置し、D2 は常に同一ホストの `kea-dhcp4` のみを処理する。

### 5.3 TSIG キー

| キー名 | アルゴリズム | 用途 |
| :--- | :--- | :--- |
| `ddns-key` | HMAC-SHA256 | `kea-dhcp-ddns` → BIND9 への動的更新認証 |
| `transfer-key` | HMAC-SHA256 | BIND9 Primary ↔ Secondary 間のゾーン転送認証 |

### 5.4 動的更新ポリシー（update-policy）

BIND9 ゾーンには以下のポリシーを適用する。

- `ddns-key` を保持するクライアント（`kea-dhcp-ddns`）のみが `devoka-jpn.com` および `11.168.192.in-addr.arpa` への A レコード・PTR レコード操作を許可される。
- それ以外のクライアントからの動的更新は全て拒否する。

---

## 6. 冗長化設計

### 6.1 DNS 冗長化（BIND9 Primary / Secondary）

| 項目 | 設計 |
| :--- | :--- |
| 構成 | BIND9 Primary / Secondary |
| クライアント参照先 | Kea DHCP Option 6 で両サーバ（.53, .54）を配布 |
| ゾーン同期 | Primary から AXFR / IXFR（TSIG 認証） |
| Primary 障害時 | Secondary が既存ゾーン情報で応答継続（動的更新登録は停止） |
| Secondary 障害時 | Primary のみで継続稼働。クライアント影響なし |

### 6.2 DHCP 冗長化（Kea HA: hot-standby モード）

| 項目 | 設計 |
| :--- | :--- |
| 構成 | Kea HA フック（`hot-standby` モード） |
| ロール | hip1tk-pvdns01: `primary`、hip1tk-pvdns02: `standby` |
| 通常時 | Primary がすべてのリクエストを処理。Standby はリースを受信して同期のみ |
| Primary 障害時 | Standby が自動で `primary` ロールに昇格し、全プールを引き継ぐ |
| 障害検知 | `kea-ctrl-agent` REST API（8000/TCP）による相互ヘルスチェック |

---

## 7. 機密情報の管理

以下の情報は Git リポジトリに平文で保存しない。

| 情報 | 管理方法 |
| :--- | :--- |
| TSIG キー（`ddns-key`、`transfer-key`） | Ansible Vault（`group_vars/dns_servers/vault.yml`） |
| `bind-user` パスワードハッシュ | Ansible Vault |
| `bind-user` SSH 公開鍵 | Ansible Vault または `group_vars/dns_servers/vars.yml` |
| Cloud-init パスワード | `terraform/secrets/terraform.tfvars`（`.gitignore` 対象） |
| Cloud-init SSH 公開鍵 | `terraform/secrets/terraform.tfvars`（`.gitignore` 対象） |

Ansible Vault の暗号化パスワードは `ansible/secrets/vault_pass` に配置し、`.gitignore` により Git 管理から除外する。

---

## 8. Cloud-init 設定

Terraform により以下を Cloud-init で設定する。DNS 設定は既存 DHCP サーバから配布されるため、Cloud-init での明示設定は行わない。

| 項目 | 値 |
| :--- | :--- |
| OS ユーザ名 | `bind-user` |
| パスワード | `terraform/secrets/terraform.tfvars` で管理（Git 除外） |
| SSH 公開鍵 | `hip1tk-pvdesk01` の `~/.ssh/id_ed25519.pub`（`terraform/secrets/terraform.tfvars` で管理） |
| ネットワーク | 固定 IP（dns01: 192.168.11.53、dns02: 192.168.11.54）、GW: 192.168.11.1 |

---

## 9. Terraform 実装方針

### 9.1 ディレクトリ構成

```
terraform/
├── environments/
│   └── proxmox/
│       ├── main.tf              # プロバイダ設定（既存）
│       ├── variables.tf         # 変数定義（既存）
│       └── ddns.tf              # DDNS サーバ VM 定義（新規）
├── modules/
│   └── vm/                      # 共通 VM プロビジョニングモジュール（新規）
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── secrets/
    └── terraform.tfvars         # パスワード・SSH 公開鍵（.gitignore 対象）
```

### 9.2 実装要件

- クローン元: VMID `9000`（cloud-init テンプレート）
- `proxmox_virtual_environment_vm` リソースの `initialization` ブロックで Cloud-init を設定する。
- パスワードおよび SSH 公開鍵は `sensitive = true` の変数として扱い、`terraform.tfvars` から注入する。

---

## 10. Ansible 実装方針

### 10.1 ディレクトリ構成

```
ansible/
├── inventories/
│   └── proxmox/
│       └── hosts.yml            # dns_servers グループを追加
├── playbooks/
│   └── ddns.yml                 # DDNS 構築 Playbook（新規）
├── roles/
│   ├── bind9/                   # BIND9 設定ロール（新規）
│   └── kea/                     # Kea DHCP 設定ロール（新規）
├── group_vars/
│   └── dns_servers/
│       ├── vars.yml             # 非機密変数（ゾーン名・プール等）
│       └── vault.yml            # Ansible Vault 暗号化（TSIG キー・パスワード）
└── host_vars/
    ├── hip1tk-pvdns01/
    │   └── vars.yml             # Primary 固有設定（kea_role: primary、dns_role: primary）
    └── hip1tk-pvdns02/
        └── vars.yml             # Secondary 固有設定（kea_role: standby、dns_role: secondary）
```

### 10.2 ロール責務

| ロール | 責務 |
| :--- | :--- |
| `bind9` | BIND9 インストール、`named.conf` 生成（View / ACL 含む）、ゾーンファイル配置、TSIG キー設定、サービス起動・有効化 |
| `kea` | `kea-dhcp4`・`kea-dhcp-ddns`・`kea-ctrl-agent` インストール、各設定ファイル（JSON）生成、HA ピア設定、DDNS 連携設定、サービス起動・有効化 |

### 10.3 Playbook 実行順序

1. `bind9` ロールを Primary・Secondary の順に適用（Primary がゾーンファイルを先に保持する必要があるため）
2. `kea` ロールを Primary・Secondary の順に適用（Primary が先に起動し、Standby からの接続を待ち受ける必要があるため）

---

## 11. 今後の拡張方針

- hip1tk-ppprox03 が安定稼働した後、hip1tk-pvdns02 を hip1tk-ppprox02 へ移設し、物理ノード障害への耐性を強化する。
- 将来的に OpenLDAP 認証基盤が整備された場合、BIND9 の管理インタフェース認証を LDAP へ統合することを検討する。
