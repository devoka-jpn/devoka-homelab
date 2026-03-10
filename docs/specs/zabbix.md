# Zabbix エンタープライズ冗長構成 仕様書

## 1. 概要

### 1.1. 目的

本仕様書は、homelab 基盤における統合監視システム **Zabbix 7.0 LTS** のエンタープライズグレード冗長構成を定義する。

単一障害点（SPOF）を排除し、コンポーネント障害発生時でも監視・アラート機能を継続提供することを主目的とする。

### 1.2. 設計方針

| 方針 | 内容 |
| :--- | :--- |
| 冗長レベル | フル冗長（全コンポーネント N+1 以上） |
| データベース | PostgreSQL 16 + TimescaleDB 2.x（時系列圧縮対応） |
| HA 管理 | Patroni + etcd（DB HA）、Zabbix Native HA（Server HA）|
| ロードバランサー | HAProxy + Keepalived VRRP |
| Zabbix バージョン | 7.0 LTS |
| IP アドレス | DHCP（VM は cloud-init DHCP 設定） |
| 初期配置 | 全 VM を hip1tk-ppprox01 に集約（将来的に分散予定）|
| 通知 | Slack Webhook（設定は後続フェーズで実施） |

---

## 2. アーキテクチャ設計

### 2.1. 全体構成図

```
                       ┌─────────────────────────────────────────┐
                       │  LAN: 192.168.11.0/24                   │
                       │                                         │
                       │  Keepalived VIP: 192.168.11.200         │
                       │  (DHCP pool から除外・静的予約)            │
                       └────────────────┬────────────────────────┘
                                        │ HTTP :80 / HTTPS :443
                          ┌─────────────┴──────────────┐
                          │  VRRP (Active/Backup)       │
               ┌──────────▼──────────┐   ┌─────────────▼──────────┐
               │  hip1tk-pvzbxlb01   │   │  hip1tk-pvzbxlb02      │
               │  HAProxy (Active)   │   │  HAProxy (Backup)      │
               │  Keepalived MASTER  │   │  Keepalived BACKUP     │
               │  etcd node 1        │   │  etcd node 2           │
               └──────────┬──────────┘   └─────────────┬──────────┘
                          │                             │
          ┌───────────────┼─────────────────────────────┤
          │ Frontend :80  │ DB :5432 (write to primary) │
          │               │                             │
   ┌──────▼──────┐  ┌─────▼──────┐   ┌──────────────────▼───────────┐
   │pvzbxfe01    │  │pvzbxfe02   │   │  PostgreSQL HA (Patroni)      │
   │Zabbix Web   │  │Zabbix Web  │   │                               │
   │Nginx+PHP-FPM│  │Nginx+PHP-FPM   │  ┌──────────────┐  ┌────────┐│
   └──────┬──────┘  └─────┬──────┘   │  │pvzbxdb01     │  │pvzbxdb02││
          │               │          │  │PG16+TSdb     │◄─►│PG16+TSdb││
          │               │          │  │Primary       │  │Replica  ││
          │               │          │  │(Patroni)     │  │(Patroni)││
          │               │          │  └──────────────┘  └─────────┘│
          │  DB :5432     │          └──────────────────────────────────┘
          │               │
   ┌──────▼───────────────▼────────────────────────┐
   │        Zabbix Server HA Cluster               │
   │  ┌──────────────────┐   ┌─────────────────┐   │
   │  │  pvzbxsv01       │   │  pvzbxsv02      │   │
   │  │  Zabbix Server   │   │  Zabbix Server  │   │
   │  │  (Active Node)   │   │  (Standby Node) │   │
   │  │  etcd node 3     │   │                 │   │
   │  └──────────────────┘   └─────────────────┘   │
   └───────────────────────────────────────────────┘
```

### 2.2. VM インベントリ

