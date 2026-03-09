# 設計: DDNS 監視・エスカレーション（Zabbix + Slack）

関連 SPEC: [docs/specs/ddns.md](./ddns.md)

## 1. 方針

| 項目 | 設計方針 |
| :--- | :--- |
| 監視基盤 | Zabbix（overview.md の採用方針に準拠） |
| 通知先 | Slack（Zabbix Media Type: Slack Webhook） |
| 監視観点 | サービス死活・サービス疎通・パフォーマンス・外形監視 |
| 外形監視の実施場所 | Zabbix Server（LAN 内クライアント代表として DNS クエリ・DHCP 確認を実施） |

> **注意**: `hip1tk-pvdesk01` は管理端末として使用するため外形監視には使用しない。
> 外形監視（TC-10, TC-12〜14 相当）はすべて将来構築する Zabbix Server から実施する。

---

## 2. 監視エージェント配置

| ホスト | エージェント | 役割 |
| :--- | :--- | :--- |
| hip1tk-pvdns01 | Zabbix Agent 2 | サービス死活・プロセス・リソース・Kea API 監視 |
| hip1tk-pvdns02 | Zabbix Agent 2 | 同上 |
| Zabbix Server | Zabbix Server 組み込み機能 | 外形監視（DNS クエリ・DHCP 配布確認） |

---

## 3. 監視アイテム定義

### 3.1 サービス死活監視（hip1tk-pvdns01 / 02 共通）

| アイテムキー | 監視内容 | 収集間隔 |
| :--- | :--- | :--- |
| `proc.num[named]` | BIND9 プロセス数 | 30s |
| `proc.num[kea-dhcp4]` | kea-dhcp4 プロセス数 | 30s |
| `proc.num[kea-dhcp-ddns]` | kea-dhcp-ddns プロセス数 | 30s |
| `proc.num[kea-ctrl-agent]` | kea-ctrl-agent プロセス数 | 30s |
| `systemd.unit.state[named]` | named systemd ユニット状態 | 30s |
| `systemd.unit.state[kea-dhcp4]` | kea-dhcp4 systemd ユニット状態 | 30s |

### 3.2 サービス疎通監視（Zabbix Server から）

Zabbix Server の組み込み Simple Check により、エージェント不要で実施する。

| アイテムキー | 監視内容 | 収集間隔 |
| :--- | :--- | :--- |
| `dns[192.168.11.53,hip1tk-ppprox01.devoka-jpn.com,A,3,1]` | Primary DNS の内部ゾーン解決 | 60s |
| `dns[192.168.11.54,hip1tk-ppprox01.devoka-jpn.com,A,3,1]` | Secondary DNS の内部ゾーン解決 | 60s |
| `net.tcp.port[192.168.11.53,53]` | Primary DNS ポート疎通 | 30s |
| `net.tcp.port[192.168.11.54,53]` | Secondary DNS ポート疎通 | 30s |

### 3.3 DNS パフォーマンス監視（Zabbix Server から）

Zabbix Server が LAN 内クライアント代表として直接 DNS クエリを発行し、応答時間を計測する。
Zabbix Agent 2 の `UserParameter` として Zabbix Server 自身（または将来の Zabbix Proxy）に登録する。

```ini
# /etc/zabbix/zabbix_agent2.d/ddns_check.conf（Zabbix Server に配置）

# Primary DNS: 内部ゾーン解決時間（ms）
UserParameter=dns.response_time.primary, \
  dig @192.168.11.53 hip1tk-ppprox01.devoka-jpn.com A +stats 2>&1 \
  | awk '/Query time/ {print $4}'

# Secondary DNS: 内部ゾーン解決時間（ms）
UserParameter=dns.response_time.secondary, \
  dig @192.168.11.54 hip1tk-ppprox01.devoka-jpn.com A +stats 2>&1 \
  | awk '/Query time/ {print $4}'

# Primary DNS: 内部ゾーン解決成否（1=成功, 0=失敗）
UserParameter=dns.resolve_ok.primary, \
  dig @192.168.11.53 hip1tk-ppprox01.devoka-jpn.com A +short \
  | grep -c '192.168.11.11' || echo 0

# Secondary DNS: 内部ゾーン解決成否（1=成功, 0=失敗）
UserParameter=dns.resolve_ok.secondary, \
  dig @192.168.11.54 hip1tk-ppprox01.devoka-jpn.com A +short \
  | grep -c '192.168.11.11' || echo 0
```

| Zabbix アイテムキー | 監視内容 | 収集間隔 |
| :--- | :--- | :--- |
| `dns.response_time.primary` | Primary DNS 応答時間（ms） | 60s |
| `dns.response_time.secondary` | Secondary DNS 応答時間（ms） | 60s |
| `dns.resolve_ok.primary` | Primary DNS 解決成否（1/0） | 30s |
| `dns.resolve_ok.secondary` | Secondary DNS 解決成否（1/0） | 30s |

