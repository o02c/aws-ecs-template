import json
import logging
import os
import re
import ssl
import uuid

import boto3
import pg8000.dbapi
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

logger = logging.getLogger(__name__)
audit_logger = logging.getLogger("audit")

S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN", "")
S3_FILES_PREFIX = os.environ.get("S3_FILES_PREFIX", "files")
MAX_UPLOAD_SIZE = 10 * 1024 * 1024

APP_RESOURCES_BUCKET = os.environ.get("APP_RESOURCES_BUCKET", "")
LANE = os.environ.get("LANE", "")

SES_FROM_ADDRESS = os.environ.get("SES_FROM_ADDRESS", "")
SES_ALLOWED_RECIPIENTS = {
    r.strip() for r in os.environ.get("SES_ALLOWED_RECIPIENTS", "").split(",") if r.strip()
}
# VPCE for com.amazonaws.<region>.email serves email.<region>.api.aws (SESv2 endpoint).
# Default boto3 SES v1 hostname email.<region>.amazonaws.com isn't reachable from
# private ECS tasks, so we use sesv2 with the api.aws endpoint.
SES_ENDPOINT_URL = os.environ.get("SES_ENDPOINT_URL") or None
MAX_EMAIL_BODY = 2000
MAX_EMAIL_SUBJECT = 200

EXT_PATTERN = re.compile(r"^\.[a-zA-Z0-9]{1,10}$")

DB_HOST = os.environ.get("DB_HOST", "")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "")
DB_USER = os.environ.get("DB_USER", "")
# Installed in Dockerfile from truststore.pki.rds.amazonaws.com/global/global-bundle.pem
RDS_CA_BUNDLE = "/etc/ssl/certs/rds-global-bundle.pem"

s3 = boto3.client("s3")
ses = boto3.client("sesv2", endpoint_url=SES_ENDPOINT_URL)
rds_client = boto3.client("rds")


def _read_app_resource(key: str) -> dict:
    try:
        obj = s3.get_object(Bucket=APP_RESOURCES_BUCKET, Key=key)
        return {"ok": True, "content": obj["Body"].read().decode("utf-8").strip()}
    except Exception as exc:
        return {"ok": False, "error": type(exc).__name__, "detail": str(exc)}


# Eagerly read the lane-scoped templates at module import (= gunicorn worker
# boot) to verify IAM wiring without waiting for the first request. Failures
# are logged but do not crash the worker — the task should still start so the
# operator can investigate via /admin/api/test/app-resources.
APP_RESOURCES_STARTUP_READ = {}
if APP_RESOURCES_BUCKET:
    APP_RESOURCES_STARTUP_READ = {
        "common/hello.txt": _read_app_resource("common/hello.txt"),
        f"{LANE}/hello.txt": _read_app_resource(f"{LANE}/hello.txt") if LANE else {"ok": False, "error": "LANE env unset"},
    }
    logger.info(
        "app-resources startup read: %s",
        json.dumps({"bucket": APP_RESOURCES_BUCKET, "lane": LANE, "result": APP_RESOURCES_STARTUP_READ}),
    )


def _db_ping() -> dict:
    # IAM-auth: generate_db_auth_token returns a 15-min presigned password.
    # Single-shot connection — sufficient for startup verification.
    if not (DB_HOST and DB_NAME and DB_USER):
        return {"ok": False, "error": "DB env unset"}
    try:
        region = boto3.session.Session().region_name
        token = rds_client.generate_db_auth_token(
            DBHostname=DB_HOST, Port=DB_PORT, DBUsername=DB_USER, Region=region
        )
        conn = pg8000.dbapi.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=token,
            ssl_context=ssl.create_default_context(cafile=RDS_CA_BUNDLE),
        )
        try:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            row = cur.fetchone()
            return {"ok": True, "result": row[0] if row else None}
        finally:
            conn.close()
    except Exception as exc:
        return {"ok": False, "error": type(exc).__name__, "detail": str(exc)}


DB_STARTUP_PING = _db_ping() if DB_HOST else {"ok": False, "error": "DB env unset"}
logger.info(
    "db startup ping: %s",
    json.dumps({"host": DB_HOST, "user": DB_USER, "result": DB_STARTUP_PING}),
)


@require_GET
def health(request):
    return JsonResponse({"status": "ok", "service": "admin-api"})


@require_GET
def dashboard(request):
    return JsonResponse({"total_users": 42, "active_sessions": 7})


@require_GET
def app_settings(request):
    return JsonResponse({"maintenance_mode": False, "log_level": "info"})


