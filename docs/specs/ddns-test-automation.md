# 設計: DDNS 試験自動化

関連 SPEC: [docs/specs/ddns.md](./ddns.md) / [docs/specs/ddns-test-plan.md](./ddns-test-plan.md)

## 1. 方針

### 1.1 ツール選定

Ansible の標準モジュール（`assert`・`command`・`uri`・`systemd`）を組み合わせて検証 Playbook を実装する。

| 選択肢 | 評価 |
| :--- | :--- |
| **Ansible assert（採用）** | 追加ツール不要。構築 Playbook と同一リポジトリ・同一スキルで管理できる |
| Testinfra（Python） | より表現力が高いが Python 依存が増える。Ansible との二重管理になる |
| シェルスクリプト | 最も軽量だが冪等性・可読性・エラー報告が劣る |

### 1.2 実行トリガー

| トリガー | 説明 |
| :--- | :--- |
| **構築直後（自動）** | `ddns.yml`（構築 Playbook）の末尾で `import_playbook` により連続実行 |
| **任意タイミング（手動）** | `ansible-playbook ddns-verify.yml` を単体実行 |

### 1.3 自動化の対象外

| 除外項目 | 理由 |
| :--- | :--- |
| TC-10（DHCP DNS 配布確認） | DHCP クライアント端末が必要。将来の Zabbix Server から実施する |
| TC-12〜14（DDNS 動作確認） | DHCP クライアント操作（dhclient）が必要。将来の Zabbix Server から実施する |
| TC-15〜17（冗長化確認） | Primary VM の意図的停止が必要なため手動試験として実施する |

> **注意**: `hip1tk-pvdesk01` は管理端末のため外形監視・DHCP クライアント試験には使用しない。
> 上記 TC は Zabbix Server 構築後に Zabbix の外形監視として組み込む。

---

## 2. ディレクトリ構成

```
ansible/
├── playbooks/
│   ├── ddns.yml                    # 構築 Playbook（末尾で verify を呼び出す）
│   └── ddns-verify.yml             # 検証 Playbook（単体実行も可能）
└── roles/
    └── ddns-verify/                # 検証ロール
        └── tasks/
            ├── main.yml            # フェーズを順に呼び出す
            ├── phase1_os.yml       # TC-01〜03: VM/OS 確認
            ├── phase2_dns.yml      # TC-04〜08: BIND9 確認
            ├── phase3_dhcp.yml     # TC-09〜11: Kea DHCP 確認
            └── phase4_ddns.yml     # TC-12〜14: DDNS 動作確認
```

---

## 3. Playbook 設計

### 3.1 構築 Playbook への組み込み（ddns.yml）

```yaml
# ansible/playbooks/ddns.yml（抜粋）
---
- import_playbook: bind9.yml   # BIND9 構築
- import_playbook: kea.yml     # Kea DHCP 構築

# 構築完了後に自動で検証を実行
- import_playbook: ddns-verify.yml
```

### 3.2 検証 Playbook（ddns-verify.yml）

```yaml
# ansible/playbooks/ddns-verify.yml
---
# TC-01〜09, TC-11 を dns_servers 上で実行する
# TC-10, TC-12〜14 は将来の Zabbix Server から外形監視として実施（自動化対象外）
- name: "Phase 1〜3: DNS サーバ上の OS・サービス・DHCP 確認"
  hosts: dns_servers
  roles:
    - role: ddns-verify
      tags: always
```

---

## 4. 検証ロール タスク設計

### 4.1 phase1_os.yml（TC-01〜TC-03）

```yaml
# tasks/phase1_os.yml
---
- name: "TC-02: ホスト名確認"
  assert:
    that: ansible_hostname == inventory_hostname
    fail_msg: "ホスト名が期待値と一致しない: {{ ansible_hostname }}"

- name: "TC-02: IP アドレス確認"
  assert:
    that: >
      ansible_default_ipv4.address == hostvars[inventory_hostname]['expected_ip']
    fail_msg: "IP アドレスが期待値と一致しない: {{ ansible_default_ipv4.address }}"

- name: "TC-03: 必須サービスの起動確認"
  systemd:
    name: "{{ item }}"
  register: svc_status
  loop:
    - named
    - kea-dhcp4
    - kea-dhcp-ddns
    - kea-ctrl-agent

- name: "TC-03: サービスが active であることを確認"
  assert:
    that: item.status.ActiveState == "active"
    fail_msg: "サービスが active でない: {{ item.item }}"
  loop: "{{ svc_status.results }}"

- name: "TC-01: SSH 接続確認（到達確認）"
  ping:
```

