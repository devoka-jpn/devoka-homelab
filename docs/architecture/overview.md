# システムアーキテクチャ概要

## 1. 目的と背景

本システムは、システムエンジニアとしての技術力向上と、モダンなインフラ技術の継続的な実践・発信を目的として構築するプライベートIaaS基盤である。

* **モダン開発手法の「手で覚える」実践**
  商用環境で標準となっているIaC（Terraform, Ansible）やCI/CDパイプライン、そしてAI駆動開発といったアプローチを、単なる知識ではなく実稼働する環境として構築し、血肉となるスキルとして習得する。

* **「教える」エンジニアへの到達**
  学習の4フェーズである「知る・分かる・できる・教える」を体現する中核的な場とする。自ら手を動かして「できる」状態を構築した上で、技術記事としての継続的なアウトプット（教える）を行い、他者の学習を牽引できるエンジニアを目指す。

* **実用的なサービスのホスティングと運用**
  単なる技術検証の使い捨て環境（サンドボックス）にはせず、日常生活を豊かにする便利なアプリケーションやツールを実際にホスティングし、商用Readyな可用性と運用品質を維持する。

## 2. 基本アーキテクチャと全体構成図

本基盤は、オンプレミスの物理ハードウェアを土台とし、ハイパーバイザーによるリソースの抽象化、および商用要件を満たすための強固な付帯系（共通サービス）システム群から構成される。

システム全体の解像度を高め、人間にとっての直感的な理解と視認性を担保するため、アーキテクチャ図は「物理」「論理ネットワーク」「サービス」の3つのフェーズに分割してSVG形式で定義する。

### 2.1. 物理レイヤー (Physical Layer)

システム全体の計算資源（CPU、メモリ）と物理的なデータ保存領域を提供する最下層のハードウェア基盤である。3台のベアメタルPCノードと、物理ネットワーク機器（L2/L3スイッチ等）で構成される。


![物理配線図](../assets/images/01_physical_wiring.drawio.svg)

**物理ノード インベントリ**

| Hostname | Model / CPU | RAM | Storage | Management IP |
| :--- | :--- | :--- | :--- | :--- |
| hip1tk-ppprox01 | GMKtec Mini PC<br>(Intel Twin Lake-N150 4C/4T) | 12GB DDR5 | 512GB SSD | 192.168.11.11 |
| hip1tk-ppprox02 | GMKtec Mini PC<br>(Intel Twin Lake-N150 4C/4T) | 12GB DDR5 | 512GB SSD | 192.168.11.12 |
| hip1tk-ppprox03 | TOSHIBA Dynabook T55/CBS<br>(CPU未定) | 20GB | 1TB (推定) | 192.168.11.13 |

*(※ 詳細なネットワーク定義やMACアドレスマッピングは `docs/specs/network.yaml` で一元管理する)*

### 2.2. 論理ネットワークとハイパーバイザー (Logical Network & Hypervisor Layer)

物理ノード上に **Proxmox VE クラスタ** を構築し、ハードウェアリソースをプール化・抽象化する。
ネットワークは管理、ストレージ同期、およびテナント（VM）の各トラフィックを単一のフラットなL2ネットワーク（`192.168.11.0/24`）に統合して運用する。これにより、物理ハードウェアのNIC制約をクリアしつつ、IaCによるプロビジョニングやCI/CDパイプラインの実践にフォーカス可能な基盤とする。


![論理ネットワーク図](../assets/images/02_logical_network.drawio.svg)

### 2.3. 運用・管理・付帯系レイヤー (Core Services & Management Layer)

ハイパーバイザー上で稼働し、基盤全体の運用、セキュリティ、および可観測性を担保する必須コンポーネント群である。これらはIaC（Terraform / Ansible）によって状態が管理される。


![サービスアーキテクチャ図](../assets/images/03_service_architecture.drawio.svg)

* **監視・モニタリング (Zabbix):** ハードウェアからミドルウェアまでの死活監視、パフォーマンスメトリクス収集、異常検知。
* **統合認証・IDM (OpenLDAP):** 基盤内の全システム・機器に対するアカウント管理とアクセス権限の一元化。
* **プロジェクト・運用管理 (Redmine):** 構成変更の履歴（チケット）、タスク管理、インシデント対応のトラッキング。
* **名前解決・DDNS (BIND9 + Kea DHCP):** 内部ネットワークにおける動的な名前解決とゾーン管理。Primary / Secondary の冗長構成で `devoka-jpn.com` ゾーンを管理し、DHCP 配布と連動した動的 DNS 登録（DDNS）を実現する。詳細は [`docs/specs/ddns.md`](../specs/ddns.md) を参照。

**管理系VMインベントリ**

