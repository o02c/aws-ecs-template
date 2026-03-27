---
name: security-gap-tasks
description: セキュリティガイドテンプレートとの差分から導出された、このプロジェクトで対応すべきセキュリティ強化タスク一覧
type: project
---

## セキュリティ強化タスク一覧 (2026-03-24時点)

### Critical
1. **WAF** - CloudFront前段にWAFv2 WebACL (SQLi/XSS/レート制限)

### High
2. **CloudFrontアクセスログ** - ログ用S3バケット + logging_config
3. **ALBアクセスログ** - access_logs ブロック追加
4. **S3アクセスログ** - ログ専用バケット + logging設定
5. **KMS CMK** - S3, Aurora, CloudWatch Logs, Secrets ManagerにCMK適用
6. **DBパスワード自動ローテーション** - Secrets Manager + ローテーションLambda
7. **Inspector** - ECR/ECSの脆弱性スキャン有効化

### Medium
8. **ECRタグ不変性** - image_tag_mutability = "IMMUTABLE"
9. **地理的制限** - CloudFront geo restriction (JP whitelist)
10. **DNS Firewall** - Route 53 Resolver DNS Firewall

**Why:** セキュリティガイドテンプレート準拠のため。管理アカウント側で対応するもの(CloudTrail, Config, Security Hub, VPC Flow Logs, IAM Access Analyzer, SNS通知)は除外済み。

**How to apply:** 優先度順に実装。既存モジュール構造・命名規則・CLAUDE.mdのコード規約に従う。
