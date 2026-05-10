# パスベースルーティング — アプリチーム向け共有

本番インフラが **単一ドメイン + path 振り分け** に切り替わったので、開発環境 (docker-compose) とデプロイ用ファイルで揃えてほしい点をまとめます。

---

## 1. 本番の構成 (前提)

CloudFront 1 個 → path で振り分け → user / admin それぞれの ALB / S3:

| Path | 配信先 | 中身 |
|---|---|---|
| `/` | user S3 | user フロント (React build) |
| `/api/*` | user ALB → user-api | user API (Django) |
| `/admin/` | admin S3 | admin フロント (React build) |
| `/admin/*` | admin S3 | admin の他静的 |
| `/admin/api/*` | admin ALB → admin-api | admin API (Django) |
| `/files/*` | user S3 (signed URL) | アップロードファイル配信 |

`/admin` (slash なし) は CloudFront Function が **301 → `/admin/`** にする。`/admin/` は同 Function で **`/admin/index.html` に rewrite**。`/` は `default_root_object = "index.html"` で apex の `index.html` を返す。

ALB は CloudFront から path をそのまま転送する (rewrite なし)。つまり Django が受ける URL は `/admin/api/health` のように **path prefix 込み**。

詳細: [docs/architecture.md](architecture.md)

---

## 2. dev 環境 (docker-compose) で揃えてほしいこと

本番と同じ path 構造を local でも再現してほしい。理由:

- React build 後の asset URL は `base` 設定 (`/admin/` 等) によって変わるため、本番だけで初めて崩れることがある
- `<a href>` / React Router の link が path prefix 前提
- API fetch 先 (`/api` or `/admin/api`) はアプリコードに直接書かれる
- Django の URLconf は `admin/api/...` のように prefix 込みで定義する必要がある

### 2.1 nginx (reverse proxy)

docker-compose に nginx を 1 つ立てて全リクエストを受ける構成を推奨:

```nginx
# 例: dev/nginx.conf
upstream user_django  { server user-django:8080; }
upstream admin_django { server admin-django:8080; }
upstream user_front   { server user-frontend:3000; }
upstream admin_front  { server admin-frontend:3000; }

server {
  listen 80;

  # API は最も specific なものから
  location /admin/api/ {
    proxy_pass http://admin_django;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  location /api/ {
    proxy_pass http://user_django;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # admin frontend (Vite dev server なら proxy、ビルド済みなら alias で配信)
  location /admin/ {
    proxy_pass http://admin_front/;   # 末尾の / で prefix を strip
    # 本番ビルド配信なら: alias /var/www/admin/;
  }

  # default → user frontend
  location / {
    proxy_pass http://user_front/;
    # 本番ビルド配信なら: alias /var/www/user/;
  }
}
```

ポイント:
- `/admin/api/` を `/api/` より先に書かないと `/api/` が先にマッチして admin リクエストが user-django に流れる
- Vite dev server を proxy する場合 HMR 用 WebSocket (`/admin/@vite/client` 等) も通る (proxy_pass で透過するので OK)

### 2.2 Django URLconf

URL は **path prefix 込み**で定義:

```python
# user-api/config/urls.py
from django.urls import path
from api import views
urlpatterns = [
    path("api/health", views.health),
    path("api/users", views.list_users),
    # ...
]

# admin-api/config/urls.py
urlpatterns = [
    path("admin/api/health", views.health),
    path("admin/api/dashboard", views.dashboard),
    # ...
]
```

> 代替案: Django の `FORCE_SCRIPT_NAME = "/admin"` を入れれば admin 側 URLconf を `path("api/...")` のままにできる。ただし ECS container health check が `http://localhost:8080/admin/api/health` を直叩きするので **URLconf に prefix を含める方が混乱しない**。本テンプレートも URLconf 直書き。

### 2.3 React (Vite) の base path

`apps/<lane>-frontend/vite.config.ts`:

```ts
// admin-frontend
export default defineConfig({
  base: "/admin/",         // ← 必須。asset URL が /admin/assets/... になる
});

// user-frontend
export default defineConfig({
  base: "/",               // 省略可
});
```