### 4.2 phase2_dns.yml（TC-04〜TC-08）

```yaml
# tasks/phase2_dns.yml
---
- name: "TC-04: 固定エントリ正引き解決（Primary）"
  command: "dig @192.168.11.53 {{ item.name }}.devoka-jpn.com A +short"
  register: dig_result
  loop: "{{ dns_static_entries }}"  # group_vars で定義

- name: "TC-04: 正引き結果の確認"
  assert:
    that: item.stdout == item.item.ip
    fail_msg: "正引き失敗: {{ item.item.name }} -> {{ item.stdout }}（期待: {{ item.item.ip }}）"
  loop: "{{ dig_result.results }}"

- name: "TC-05: 逆引き解決（Primary）"
  command: "dig @192.168.11.53 -x {{ item.ip }} +short"
  register: ptr_result
  loop: "{{ dns_static_entries }}"

- name: "TC-05: 逆引き結果の確認"
  assert:
    that: item.stdout == item.item.name + ".devoka-jpn.com."
    fail_msg: "逆引き失敗: {{ item.item.ip }} -> {{ item.stdout }}"
  loop: "{{ ptr_result.results }}"

- name: "TC-06: 外部ドメインへのフォワード確認"
  command: dig @192.168.11.53 google.com A +short
  register: fwd_result

- name: "TC-06: フォワードで IP が返ること"
  assert:
    that: fwd_result.stdout != ""
    fail_msg: "外部フォワード失敗: google.com の解決が返らなかった"

- name: "TC-07: Secondary によるゾーン解決"
  command: "dig @192.168.11.54 {{ item.name }}.devoka-jpn.com A +short"
  register: sec_result
  loop: "{{ dns_static_entries }}"

- name: "TC-07: Secondary の解決結果確認"
  assert:
    that: item.stdout == item.item.ip
    fail_msg: "Secondary 解決失敗: {{ item.item.name }} -> {{ item.stdout }}"
  loop: "{{ sec_result.results }}"

- name: "TC-08: ゾーン転送完了ログ確認（Primary で実行）"
  delegate_to: hip1tk-pvdns01
  become: true
  shell: "journalctl -u named --no-pager | grep -c 'Transfer completed'"
  register: transfer_log

- name: "TC-08: ゾーン転送が完了していること"
  assert:
    that: transfer_log.stdout | int > 0
    fail_msg: "ゾーン転送完了ログが存在しない"
```

### 4.3 phase3_dhcp.yml（TC-09〜TC-11）

```yaml
# tasks/phase3_dhcp.yml
---
- name: "TC-09/10: Kea leases 統計を REST API で取得（Primary）"
  uri:
    url: "http://192.168.11.53:8000/"
    method: POST
    body_format: json
    body:
      command: "stat-lease4-get"
      service: ["dhcp4"]
  register: lease_stats

- name: "TC-09: リース数が 0 以上であること"
  assert:
    that: lease_stats.json[0].arguments['result-set']['rows'] | length >= 0
    fail_msg: "Kea REST API からリース統計が取得できない"

- name: "TC-10: DHCP Option 6（DNS サーバ）の配布確認"
  command: resolvectl status
  register: resolv_status

- name: "TC-10: プライマリ DNS が配布されていること"
  assert:
    that: "'192.168.11.53' in resolv_status.stdout"
    fail_msg: "DNS サーバ 192.168.11.53 が配布されていない"

- name: "TC-10: セカンダリ DNS が配布されていること"
  assert:
    that: "'192.168.11.54' in resolv_status.stdout"
    fail_msg: "DNS サーバ 192.168.11.54 が配布されていない"

- name: "TC-11: Kea HA ステータスの確認（Primary）"
  uri:
    url: "http://192.168.11.53:8000/"
    method: POST
    body_format: json
    body:
      command: "ha-heartbeat"
      service: ["dhcp4"]
  register: ha_status

- name: "TC-11: HA 状態が hot-standby であること"
  assert:
    that: ha_status.json[0].arguments.state == "hot-standby"
    fail_msg: "Kea HA 状態が異常: {{ ha_status.json[0].arguments.state }}"
```