| # | Hostname | VMID | 役割 | vCPU | RAM | Disk | 追加コンポーネント |
| :- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | hip1tk-pvzbxlb01 | 300 | Load Balancer 1 (MASTER) | 2 | 2 GB | 20 GB | HAProxy, Keepalived, etcd node-1 |
| 2 | hip1tk-pvzbxlb02 | 301 | Load Balancer 2 (BACKUP) | 2 | 2 GB | 20 GB | HAProxy, Keepalived, etcd node-2 |
| 3 | hip1tk-pvzbxsv01 | 302 | Zabbix Server 1 (Active) | 4 | 4 GB | 30 GB | Zabbix Server, etcd node-3 |
| 4 | hip1tk-pvzbxsv02 | 303 | Zabbix Server 2 (Standby) | 4 | 4 GB | 30 GB | Zabbix Server |
| 5 | hip1tk-pvzbxfe01 | 304 | Zabbix Frontend 1 | 2 | 2 GB | 20 GB | Nginx, PHP-FPM, Zabbix Web UI |
| 6 | hip1tk-pvzbxfe02 | 305 | Zabbix Frontend 2 | 2 | 2 GB | 20 GB | Nginx, PHP-FPM, Zabbix Web UI |
| 7 | hip1tk-pvzbxdb01 | 306 | DB Primary | 4 | 8 GB | 50 GB | PostgreSQL 16, TimescaleDB, Patroni |
| 8 | hip1tk-pvzbxdb02 | 307 | DB Replica | 4 | 8 GB | 50 GB | PostgreSQL 16, TimescaleDB, Patroni |

**合計リソース:** 24 vCPU / 32 GB RAM / 210 GB Disk

> 注意: 初期構築は全 VM を `hip1tk-ppprox01` に配置する。
> 本番安定後に LB, DB, Server をそれぞれ別ノードへ移設し、物理障害耐性を確保する。

---

## 3. コンポーネント詳細設計

### 3.1. ロードバランサー層 (HAProxy + Keepalived)

#### 3.1.1. Keepalived VRRP

| パラメータ | 値 |
| :--- | :--- |
| VRRP Instance | VI_ZABBIX |
| Virtual Router ID | 51 |
| VIP | 192.168.11.200/24 |
| MASTER | hip1tk-pvzbxlb01 (priority: 110) |
| BACKUP | hip1tk-pvzbxlb02 (priority: 100) |
| Auth Type | PASS |
| Preempt | enabled |
| Health Check | HAProxy プロセス監視 (`track_script`) |

VIP `192.168.11.200` は Kea DHCP の配布対象から除外すること（`reserved-addresses` または DHCP プール範囲外に設定）。

#### 3.1.2. HAProxy 設定

| フロントエンド | バックエンド | ポート | アルゴリズム |
| :--- | :--- | :--- | :--- |
| zabbix_web | pvzbxfe01:8080, pvzbxfe02:8080 | :80 | roundrobin + sticky sessions |
| zabbix_web_ssl | pvzbxfe01:8080, pvzbxfe02:8080 | :443 | roundrobin + sticky sessions |
| zabbix_db | pvzbxdb01:5432 (primary), pvzbxdb02:5432 | :5432 | first (write to primary) |

- DB バックエンドは Patroni REST API (`/primary`) によるヘルスチェックで Primary を自動判定する。
- セッション維持には `cookie SERVERID` を使用する（Zabbix Web UI の再ログイン防止）。

### 3.2. Zabbix Server HA クラスタ

#### 3.2.1. 概要

Zabbix 7.0 Native HA Cluster を使用する。

| パラメータ | 値 |
| :--- | :--- |
| HA Node Name (sv01) | zabbix-node-01 |
| HA Node Name (sv02) | zabbix-node-02 |
| HA Failover Delay | 60s |
| DB Connection | HAProxy VIP :5432 経由（フォールバック: DB 直接接続） |
| Server Port | 10051 |

#### 3.2.2. HA フェイルオーバー動作

1. Active ノード（sv01）が停止
2. 60 秒後に Standby ノード（sv02）が Active に昇格
3. Zabbix Frontend は DB の `ha_node` テーブルを参照して自動的に新 Active に切り替え

#### 3.2.3. Zabbix Server 主要設定

```ini
DBHost=192.168.11.200       # HAProxy VIP
DBPort=5432
DBName=zabbix
DBUser=zabbix
HANodeName=zabbix-node-01   # ノード毎に異なる
```