| Hostname | VMID | 役割 | OS | vCPU | RAM | Disk | IP アドレス |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| hip1tk-pvdesk01 | 103 | IaaS管理踏み台VM（IaC実行・開発基盤） | Ubuntu 24.04.4 LTS | 4 | 8GiB | 25GiB | 動的（DDNS） |
| hip1tk-pvdns01 | 200 | Primary DNS / DHCP サーバ | Ubuntu 24.04.4 LTS | テンプレートデフォルト | テンプレートデフォルト | テンプレートデフォルト | 192.168.11.53 |
| hip1tk-pvdns02 | 201 | Secondary DNS / DHCP サーバ | Ubuntu 24.04.4 LTS | テンプレートデフォルト | テンプレートデフォルト | テンプレートデフォルト | 192.168.11.54 |
| hip1tk-pvzbxlb01 | 300 | Zabbix LB1 (HAProxy MASTER) | Ubuntu 24.04.4 LTS | 2 | 2GiB | 20GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxlb02 | 301 | Zabbix LB2 (HAProxy BACKUP) | Ubuntu 24.04.4 LTS | 2 | 2GiB | 20GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxsv01 | 302 | Zabbix Server 1 (Active) | Ubuntu 24.04.4 LTS | 4 | 4GiB | 30GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxsv02 | 303 | Zabbix Server 2 (Standby) | Ubuntu 24.04.4 LTS | 4 | 4GiB | 30GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxfe01 | 304 | Zabbix Frontend 1 | Ubuntu 24.04.4 LTS | 2 | 2GiB | 20GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxfe02 | 305 | Zabbix Frontend 2 | Ubuntu 24.04.4 LTS | 2 | 2GiB | 20GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxdb01 | 306 | Zabbix DB Primary (Patroni) | Ubuntu 24.04.4 LTS | 4 | 8GiB | 50GiB | 動的（DHCP/DDNS）|
| hip1tk-pvzbxdb02 | 307 | Zabbix DB Replica (Patroni) | Ubuntu 24.04.4 LTS | 4 | 8GiB | 50GiB | 動的（DHCP/DDNS）|

*(※ hip1tk-pvdesk01 はTerraform/Ansible等のIaCツールを実行する管理専用VMであり、Proxmoxクラスタ上のKVM仮想マシンとして稼働する。IPアドレスはDDNSにより動的に割り当てられる。)*
*(※ hip1tk-pvdns01/02 の詳細仕様・設計は [`docs/specs/ddns.md`](../specs/ddns.md) を参照。)*
*(※ hip1tk-pvzbx* の詳細仕様・設計は [`docs/specs/zabbix.md`](../specs/zabbix.md) を参照。Keepalived VIP は `192.168.11.200` を使用。)*

### 2.4. ホスティング・テナントレイヤー (Tenant Layer)

付帯系サービスによる統制の下で稼働する、実用アプリケーション群、技術検証用のサンドボックス環境、および **OpenStack** 等のクラウドコントロールプレーンが展開される領域。
## 3. コアコンポーネントと技術スタック

### 3.1. IaC ツールチェーン

| ツール | 用途 | バージョン要件 |
| :--- | :--- | :--- |
| Terraform | VM・ネットワークのプロビジョニング（Proxmox VE リソース管理） | >= 1.5 |
| Terraform Provider: bpg/proxmox | Proxmox VE API との通信 | ~> 0.73 |
| Ansible | OS初期設定・ミドルウェア構成管理 | 最新安定版 |

### 3.2. Terraform ディレクトリ構成

```
terraform/
├── environments/
│   └── proxmox/        # Proxmox VE 環境定義（プロバイダ設定・変数定義）
├── modules/
│   └── vm/             # 再利用可能な VM プロビジョニングモジュール
└── secrets/            # 機密情報（.gitignore で除外）
    └── terraform.tfvars
```

### 3.3. Ansible ディレクトリ構成

```
ansible/
├── ansible.cfg
├── inventories/
│   └── proxmox/
│       └── hosts.yml   # Proxmox ノードインベントリ
├── playbooks/
├── roles/
├── group_vars/
├── host_vars/
└── secrets/            # Vault パスワード等（.gitignore で除外）
```

### 3.4. Proxmox VE 接続情報

| 項目 | 値 |
| :--- | :--- |
| APIエンドポイント | `https://192.168.11.11:8006` |
| 認証方式 | APIトークン（`USER@REALM!TOKENID=SECRET`形式） |
| TLS検証 | 無効（自己署名証明書のため） |
| VMテンプレートID | `9000`（cloud-initテンプレート） |

認証情報は `terraform/secrets/terraform.tfvars` に格納し、Git管理から除外する。

## 4. ネットワーク・VLAN設計の基本方針
## 5. 物理ノードとリソース割り当ての方針