### 3.4 Kea DHCP 監視（hip1tk-pvdns01 / 02）

Kea の REST API（kea-ctrl-agent: 8000/TCP）から統計を取得する。
Zabbix Agent 2 の `UserParameter` として以下を登録する。

```ini
# /etc/zabbix/zabbix_agent2.d/kea_check.conf（hip1tk-pvdns01/02 に配置）

# DHCP リース使用数
UserParameter=kea.lease_count, \
  curl -s -X POST http://127.0.0.1:8000/ \
  -H "Content-Type: application/json" \
  -d '{"command":"stat-lease4-get","service":["dhcp4"]}' \
  | python3 -c "import sys,json; \
    rows=json.load(sys.stdin)[0]['arguments']['result-set']['rows']; \
    print(sum(r[1] for r in rows))"

# Kea HA 状態（hot-standby=1, その他=0）
UserParameter=kea.ha_state_ok, \
  curl -s -X POST http://127.0.0.1:8000/ \
  -H "Content-Type: application/json" \
  -d '{"command":"ha-heartbeat","service":["dhcp4"]}' \
  | python3 -c "import sys,json; \
    state=json.load(sys.stdin)[0]['arguments']['state']; \
    print(1 if state == 'hot-standby' else 0)"
```

| Zabbix アイテムキー | 監視内容 | 収集間隔 |
| :--- | :--- | :--- |
| `kea.lease_count` | 現在の DHCP リース使用数 | 60s |
| `kea.ha_state_ok` | Kea HA 状態正常性（1/0） | 30s |

DHCP プールの総数: 101（192.168.11.100〜200）

---

## 4. トリガー定義

### 4.1 DISASTER（即時エスカレーション）

| トリガー名 | 条件 | 対象 |
| :--- | :--- | :--- |
| **DNS サービスダウン** | `proc.num[named]` = 0、継続 1 分 | pvdns01 / pvdns02 |
| **DHCP サービスダウン** | `proc.num[kea-dhcp4]` = 0、継続 1 分 | pvdns01 / pvdns02 |
| **DDNS デーモンダウン** | `proc.num[kea-dhcp-ddns]` = 0、継続 1 分 | pvdns01 / pvdns02 |
| **外形監視失敗（Primary）** | `dns.resolve_ok.primary` = 0、継続 2 分 | Zabbix Server |
| **外形監視失敗（Secondary）** | `dns.resolve_ok.secondary` = 0、継続 2 分 | Zabbix Server |
| **DHCP リース枯渇** | `kea.lease_count` >= 96（95%以上）、継続 5 分 | pvdns01 |

### 4.2 HIGH（即時エスカレーション）

| トリガー名 | 条件 | 対象 |
| :--- | :--- | :--- |
| **DNS 応答遅延（高）** | `dns.response_time.primary` > 1000ms、継続 3 分 | Zabbix Server |
| **DNS 応答遅延（高）** | `dns.response_time.secondary` > 1000ms、継続 3 分 | Zabbix Server |
| **Kea HA 状態異常** | `kea.ha_state_ok` = 0、継続 2 分 | pvdns01 |
| **DHCP リース逼迫** | `kea.lease_count` >= 81（80%以上）、継続 5 分 | pvdns01 |

### 4.3 WARNING（通知のみ）

| トリガー名 | 条件 | 対象 |
| :--- | :--- | :--- |
| **DNS 応答遅延（警告）** | `dns.response_time.primary` > 500ms、継続 5 分 | Zabbix Server |
| **DNS 応答遅延（警告）** | `dns.response_time.secondary` > 500ms、継続 5 分 | Zabbix Server |
| **kea-ctrl-agent ダウン** | `proc.num[kea-ctrl-agent]` = 0、継続 2 分 | pvdns01 / pvdns02 |

---

## 5. Slack 通知設計

### 5.1 Media Type 設定

Zabbix の `Administration > Media Types` で Slack を設定する。

| 設定項目 | 値 |
| :--- | :--- |
| Type | Webhook |
| Parameters | `webhook_url`: Slack Incoming Webhook URL |
| Message templates | 重要度別にメッセージテンプレートを定義（後述） |

### 5.2 Slack メッセージテンプレート

**DISASTER / HIGH（即時エスカレーション）**

```
:rotating_light: *[{TRIGGER.SEVERITY}] {HOST.NAME}*
> *問題:* {TRIGGER.NAME}
> *検知時刻:* {EVENT.DATE} {EVENT.TIME}
> *ステータス:* {TRIGGER.STATUS}
> *詳細:* {TRIGGER.DESCRIPTION}
対応が必要です。Zabbix で確認してください。
```

