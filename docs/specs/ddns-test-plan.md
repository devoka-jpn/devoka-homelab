# 試験計画: DDNS サーバ冗長構成

関連 SPEC: [docs/specs/ddns.md](./ddns.md)

## 1. 試験の目的

DDNS サーバ（hip1tk-pvdns01 / hip1tk-pvdns02）の構築後に、以下の観点で正常性と冗長性を確認する。

1. VM・OS・Cloud-init の初期設定が正しく適用されていること
2. BIND9 が正引き・逆引きの権威 DNS として正常に動作すること
3. Kea DHCP がクライアントへ正しく IP 配布していること
4. DHCP リース連動で DNS レコードが動的に登録・削除されること（DDNS）
5. Primary 障害時に Secondary が自律的に引き継ぐこと（冗長化）

---

## 2. 試験環境・前提条件

| 項目 | 値 |
| :--- | :--- |
| 試験実施端末 | hip1tk-pvdesk01（192.168.11.x、DHCP 配布） |
| Primary DNS/DHCP | hip1tk-pvdns01（192.168.11.53） |
| Secondary DNS/DHCP | hip1tk-pvdns02（192.168.11.54） |
| 内部ドメイン | `devoka-jpn.com` |
| DHCP プール | 192.168.11.100 〜 192.168.11.200 |

試験は Ansible Playbook の適用完了後、かつ両 VM が起動している状態で実施する。

---

## 3. フェーズ 1: VM・OS 確認

### TC-01: SSH ログイン確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Cloud-init によるユーザ・SSH 鍵設定が正しく適用されていること |
| 手順 | hip1tk-pvdesk01 から各 VM へ SSH ログインする |
| コマンド | `ssh bind-user@192.168.11.53` / `ssh bind-user@192.168.11.54` |
| 合格条件 | パスフレーズなし（秘密鍵認証）でログインできること |

### TC-02: ホスト名・IP 確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Cloud-init によるホスト名・固定 IP が正しく設定されていること |
| 手順 | 各 VM にログイン後、ホスト名と IP を確認する |
| コマンド | `hostname` / `ip addr show` |
| 合格条件 | dns01: hostname=`hip1tk-pvdns01`、IP=`192.168.11.53/24` <br> dns02: hostname=`hip1tk-pvdns02`、IP=`192.168.11.54/24` |

### TC-03: サービス起動確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | 全デーモンが正常起動・自動起動設定されていること |
| 手順 | 各 VM で各サービスのステータスを確認する |
| コマンド | `systemctl is-active named kea-dhcp4 kea-dhcp-ddns kea-ctrl-agent` |
| 合格条件 | 全サービスが `active` を返すこと |

---

## 4. フェーズ 2: BIND9（DNS）動作確認

### TC-04: 固定エントリ正引き解決

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Proxmox ノード等の静的 A レコードが正しく解決されること |
| 手順 | hip1tk-pvdesk01 から各ホスト名を名前解決する |
| コマンド | `dig @192.168.11.53 hip1tk-ppprox01.devoka-jpn.com A +short` |
| 合格条件 | `192.168.11.11` が返ること（他ノードも同様に確認） |

### TC-05: 逆引き解決

| 項目 | 内容 |
| :--- | :--- |
| 目的 | PTR レコードが正しく解決されること |
| 手順 | Proxmox ノードの IP を逆引きする |
| コマンド | `dig @192.168.11.53 -x 192.168.11.11 +short` |
| 合格条件 | `hip1tk-ppprox01.devoka-jpn.com.` が返ること |

### TC-06: 外部ドメインへのフォワード

| 項目 | 内容 |
| :--- | :--- |
| 目的 | 内部ゾーン以外のクエリがゲートウェイへ転送されること |
| 手順 | 外部ドメインを内部 DNS サーバへ問い合わせる |
| コマンド | `dig @192.168.11.53 google.com A +short` |
| 合格条件 | Google のグローバル IP が返ること（SERVFAIL にならないこと） |

### TC-07: Secondary によるゾーン解決

| 項目 | 内容 |
| :--- | :--- |
| 目的 | ゾーン転送が完了し、Secondary も権威応答できること |
| 手順 | Secondary へ直接問い合わせる |
| コマンド | `dig @192.168.11.54 hip1tk-ppprox01.devoka-jpn.com A +short` |
| 合格条件 | Primary と同一の結果が返ること |

### TC-08: ゾーン転送の正常性確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | AXFR（ゾーン転送）が TSIG 認証付きで成功していること |
| 手順 | Primary の named ログでゾーン転送を確認する |
| コマンド | `journalctl -u named --no-pager \| grep "transfer of"` |
| 合格条件 | `Transfer completed` のログが存在すること |

---

## 5. フェーズ 3: Kea DHCP 動作確認

### TC-09: IP アドレス配布確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Kea がプール範囲内の IP を正しく配布すること |
| 手順 | 試験用クライアント（またはhip1tk-pvdesk01）で DHCP リクエストを発行し、取得 IP を確認する |
| コマンド | `ip addr show` でリース IP を確認 / または `kea-shell` でリース一覧を取得 |
| 合格条件 | `192.168.11.100` 〜 `192.168.11.200` 内の IP が割り当てられること |

### TC-10: DHCP Option 6（DNS サーバ）配布確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | DNS サーバアドレスが両 VM のアドレスで配布されること |
| 手順 | クライアントのリース情報を確認する |
| コマンド | `resolvectl status` または `/etc/resolv.conf` を確認 |
| 合格条件 | `nameserver 192.168.11.53` と `nameserver 192.168.11.54` が設定されていること |