### 3.3. Zabbix Frontend

| パラメータ | 値 |
| :--- | :--- |
| Web サーバ | Nginx + PHP-FPM |
| PHP バージョン | 8.2+ |
| リッスンポート | 8080 (HAProxy からのバックエンドポート) |
| DB 接続 | HAProxy VIP :5432 経由 |
| セッション共有 | PHP セッションを DB に格納（Zabbix 標準機能） |

### 3.4. データベース層 (PostgreSQL + TimescaleDB + Patroni)

#### 3.4.1. PostgreSQL / TimescaleDB

| パラメータ | 値 |
| :--- | :--- |
| PostgreSQL バージョン | 16 |
| TimescaleDB バージョン | 2.x (最新安定版) |
| データベース名 | zabbix |
| ユーザ名 | zabbix |
| レプリケーション | ストリーミングレプリケーション（同期モード） |

#### 3.4.2. TimescaleDB 圧縮設定

Zabbix の大量時系列データを格納するテーブルに hypertable + 圧縮ポリシーを適用する。

| テーブル | hypertable 化 | チャンク間隔 | 圧縮ポリシー |
| :--- | :--- | :--- | :--- |
| history | あり | 1 day | 7 日経過後に圧縮 |
| history_uint | あり | 1 day | 7 日経過後に圧縮 |
| history_str | あり | 1 day | 7 日経過後に圧縮 |
| history_log | あり | 1 day | 7 日経過後に圧縮 |
| history_text | あり | 1 day | 7 日経過後に圧縮 |
| trends | あり | 30 days | 90 日経過後に圧縮 |
| trends_uint | あり | 30 days | 90 日経過後に圧縮 |

圧縮率は通常 80〜90% 削減を期待できる。

#### 3.4.3. Patroni HA

| パラメータ | 値 |
| :--- | :--- |
| DCS (Distributed Config Store) | etcd v3 |
| etcd クラスタ | pvzbxlb01, pvzbxlb02, pvzbxsv01 (3ノード) |
| etcd クラスタ名 | zabbix-etcd |
| Patroni クラスタ名 | zabbix-pg-cluster |
| Primary 選出方式 | etcd リーダー選出（quorum ベース） |
| レプリカ昇格猶予 | 30s |
| REST API ポート | 8008 |
| ヘルスチェック URL | `http://<dbhost>:8008/primary` (Primary), `/replica` (Replica) |

### 3.5. etcd クラスタ

| ノード | ETCD_NAME | 役割 |
| :--- | :--- | :--- |
| hip1tk-pvzbxlb01 | etcd-lb01 | etcd member |
| hip1tk-pvzbxlb02 | etcd-lb02 | etcd member |
| hip1tk-pvzbxsv01 | etcd-sv01 | etcd member |

- 3 ノード構成により quorum (2/3) を維持。1 ノード障害時も継続動作する。
- クライアントポート: 2379、ピアポート: 2380

---

## 4. ネットワーク設計

### 4.1. IP アドレス割り当て

| ホスト | IP 種別 | 備考 |
| :--- | :--- | :--- |
| 全 VM | DHCP | cloud-init DHCP 設定、DDNS により `<hostname>.devoka-jpn.com` で解決 |
| VIP (Keepalived) | 静的予約 `192.168.11.200` | Kea DHCP の配布範囲から除外すること |

### 4.2. ポート一覧

| ポート | プロトコル | 用途 | 送信元 | 宛先 |
| :--- | :--- | :--- | :--- | :--- |
| 80 | TCP | Zabbix Web UI (HTTP) | クライアント | HAProxy VIP |
| 443 | TCP | Zabbix Web UI (HTTPS) | クライアント | HAProxy VIP |
| 5432 | TCP | PostgreSQL | HAProxy, Zabbix Server, Zabbix Frontend | HAProxy VIP |
| 5432 | TCP | PostgreSQL (直接) | Patroni 内部 | pvzbxdb01/02 |
| 8008 | TCP | Patroni REST API | HAProxy | pvzbxdb01/02 |
| 8080 | TCP | Zabbix Frontend (内部) | HAProxy | pvzbxfe01/02 |
| 10051 | TCP | Zabbix Trapper | Zabbix Agent | pvzbxsv01/02 |
| 10050 | TCP | Zabbix Agent (passive) | Zabbix Server | 監視対象 VM |
| 2379 | TCP | etcd Client | Patroni | etcd ノード |
| 2380 | TCP | etcd Peer | etcd ノード間 | etcd ノード |
| 112 | VRRP | Keepalived VRRP | pvzbxlb01/02 | pvzbxlb01/02 |