### 4.4 phase4_ddns.yml（TC-12〜TC-14）

```yaml
# tasks/phase4_ddns.yml
---
- name: "TC-12: DHCP リースを更新して DDNS 登録をトリガー"
  become: true
  shell: "dhclient -r && sleep 3 && dhclient"

- name: "TC-12/13: 現在のホスト名を取得"
  command: hostname
  register: client_hostname

- name: "TC-12: DHCP リース後の DNS 登録確認（正引き）"
  command: "dig @192.168.11.53 {{ client_hostname.stdout }}.devoka-jpn.com A +short"
  register: ddns_fwd
  retries: 5
  delay: 3
  until: ddns_fwd.stdout != ""

- name: "TC-12: 動的登録された A レコードが解決できること"
  assert:
    that: ddns_fwd.stdout != ""
    fail_msg: "DDNS 正引き登録が確認できない: {{ client_hostname.stdout }}.devoka-jpn.com"

- name: "TC-13: 取得した IP を逆引きしてホスト名が返ること"
  command: "dig @192.168.11.53 -x {{ ddns_fwd.stdout }} +short"
  register: ddns_ptr

- name: "TC-13: PTR レコードが正しく登録されていること"
  assert:
    that: client_hostname.stdout in ddns_ptr.stdout
    fail_msg: "DDNS 逆引き登録が確認できない: {{ ddns_fwd.stdout }}"

- name: "TC-14: DHCP リース解放"
  become: true
  command: dhclient -r

- name: "TC-14: リース解放後の DNS レコード削除確認"
  command: "dig @192.168.11.53 {{ client_hostname.stdout }}.devoka-jpn.com A"
  register: ddns_del
  retries: 5
  delay: 3
  until: "'NXDOMAIN' in ddns_del.stdout"

- name: "TC-14: NXDOMAIN が返ること（レコード削除済み）"
  assert:
    that: "'NXDOMAIN' in ddns_del.stdout"
    fail_msg: "DHCP 解放後もレコードが残存している"

- name: "試験後: DHCP リースを再取得して通常状態に戻す"
  become: true
  command: dhclient
```

---

## 5. 変数定義（group_vars）

```yaml
# ansible/group_vars/dns_servers/vars.yml（追記）
dns_static_entries:
  - { name: "hip1tk-ppprox01", ip: "192.168.11.11" }
  - { name: "hip1tk-ppprox02", ip: "192.168.11.12" }
  - { name: "hip1tk-ppprox03", ip: "192.168.11.13" }
  - { name: "hip1tk-pvdns01",  ip: "192.168.11.53" }
  - { name: "hip1tk-pvdns02",  ip: "192.168.11.54" }

# host_vars/hip1tk-pvdns01/vars.yml
expected_ip: "192.168.11.53"

# host_vars/hip1tk-pvdns02/vars.yml
expected_ip: "192.168.11.54"
```

---

## 6. 実行例

```bash
# 構築と同時に自動実行（通常フロー）
ansible-playbook playbooks/ddns.yml -i inventories/proxmox/hosts.yml

# 検証のみ単体実行
ansible-playbook playbooks/ddns-verify.yml -i inventories/proxmox/hosts.yml

# 特定フェーズのみ実行
ansible-playbook playbooks/ddns-verify.yml -i inventories/proxmox/hosts.yml \
  --tags phase2_dns

# 詳細出力モード
ansible-playbook playbooks/ddns-verify.yml -i inventories/proxmox/hosts.yml -v
```

---

## 7. 試験結果の扱い

- `assert` が失敗した TC は Ansible のタスクエラーとして報告される。
- `--continue-on-error` は使用しない。失敗した TC で即停止し、原因調査を優先する。
- 試験完了後は `ddns-test-plan.md` の結果記録表に手動で記録する。