React Router を使う場合は basename も合わせる:
```tsx
<BrowserRouter basename="/admin">...</BrowserRouter>
```

base を `/` のまま admin をビルドすると、`/admin/index.html` の中の `<script src="/assets/foo.js">` が user S3 を見にいって 404 になります。

### 2.4 環境変数 (Django)

| 変数 | dev での値 | 本番での値 |
|---|---|---|
| `DJANGO_SECRET_KEY` | 適当な開発用 | SSM Parameter Store (Secrets) |
| `ALLOWED_HOSTS` | `localhost,127.0.0.1` | `localhost,127.0.0.1,<本番ドメイン>` |
| `DJANGO_DEBUG` | `true` | `false` (prod) / `true` (dev env) |
| `S3_BUCKET_NAME` | minio やダミー | terraform output から ECS env に注入 |
| `CLOUDFRONT_DOMAIN` | (signed URL を dev で使うなら) | 本番ドメイン |
| `CLOUDFRONT_KEY_PAIR_ID`, `CLOUDFRONT_SIGNING_KEY_SECRET_ARN` | 空 | terraform 経由 |
| `SES_FROM_ADDRESS`, `SES_ALLOWED_RECIPIENTS`, `SES_ENDPOINT_URL` | 空 / mock | terraform output |

### 2.5 CORS / CSRF / Cookie

単一ドメインなので **CORS は不要**。Cookie の `Domain` 属性も指定不要 (現在ドメインに自動紐付け)。

`CSRF_TRUSTED_ORIGINS` は本番ドメインを env から渡す:
```python
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in os.environ.get("ALLOWED_HOSTS","").split(",") if "." in h]
```

### 2.6 ログ出力 (本番のパイプライン前提)

本番では container の stdout を **FireLens (fluent-bit) → Kinesis Firehose → S3** で集約し、`type=audit` のレコードだけ別 stream に切り分ける構成。詳細は [docs/logs.md](logs.md)。

#### ログ源と JSON 化の指定箇所

Django プロセス内には **gunicorn と Django の logger が独立**して存在し、それぞれ別々に JSON 化を指定する必要がある。

| ログ源 | JSON 化方法 | 設定場所 |
|---|---|---|
| gunicorn 自体（起動 / worker boot / signal / error） | `--logger-class config.gunicorn_logger.JsonLogger` | `Dockerfile` の `CMD` |
| Django framework（system check, autoreload, request 等） | `LOGGING["loggers"]["django"]` を console handler (`JsonFormatter`) に紐付け | `config/settings.py` |
| アプリ (`logging.getLogger(__name__)`) | `LOGGING["root"]` を同上 console handler に紐付け | 同上 |
| 監査 (`logging.getLogger("audit")`) | `LOGGING["loggers"]["audit"]` を同上 console handler に紐付け | 同上 |

#### `config/settings.py` の `LOGGING` dict 必須形

```python
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "config.logging_formatter.JsonFormatter"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "json"},
    },
    "root":    {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django":         {"handlers": ["console"], "level": "INFO", "propagate": False},
        "django.request": {"handlers": ["console"], "level": "INFO", "propagate": False},
        "audit":          {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}
```

ハマりどころ:
- **`disable_existing_loggers: False`** — Django 内部 logger が settings 適用前のデフォルト (text formatter) で残るのを防ぐ
- **`propagate: False`** — `django` logger が root にも伝播して二重出力するのを防ぐ
- 新しい子 logger を作る時は同じ pattern (`handlers=["console"], propagate=False`) を踏襲
- traceback は **`JsonFormatter` が `"traceback"` フィールドにまとめて 1 行に入れる**（multiline log は Firehose で別レコード扱いされて検索不能になる）

#### アプリ側に求められること

1. **stdout は 1 行 1 JSON object**
   - 上記 `LOGGING` dict + `--logger-class` の両方を入れること（片方だけだと起動ログだけ text、リクエストログは JSON、のような混在になる）