**WARNING（通知のみ）**

```
:warning: *[WARNING] {HOST.NAME}*
> *問題:* {TRIGGER.NAME}
> *検知時刻:* {EVENT.DATE} {EVENT.TIME}
> *ステータス:* {TRIGGER.STATUS}
閾値を超えました。監視を継続してください。
```

**RESOLVED（復旧通知）**

```
:white_check_mark: *[RESOLVED] {HOST.NAME}*
> *復旧:* {TRIGGER.NAME}
> *復旧時刻:* {EVENT.RECOVERY.DATE} {EVENT.RECOVERY.TIME}
問題が解消されました。
```

### 5.3 エスカレーションポリシー

| 重要度 | 通知タイミング | 通知チャンネル |
| :--- | :--- | :--- |
| DISASTER | 即時（0 分） | `#alerts-critical` |
| HIGH | 即時（0 分） | `#alerts-critical` |
| WARNING | 即時（0 分） | `#alerts-warning` |
| RESOLVED | 即時（0 分） | 発報時と同じチャンネル |

---

## 6. Zabbix テンプレート構成

### 6.1 Template: DDNS Server

hip1tk-pvdns01 / hip1tk-pvdns02 に適用するテンプレート。

```
Template: DDNS Server
├── Items
│   ├── proc.num[named]
│   ├── proc.num[kea-dhcp4]
│   ├── proc.num[kea-dhcp-ddns]
│   ├── proc.num[kea-ctrl-agent]
│   ├── systemd.unit.state[named]
│   ├── systemd.unit.state[kea-dhcp4]
│   ├── kea.lease_count（UserParameter）
│   └── kea.ha_state_ok（UserParameter）
├── Triggers
│   ├── DNS サービスダウン          [DISASTER]
│   ├── DHCP サービスダウン         [DISASTER]
│   ├── DDNS デーモンダウン         [DISASTER]
│   ├── DHCP リース枯渇             [DISASTER]
│   ├── Kea HA 状態異常             [HIGH]
│   ├── DHCP リース逼迫             [HIGH]
│   └── kea-ctrl-agent ダウン       [WARNING]
└── Graphs
    ├── DHCP リース使用数推移
    └── サービスプロセス数
```

### 6.2 Template: DDNS External Monitor

Zabbix Server（ホスト登録: `zabbix-server`）に適用するテンプレート。
Zabbix Server 自身が LAN 内クライアントとして DNS クエリを発行する。

```
Template: DDNS External Monitor
├── Items
│   ├── dns.response_time.primary（UserParameter on Zabbix Server）
│   ├── dns.response_time.secondary（UserParameter on Zabbix Server）
│   ├── dns.resolve_ok.primary（UserParameter on Zabbix Server）
│   └── dns.resolve_ok.secondary（UserParameter on Zabbix Server）
├── Triggers
│   ├── 外形監視失敗（Primary）     [DISASTER]
│   ├── 外形監視失敗（Secondary）   [DISASTER]
│   ├── DNS 応答遅延 >1000ms        [HIGH]
│   └── DNS 応答遅延 >500ms         [WARNING]
└── Graphs
    └── DNS 応答時間推移（Primary / Secondary 比較）
```

---

## 7. Ansible による監視設定の自動化

Zabbix Agent のインストールと UserParameter の配置は Ansible で実施する。

```
ansible/
├── playbooks/
│   └── ddns.yml              # 末尾で monitoring ロールを呼び出す（将来）
└── roles/
    └── zabbix-agent/         # Zabbix Agent インストール・設定ロール
        └── tasks/
            ├── main.yml      # インストール・サービス起動
            ├── kea_check.yml # kea_check.conf の配置（pvdns01/02）
            └── ddns_check.yml# ddns_check.conf の配置（Zabbix Server）
```

Zabbix Server へのテンプレート適用・ホスト登録は Zabbix API（または Web UI）で実施する。
将来 Zabbix 構築が完了した段階で `zabbix-agent` ロールを `ddns.yml` へ組み込む。

---

## 8. 監視開始の前提条件

| 条件 | 詳細 |
| :--- | :--- |
| Zabbix Server の構築完了 | 別途 Zabbix サーバ VM を構築・構成すること |
| Slack Incoming Webhook の発行 | 通知先 Slack ワークスペースで Webhook URL を取得すること |
| Zabbix から各 VM への疎通 | Zabbix Server → pvdns01/02 の 10050/TCP が通ること |
| Zabbix Server の LAN 接続 | Zabbix Server が 192.168.11.0/24 に接続されていること（外形監視のため） |
| テンプレートのインポート | 上記テンプレートを Zabbix Server へインポートし各ホストへ適用すること |