### TC-11: Kea HA 同期状態確認

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Primary / Standby 間でリース情報が同期されていること |
| 手順 | Kea Control Agent の REST API でステータスを取得する |
| コマンド | `curl -s -X POST http://192.168.11.53:8000/ -d '{"command":"ha-heartbeat","service":["dhcp4"]}' \| jq .` |
| 合格条件 | レスポンスに `"state": "hot-standby"` が含まれること |

---

## 6. フェーズ 4: DDNS 動作確認

### TC-12: DHCP リース時の DNS 自動登録

| 項目 | 内容 |
| :--- | :--- |
| 目的 | IP 配布と同時に A レコード・PTR レコードが自動登録されること |
| 手順 | 1. クライアントの DHCP リースを更新する<br>2. DNS へそのホスト名で問い合わせる |
| コマンド | `sudo dhclient -r && sudo dhclient` 後に `dig @192.168.11.53 <hostname>.devoka-jpn.com A +short` |
| 合格条件 | リースされた IP が DNS から返ること |

### TC-13: hip1tk-pvdesk01 のホスト名解決

| 項目 | 内容 |
| :--- | :--- |
| 目的 | DHCP 配布の管理 VM が LAN 内からホスト名でアクセスできること |
| 手順 | Proxmox ノードから hip1tk-pvdesk01 をホスト名で ping する |
| コマンド | `ping -c 3 hip1tk-pvdesk01.devoka-jpn.com`（hip1tk-ppprox01 から実行） |
| 合格条件 | 正しい IP へ到達し、パケットロスなく応答すること |

### TC-14: DHCP リース解放時の DNS レコード削除

| 項目 | 内容 |
| :--- | :--- |
| 目的 | リース解放後に A レコード・PTR レコードが削除されること |
| 手順 | 1. `sudo dhclient -r` でリース解放<br>2. DNS へそのホスト名で問い合わせる |
| コマンド | `dig @192.168.11.53 <hostname>.devoka-jpn.com A` |
| 合格条件 | `NXDOMAIN` が返ること（レコードが存在しないこと） |

---

## 7. フェーズ 5: 冗長化動作確認

> **注意**: 本フェーズでは Primary VM を意図的に停止する。試験後は必ず Primary を再起動し、全サービスの復旧を確認すること。

### TC-15: Primary 停止時の DNS 継続性

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Primary 停止後も Secondary で名前解決が継続されること |
| 手順 | 1. hip1tk-pvdns01 を Proxmox からシャットダウン<br>2. Secondary へ名前解決を問い合わせる<br>3. クライアントの `/etc/resolv.conf` の 2 番目 DNS で解決されることを確認 |
| コマンド | `dig @192.168.11.54 hip1tk-ppprox01.devoka-jpn.com A +short` |
| 合格条件 | Secondary から正しい IP が返ること |

### TC-16: Primary 停止時の DHCP 継続性

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Primary 停止後に Standby が IP 配布を引き継ぐこと |
| 手順 | 1. hip1tk-pvdns01 シャットダウン後、mclt（3600s）待機またはフェールオーバー強制移行<br>2. 試験クライアントで DHCP リクエストを発行し、IP を取得できることを確認 |
| コマンド | `sudo dhclient -r && sudo dhclient` 後に IP 取得確認 |
| 合格条件 | プール範囲内の IP が割り当てられること |

### TC-17: Primary 復旧後の正常化

| 項目 | 内容 |
| :--- | :--- |
| 目的 | Primary 復旧後に両サーバが正常状態に戻ること |
| 手順 | 1. hip1tk-pvdns01 を起動<br>2. Kea HA ステータスと BIND9 ゾーン転送ログを確認 |
| コマンド | TC-08 / TC-11 のコマンドを再実行 |
| 合格条件 | HA ステータスが `hot-standby` に戻り、ゾーン転送が完了すること |

---

## 8. 合否判定基準

| フェーズ | 必須 TC | 任意 TC |
| :--- | :--- | :--- |
| フェーズ 1（VM・OS） | TC-01, TC-02, TC-03 | - |
| フェーズ 2（DNS） | TC-04, TC-05, TC-06, TC-07 | TC-08 |
| フェーズ 3（DHCP） | TC-09, TC-10 | TC-11 |
| フェーズ 4（DDNS） | TC-12, TC-13 | TC-14 |
| フェーズ 5（冗長化） | TC-15, TC-16, TC-17 | - |

すべての必須 TC が合格した場合、構築完了とみなす。

---

## 9. 試験結果記録

試験実施後は以下の表に結果を記録する。

| TC | 試験名 | 結果 | 実施日 | 備考 |
| :--- | :--- | :--- | :--- | :--- |
| TC-01 | SSH ログイン確認 | - | | |
| TC-02 | ホスト名・IP 確認 | - | | |
| TC-03 | サービス起動確認 | - | | |
| TC-04 | 固定エントリ正引き解決 | - | | |
| TC-05 | 逆引き解決 | - | | |
| TC-06 | 外部ドメインへのフォワード | - | | |
| TC-07 | Secondary によるゾーン解決 | - | | |
| TC-08 | ゾーン転送の正常性確認 | - | | |
| TC-09 | IP アドレス配布確認 | - | | |
| TC-10 | DHCP Option 6 配布確認 | - | | |
| TC-11 | Kea HA 同期状態確認 | - | | |
| TC-12 | DHCP リース時の DNS 自動登録 | - | | |
| TC-13 | hip1tk-pvdesk01 のホスト名解決 | - | | |
| TC-14 | DHCP リース解放時の DNS 削除 | - | | |
| TC-15 | Primary 停止時の DNS 継続性 | - | | |
| TC-16 | Primary 停止時の DHCP 継続性 | - | | |
| TC-17 | Primary 復旧後の正常化 | - | | |
