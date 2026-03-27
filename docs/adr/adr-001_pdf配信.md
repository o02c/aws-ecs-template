# ADR-001: PDF配信アーキテクチャ — CloudFront Signed URL + S3

- **ステータス**: 承認済み

---

## 背景・前提

### システム概要

- CloudFront / ALB / ECS を中心としたフルスタック構成
- CloudFrontはお客様向けに静的資材の配信と、VPC origin経由でALBへのAPI通信の2動線を持つ
- お客様動線と内部管理動線の2系統が存在する

### 要件

- ECS上でPDFをオンデマンド生成し、ユーザーへ配信する
- ネットワーク断によるダウンロード失敗リスクを軽減したい
- 生成されたPDFを内部の管理画面からも参照できること
- 配信URLは期限付きであること（セキュリティ要件）
- お客様向けと管理者向けでドメインを分離すること

---

## 検討した選択肢

### 案A: ECSから直接PDFをレスポンスで返す

- ECSがPDFバイト列をそのままHTTPレスポンスとして返す
- **問題点**: ダウンロード中のネットワーク断で再試行が困難。ECSスレッドが転送完了まで占有される。管理画面からの再参照が難しい

### 案B: S3にアップロードしてS3 Presigned URLで配信

- S3 Presigned URLの有効期限はIAMロール（ECSタスクロール）に依存
- ECSタスクロールの最大セッション時間は12時間が上限であり、運用上の制約になりうる
- CloudFrontドメインを使えないためURLのブランディング統一ができない

### 案C（採用）: S3にアップロードしてCloudFront Signed URLで配信

- 有効期限をIAM認証情報と独立して設定可能
- CloudFrontカスタムドメインでURLを統一できる
- OAC（Origin Access Control）でS3への直接アクセスを完全遮断
- お客様用・管理用で別CloudFront Distributionを立て、同一S3バケットを参照

---

## 決定内容

**案C（CloudFront Signed URL + S3）を採用する。**

### アーキテクチャ概要

```
お客様
  └─ CloudFront (pdf.example.com)
        └─ S3 bucket [OAC保護・非公開]

管理者
  └─ CloudFront (admin.internal.example.com)
        └─ S3 bucket [同上・OAC保護]

ECS (PDF APIサービス)
  ├─ PDF生成
  ├─ S3アップロード
  └─ CloudFront Signed URL生成 → レスポンス返却
```

### 主要コンポーネントと役割

| コンポーネント | 役割 |
|---|---|
| S3 bucket | PDF永続保存。完全非公開（パブリックアクセスブロック済み） |
| OAC | CloudFront以外からのS3アクセスを拒否 |
| CloudFront（お客様用） | `pdf.example.com`。Signed URL必須。有効期限：1時間 |
| CloudFront（管理用） | `admin.internal.example.com`。Signed URL必須。有効期限：24時間 |
| CloudFront キーグループ | 両Distributionで共用。Signed URL検証に使用 |
| Secrets Manager | 署名用秘密鍵の保管。ECS起動時に一度取得しメモリキャッシュ |

### 有効期限切れ時の再発行

- S3オブジェクトは再生成不要
- DBに保存したS3キー（例: `pdfs/ORD-001.pdf`）から新規Signed URLを発行するだけ
- 管理画面はオンデマンドでURLを発行するAPIエンドポイントを提供する

---

## 結果・トレードオフ

### メリット

- ECSはURLを返すだけで転送完了を待たなくてよい → スレッド効率が向上
- CloudFront経由でPDFを配信するためエッジキャッシュの恩恵を受けられる
- Signed URLの有効期限をIAMから独立して制御可能
- S3直接アクセスをOACで完全遮断 → URLが漏洩してもS3 URLからは取得不可

### 注意点

- CloudFrontキーペアの管理が必要（秘密鍵の安全な保管・ローテーション）
- Signed URLはキャッシュキーにクエリパラメータを含むため、CloudFrontキャッシュは基本的に効かない（PDFはオリジンから毎回取得）
- キャッシュを有効にする場合はSigned URLのクエリパラメータをキャッシュキーから除外する設定が必要だが、セキュリティとのトレードオフになる

---

## 補足: 実装サンプル

### 秘密鍵のメモリキャッシュ

Secrets Managerへの毎回アクセスを避けるため、ECSプロセス起動時に一度だけ取得してメモリに保持する。

```python
import boto3
from datetime import datetime, timezone, timedelta
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from botocore.signers import CloudFrontSigner

S3_BUCKET      = "myapp-pdf-storage"
CF_DOMAIN      = "pdf.example.com"
CF_KEY_PAIR_ID = "K2JCJMDEHXQW5F"
SECRET_NAME    = "myapp/cloudfront-private-key"
SIGNED_URL_TTL = 60 * 60  # 1時間

secrets_client = boto3.client("secretsmanager")

# プロセス内キャッシュ（ECS タスク起動ごとに1回だけ Secrets Manager を叩く）
_PRIVATE_KEY = None

def _get_private_key_cached():
    global _PRIVATE_KEY
    if _PRIVATE_KEY is None:
        resp = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        _PRIVATE_KEY = serialization.load_pem_private_key(
            resp["SecretString"].encode(), password=None
        )
    return _PRIVATE_KEY

def _rsa_signer(message: bytes) -> bytes:
    """CloudFrontSigner が要求する署名関数。秘密鍵はキャッシュ済み。"""
    key = _get_private_key_cached()
    return key.sign(message, padding.PKCS1v15(), hashes.SHA1())

def create_signed_url(
    s3_key: str,
    domain: str = CF_DOMAIN,
    ttl_seconds: int = SIGNED_URL_TTL,
) -> str:
    """
    CloudFront Signed URL を生成する。
    domain を切り替えるだけでお客様用・管理用の両方に対応。
    """
    cf_signer = CloudFrontSigner(CF_KEY_PAIR_ID, _rsa_signer)
    url        = f"https://{domain}/{s3_key}"
    expire_at  = datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
    return cf_signer.generate_presigned_url(url, date_less_than=expire_at)


# --- お客様向け（有効期限: 1時間）---
# signed_url = create_signed_url("pdfs/ORD-001.pdf")

# --- 管理用（有効期限: 24時間、別ドメイン）---
# signed_url = create_signed_url(
#     "pdfs/ORD-001.pdf",
#     domain="admin.internal.example.com",
#     ttl_seconds=60 * 60 * 24,
# )
```

### キャッシュの注意点

- `_PRIVATE_KEY` はプロセス内グローバル変数のため、ECSタスクが再起動するとリセットされる
- キーローテーション時は新しい秘密鍵をSecrets Managerに登録した後、ECSタスクを再起動して反映させる
- マルチスレッド環境では初回の同時呼び出しで複数回取得される可能性があるが、取得結果は同一なので機能上の問題はない。厳密にしたい場合は `threading.Lock` で排他制御する