### 4.3. DNS 前提条件

全 VM は DDNS（BIND9 + Kea DHCP）により以下の形式で名前解決可能であること。

```
hip1tk-pvzbxlb01.devoka-jpn.com → <DHCP 付与 IP>
hip1tk-pvzbxlb02.devoka-jpn.com → <DHCP 付与 IP>
...
```

---

## 5. フェイルオーバーシナリオ

### 5.1. LB ノード障害 (pvzbxlb01 停止)

1. Keepalived が LB1 の停止を検出（dead_interval: 3s）
2. LB2 が VIP を引き継ぎ MASTER に昇格
3. ユーザの HTTP 接続は LB2 経由で継続
4. 影響: 切り替え中のインフライトリクエストが一部ドロップ（通常 < 3s）

### 5.2. Zabbix Server 障害 (pvzbxsv01 停止)

1. pvzbxsv01 が DB の `ha_node` テーブルへのハートビート送信停止
2. 60 秒後に pvzbxsv02 が Active ノードに昇格
3. 監視収集・アラート処理が再開
4. 影響: 最大 60 秒の監視収集停止

### 5.3. DB Primary 障害 (pvzbxdb01 停止)

1. Patroni がハートビート失敗を検出（ttl: 30s）
2. etcd でリーダー選出実行
3. pvzbxdb02 が Primary に昇格
4. Patroni が自身の REST API を `/primary` 応答に切り替え
5. HAProxy のヘルスチェックが新 Primary を検出（interval: 2s）
6. 以降の DB 書き込みが pvzbxdb02 へルーティング
7. 影響: 最大 30〜60 秒の DB 接続エラー

### 5.4. Frontend ノード障害 (pvzbxfe01 停止)

1. HAProxy のヘルスチェック（interval: 2s）が障害を検出
2. pvzbxfe02 のみにルーティング
3. ユーザへの影響: セッションが維持されない可能性あり（再ログイン必要）

---

## 6. 監視対象

### 6.1. 初期監視スコープ

Ansible により管理されている以下の全 VM・ノードを監視対象とする。

| 対象 | 監視方式 | テンプレート |
| :--- | :--- | :--- |
| hip1tk-ppprox01/02/03 (Proxmox) | SNMP v2c | Template Virt VMware / Proxmox by HTTP |
| hip1tk-pvdns01/02 (DNS/DHCP) | Zabbix Agent 2 | Template OS Linux by Zabbix agent |
| hip1tk-pvzbxlb01/02 (LB) | Zabbix Agent 2 | Template OS Linux + HAProxy |
| hip1tk-pvzbxsv01/02 (Zabbix Server) | Zabbix Agent 2 | Template OS Linux + Zabbix Server |
| hip1tk-pvzbxfe01/02 (Frontend) | Zabbix Agent 2 | Template OS Linux + Nginx |
| hip1tk-pvzbxdb01/02 (DB) | Zabbix Agent 2 | Template OS Linux + PostgreSQL by Zabbix agent |
| Zabbix 自身 | Internal | Template Zabbix Server |

### 6.2. 主要アラート条件

| アラート名 | 条件 | 重大度 |
| :--- | :--- | :--- |
| ホスト到達不能 | ICMP 無応答 3 回連続 | HIGH |
| CPU 使用率高 | 5 分平均 > 85% | WARNING |
| メモリ使用率高 | 使用率 > 90% | HIGH |
| ディスク使用率高 | 使用率 > 80% | WARNING |
| DB Primary 停止 | Patroni `/primary` 無応答 | DISASTER |
| Zabbix Server HA 切り替え | ha_node ステータス変化 | HIGH |
| HAProxy バックエンド停止 | HAProxy stats エラー | HIGH |

