# devoka-homelab

商用Readyな自宅IaaS基盤を構築・管理するための統合リポジトリです。

Proxmox VEをコア技術とし、TerraformとAnsibleを用いたInfrastructure as Code (IaC) を実践しています。また、本プロジェクトは「SPEC駆動開発」および「AI駆動開発（Cline / Claude Code）」の実験・実践環境でもあります。

## 📝 概要 / Overview

本リポジトリは、Qiitaにおける自宅IaaS環境構築の連載記事と連動しています。

記事内で解説しているアーキテクチャや各種設定ファイルの実稼働コードを公開・管理するためのポートフォリオとして機能します。

🔗 **関連リンク**
- [devoka-jpn の Qiita マイページ](https://qiita.com/devoka-jpn)

## 🛠 技術スタック / Tech Stack

- **Virtualization & Cloud:** Proxmox VE, OpenStack
- **Provisioning (IaC):** Terraform
- **Configuration (IaC):** Ansible
- **Core Services:**
  - OS: Ubuntu Server
  - DDNS: Bind
  - IDM: OpenLDAP
  - Project Management: Redmine
- **AI Agents:** Cline, Claude Code

## 🏗 ディレクトリ構成 / Architecture

インフラにおける「仕様（SPEC）」を中心としたモノレポ構成を採用し、AIエージェントがシステムの全体像と文脈を正確に把握できるように設計されています。

```text
.
├── docs/                   # AIと人間のための「真実の情報源（SPEC）」とアーキテクチャ図
├── specs/                  # インフラの要件を定義したYAML等のテンプレート（SPEC駆動の核）
├── iac/                    # プロビジョニング層（Terraform / Packer）
├── configuration/          # コンフィグレーション層（Ansible Roles / Playbooks）
├── .clinerules             # Cline用のコーディング規約・システムプロンプト
└── .claude.json            # Claude Code用のコンテキスト設定

```

*(※ セキュリティ保護のため、実際のパスワードやTFStateなどの機密情報はGitの管理外としています。)*

## ⚠️ 注意事項 / Note

This repository is maintained as a personal portfolio and a reference for Qiita articles. Therefore, Pull Requests are not accepted.

(本リポジトリは個人のポートフォリオおよびQiita連載記事の参照用として管理しているため、Pull Requestは受け付けておりません。コードの利用や参考についてはMITライセンスの範囲内でご自由にどうぞ。)

## 📄 License

This project is licensed under the MIT License