2. **audit ログは専用 logger + `extra={"type": "audit", ...}`**
   ```python
   audit_logger = logging.getLogger("audit")
   audit_logger.info(
       "File uploaded",
       extra={"type": "audit", "action": "file_upload", "resource": s3_key, "user_id": ...},
   )
   ```
   `type=audit` がフィールドに入るとfluent-bit が **Firehose の audit stream → S3 `audit/year=YYYY/month=MM/day=DD/`** に振り分ける。それ以外のログは `ecs-logs/` 配下。

3. **追加フィールドは `JsonFormatter` の許可リストに登録**
   `apps/user-api/config/logging_formatter.py` で `("type", "user_id", "action", "resource", "detail")` のみが `extra=` から JSON に出力される。新フィールドを足す時はこの tuple を編集。

4. **dev では FireLens なし、stdout 直見でよい**
   ```bash
   docker compose logs -f user-django | jq .   # JSON parse できるか確認
   ```
   `audit_logger.info(..., extra={"type":"audit", ...})` を打って `type` フィールドが出力 JSON に含まれることを確認すれば、本番の routing が効く前提が取れる。

5. **gunicorn の access log は OFF**
   nginx 側で取るので gunicorn は `--access-logfile /dev/null`。アクセスログ二重化を避ける。

---

## 3. デプロイ向けに用意するファイル

### 3.1 Django app

| 必須 | ファイル | 備考 |
|---|---|---|
| ✅ | `Dockerfile` | `linux/amd64`、gunicorn 起動。`apps/user-api/Dockerfile` 参照 |
| ✅ | `requirements.txt` | `gunicorn`, `django`, `boto3`, `cryptography` (signed URL 用) |
| ✅ | `config/urls.py` | path prefix 込み URLconf (上記 2.2) |
| ✅ | `config/settings.py` | env 駆動 (`os.environ.get(...)`) |
| ✅ | `config/wsgi.py` | gunicorn が import する WSGI entrypoint |
| ✅ | `api/views.py` | **health endpoint 必須** |
| ✅ | `config/logging_formatter.py` | `JsonFormatter`。`apps/user-api/config/logging_formatter.py` をコピペ。新フィールド追加時は許可リストに足す |
| ✅ | `config/gunicorn_logger.py` | gunicorn 起動ログを JSON 化する `JsonLogger`。`apps/user-api/config/gunicorn_logger.py` をコピペ |
| ✅ | `config/settings.py` の `LOGGING` | `json` formatter + console handler、root / django / **audit** logger を定義 |

#### health endpoint の規約

| Service | URL | レスポンス |
|---|---|---|
| user-api | `GET /api/health` | `{"status":"ok","service":"user-api"}` 200 |
| admin-api | `GET /admin/api/health` | `{"status":"ok","service":"admin-api"}` 200 |

これは **ECS container 内の gunicorn を直接** 叩くヘルスチェック (port 8080)。一方 ALB target group は **nginx sidecar の `/health`** (port 80) を叩く別経路。両方独立で動かす必要がある。

#### Dockerfile 参考

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8080", \
     "--access-logfile", "/dev/null", "--error-logfile", "-", \
     "--logger-class", "config.gunicorn_logger.JsonLogger"]