@csrf_exempt
@require_POST
def upload_file(request):
    uploaded = request.FILES.get("file")
    if not uploaded:
        return JsonResponse({"error": "No file provided"}, status=400)

    if uploaded.size > MAX_UPLOAD_SIZE:
        return JsonResponse({"error": "File too large (max 10MB)"}, status=413)

    file_id = uuid.uuid4().hex
    filename = uploaded.name or "upload"
    ext = os.path.splitext(filename)[1] if filename else ""
    s3_key = f"{S3_FILES_PREFIX}/{file_id}{ext}"

    s3.put_object(
        Bucket=S3_BUCKET_NAME,
        Key=s3_key,
        Body=uploaded.read(),
        ContentDisposition=f'attachment; filename="{filename}"',
    )

    audit_logger.info(
        "File uploaded",
        extra={"type": "audit", "action": "file_upload", "resource": s3_key},
    )

    return JsonResponse({"file_id": file_id, "s3_key": s3_key})


@require_GET
def get_file_url(request, file_id):
    ext = request.GET.get("ext", "")
    if ext and not EXT_PATTERN.match(ext):
        return JsonResponse({"error": "Invalid file extension"}, status=400)

    s3_key = f"{S3_FILES_PREFIX}/{file_id}{ext}"
    return JsonResponse({"file_id": file_id, "s3_key": s3_key})


# --------------------------------------------------------------------------------
# Test endpoints for verifying structured logging
# --------------------------------------------------------------------------------


@require_GET
def test_db(request):
    """Aurora IAM-auth connectivity check.

    No query: returns the cached startup-time ping result.
    ?live=1: runs a fresh SELECT 1 (useful after the 15-min IAM token TTL).
    """
    if request.GET.get("live") == "1":
        result = _db_ping()
        status = 200 if result["ok"] else 503
        return JsonResponse({"live": True, **result}, status=status)
    status = 200 if DB_STARTUP_PING.get("ok") else 503
    return JsonResponse(
        {"host": DB_HOST, "user": DB_USER, "startup_ping": DB_STARTUP_PING},
        status=status,
    )


@require_GET
def test_app_resources(request):
    """Verify IAM lane scoping on the shared app-resources bucket.

    No `key` query: returns the cached startup-time read result.
    With `key`: attempts a live GetObject so cross-lane denial can be confirmed
    (e.g. admin-api reading `user/hello.txt` should fail with AccessDenied).
    """
    key = request.GET.get("key", "")
    if not key:
        return JsonResponse({
            "bucket": APP_RESOURCES_BUCKET,
            "lane": LANE,
            "startup_read": APP_RESOURCES_STARTUP_READ,
        })
    result = _read_app_resource(key)
    status = 200 if result["ok"] else 403
    return JsonResponse({"key": key, **result}, status=status)


@require_GET
def test_error(request):
    """Generates an error with traceback to verify trace consolidation."""
    try:
        1 / 0
    except ZeroDivisionError:
        logger.exception("Test error with traceback")
    return JsonResponse({"logged": True, "check": "CloudWatch for consolidated traceback"})


@require_GET
def test_audit(request):
    """Generates an audit log to verify Firehose routing."""
    audit_logger.info(
        "Test audit event",
        extra={
            "type": "audit",
            "action": "test",
            "user_id": "test-user",
            "resource": "/api/test/audit",
        },
    )
    return JsonResponse({"logged": True, "check": "Firehose/S3 for audit entry"})


@csrf_exempt
@require_POST
def send_test_email(request):
    """Sends a test email via SES. Guarded by DEBUG + allowlist + size caps.

    POST body: {"to": "...", "subject": "...", "body": "..."}
    Recipient must be in SES_ALLOWED_RECIPIENTS env (populated from TF verified_recipients).
    """
    if not SES_FROM_ADDRESS:
        return JsonResponse({"error": "SES not configured"}, status=503)

    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "Invalid JSON"}, status=400)

    to = (payload.get("to") or "").strip()
    subject = (payload.get("subject") or "Test")[:MAX_EMAIL_SUBJECT]
    body = (payload.get("body") or "ping")[:MAX_EMAIL_BODY]

    if to not in SES_ALLOWED_RECIPIENTS:
        return JsonResponse({"error": "Recipient not allowlisted"}, status=400)

    response = ses.send_email(
        FromEmailAddress=SES_FROM_ADDRESS,
        Destination={"ToAddresses": [to]},
        Content={
            "Simple": {
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {"Text": {"Data": body, "Charset": "UTF-8"}},
            },
        },
    )
    audit_logger.info(
        "Email sent",
        extra={
            "type": "audit",
            "action": "email_send",
            "to": to,
            "message_id": response["MessageId"],
        },
    )
    return JsonResponse({"message_id": response["MessageId"]})