---

## 7. Slack 通知設定

Slack 通知は Zabbix Web UI から以下の手順で設定する（初期構築後に実施）。

1. Slack で Incoming Webhook URL を取得
2. Zabbix Web UI → Administration → Media Types → Slack を選択
3. Webhook URL を設定
4. ユーザメディアに Slack を追加
5. アクションで Slack 通知を有効化

---

## 8. セキュリティ設計

| 項目 | 設計 |
| :--- | :--- |
| DB パスワード | Ansible Vault で暗号化管理 |
| Zabbix 管理者パスワード | Ansible Vault で暗号化管理 |
| SSH | 公開鍵認証のみ（パスワード認証無効）|
| VM OS ユーザ | `zabbix-user`（sudo 可）|
| firewall | ufw: 必要ポートのみ許可 |
| Patroni REST API | `127.0.0.1` および LAN 内のみ許可 |

---

## 9. IaC 構成

### 9.1. Terraform

```
terraform/
└── environments/
    └── proxmox/
        ├── main.tf          # Provider 設定
        ├── variables.tf     # 変数定義（Zabbix 変数を追加）
        ├── ddns.tf          # 既存 DNS/DHCP VM
        └── zabbix.tf        # Zabbix VM 定義（本ドキュメント対象）
```

### 9.2. Ansible

```
ansible/
├── inventories/proxmox/hosts.yml    # Zabbix グループを追加
├── group_vars/
│   ├── zabbix_lb.yml                # LB 設定変数
│   ├── zabbix_server.yml            # Zabbix Server 設定変数
│   ├── zabbix_frontend.yml          # Frontend 設定変数
│   └── zabbix_db.yml                # DB 設定変数（Vault 参照）
├── playbooks/
│   └── zabbix.yml                   # Zabbix 構築 Playbook
└── roles/
    ├── zabbix_lb/                   # HAProxy + Keepalived + etcd
    ├── zabbix_db/                   # PostgreSQL + TimescaleDB + Patroni
    ├── zabbix_server/               # Zabbix Server HA
    └── zabbix_frontend/             # Nginx + PHP-FPM + Zabbix Web
```

### 9.3. Playbook 実行順序

```
1. zabbix_db       (DB クラスタ初期化)
2. zabbix_lb       (etcd + HAProxy + Keepalived)
3. zabbix_server   (Zabbix Server HA 設定)
4. zabbix_frontend (Zabbix Web UI)
```

---

## 10. 試験計画

| TC-ID | テスト項目 | 手順 | 期待結果 |
| :--- | :--- | :--- | :--- |
| TC-01 | DB Primary 接続確認 | HAProxy VIP:5432 へ psql 接続 | 接続成功・Primary ノードに接続 |
| TC-02 | TimescaleDB 圧縮確認 | `SELECT * FROM timescaledb_information.compression_settings` | history テーブルに圧縮設定あり |
| TC-03 | Zabbix Web UI 表示 | http://192.168.11.200 にアクセス | ログイン画面表示 |
| TC-04 | Zabbix HA 状態確認 | Web UI → Reports → HA nodes | sv01: active, sv02: standby |
| TC-05 | LB フェイルオーバー | pvzbxlb01 を停止し VIP 継続確認 | LB2 が VIP を引き継ぎ、Web UI 継続 |
| TC-06 | Zabbix Server HA 切り替え | pvzbxsv01 を停止し 60 秒後確認 | sv02 が active に切り替わる |
| TC-07 | DB フェイルオーバー | pvzbxdb01 を停止し Patroni 昇格確認 | pvzbxdb02 が Primary に昇格 |
| TC-08 | 監視対象死活確認 | DNS VM の Zabbix Agent 応答確認 | pvdns01/02 が monitoring に表示 |
| TC-09 | アラート通知確認 | テストアクションで Slack 通知送信 | Slack チャンネルに通知が届く |