```

`--access-logfile /dev/null` は nginx 側で取るので gunicorn 側は OFF。`--logger-class` で `gunicorn_logger.JsonLogger` を使うと error log も JSON で吐く (`apps/user-api/config/gunicorn_logger.py` 参照)。

### 3.2 React app

| 必須 | ファイル / 出力物 | 備考 |
|---|---|---|
| ✅ | `vite.config.ts` (or 同等) | `base` を lane の path prefix に設定 (上記 2.3) |
| ✅ | `package.json` | `npm run build` が `dist/` を出力すること |
| ✅ | `dist/index.html` | base 込みで asset URL がビルド済み |
| ✅ | `dist/assets/*` | 相対 path で参照される js / css / img |

S3 配置先 (`scripts/deploy.sh` が自動振り分け済み):

| lane | S3 prefix |
|---|---|
| user | `s3://myapp-<env>-user-assets/` (root) |
| admin | `s3://myapp-<env>-admin-assets/admin/` |

開発者側で気にする必要があるのは **`vite build` の出力**だけ。`apps/<lane>-frontend/` 配下に成果物が出ていれば deploy script が拾う。

### 3.3 docker-compose (dev) — リファレンス例

```yaml
# docker-compose.yml
services:
  nginx:
    image: nginx:1.27-alpine
    ports: ["80:80"]
    volumes:
      - ./dev/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on: [user-django, admin-django, user-frontend, admin-frontend]

  user-django:
    build: ./apps/user-api
    environment:
      DJANGO_SECRET_KEY: dev-only-not-for-prod
      ALLOWED_HOSTS: localhost,127.0.0.1,nginx
      DJANGO_DEBUG: "true"
    expose: ["8080"]

  admin-django:
    build: ./apps/admin-api
    environment:
      DJANGO_SECRET_KEY: dev-only-not-for-prod
      ALLOWED_HOSTS: localhost,127.0.0.1,nginx
      DJANGO_DEBUG: "true"
    expose: ["8080"]

  user-frontend:
    image: node:20-alpine
    working_dir: /app
    command: npm run dev -- --host 0.0.0.0
    volumes: ["./apps/user-frontend:/app"]
    expose: ["3000"]

  admin-frontend:
    image: node:20-alpine
    working_dir: /app
    command: npm run dev -- --host 0.0.0.0
    volumes: ["./apps/admin-frontend:/app"]
    expose: ["3000"]
```

DB が必要なら postgres を追加。`ALLOWED_HOSTS` に `nginx` を含めているのは Django が `Host: nginx` のリクエストを受けるため。

---

## 4. 受入チェックリスト (デプロイ前)

ローカルで以下が全部通ること:

- [ ] `docker compose up` 後、ホストの `http://localhost/api/health` → 200 + `{"service":"user-api"}`
- [ ] `http://localhost/admin/api/health` → 200 + `{"service":"admin-api"}`
- [ ] `http://localhost/` で user フロントが描画される
- [ ] `http://localhost/admin/` で admin フロントが描画される
- [ ] DevTools の Network で、admin の `<script>` / `<link>` / fetch URL が **`/admin/...` で始まっている**こと (user S3 に漏れていない)
- [ ] `docker exec <user-django-container> python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/api/health')"` が成功 (ECS container healthcheck 相当)
- [ ] 同様に admin で `.../admin/api/health` が成功
- [ ] **gunicorn の起動ログ含めて全行 JSON** で stdout に出ている (`docker compose logs user-django | jq .` でエラーなくパースできる)
- [ ] `logger.info("...")` した内容が JSON object の `"message"` に入る
- [ ] `audit_logger.info("...", extra={"type":"audit","action":"x","resource":"y"})` を叩いた時の出力 JSON に `"type":"audit"` フィールドが含まれる (本番 routing の前提)
- [ ] `try/except` で `logger.exception(...)` した時、traceback が **同じ JSON entry の `"traceback"` フィールド**に入る (multiline で別行になっていないこと)
- [ ] gunicorn の access log が **出ていない** こと (nginx 側で取るため `--access-logfile /dev/null`)
- [ ] `docker build --platform linux/amd64 .` が成功 (Fargate は amd64)

---

## 5. 新サービスを増やす / path prefix を変える時

`terraform/project/environments/dev/locals.tf` の `lanes` map に追記すれば infra 側の CloudFront / WAF / SG / S3 / ALB は自動で増えます。アプリ側は以下を同期して書き換えてください:

| 場所 | 何を変える |
|---|---|
| `apps/<new-lane>-api/config/urls.py` | URLconf に path prefix 込みで定義 |
| `apps/<new-lane>-frontend/vite.config.ts` | `base` を新 prefix に |
| `dev/nginx.conf` (チーム管理) | location ブロック追加。**必ず specific な順** |
| `apps/<new-lane>-api/config/settings.py` | env 駆動の `ALLOWED_HOSTS` を継承 |

---

## 関連ドキュメント

- [docs/architecture.md](architecture.md) — インフラ全体構成
- [docs/ecspresso.md](ecspresso.md) — ECS デプロイ手順
- [docs/logs.md](logs.md) — ログ集約パイプライン
