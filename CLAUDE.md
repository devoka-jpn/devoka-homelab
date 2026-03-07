# Claude Agent Rules for devoka-homelab

## Communication Style
- 結論ファーストで簡潔に回答すること。
- 言語は必ず「日本語」を使用すること。
- 不要な前置きや謝罪は省き、技術的な事実と次のアクションにフォーカスすること。
- 絵文字は一切使用しないこと。

## SPEC-Driven Development (厳格なルール)
- ドキュメントファースト: コード（Terraform/Ansible等）を記述・変更する前に、必ず `docs/specs/` または `docs/architecture/` の関連仕様書を確認・作成・更新すること。
- 仕様（SPEC）が定義されていない状態で、推測でインフラコードを書いてはならない。

## Execution & Safety (実行と安全性のルール)
- 自動実行を許可 (テスト・Plan):
  - `terraform plan`, `terraform validate`, `terraform fmt`, `ansible-lint`, `ansible-playbook --check` などの「状態を変更しない検証コマンド」は、積極的に自律実行し、結果を評価して修正に役立てること。
- 人間の承認が必須 (Apply・変更):
  - `terraform apply`, `terraform destroy`, 実際のノードに対する `ansible-playbook` の実行など、インフラの状態（State）を変更するコマンドは絶対に自動実行してはならない。必ずPlan結果を提示し、人間の明示的な許可を得ること。

## Git Workflow (ブランチ戦略と完了条件)
1. 作業開始時に、要件に合わせた新しいブランチを作成すること（例: feature/add-proxmox-node）。
2. 作業中は適宜コミットを行うこと（コミットメッセージの厳密な指定はなし）。
3. 作業とテスト（Plan）が完了したらリモートへPushすること。
4. Pull Request（PR）を発行した時点をもって「作業完了」とみなす。PRの概要には、変更内容と更新したSPECファイルへのリンクを記載すること。