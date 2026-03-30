import logging
import os
import re
import uuid

import boto3
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

logger = logging.getLogger(__name__)
audit_logger = logging.getLogger("audit")

S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN", "")
S3_FILES_PREFIX = os.environ.get("S3_FILES_PREFIX", "files")
MAX_UPLOAD_SIZE = 10 * 1024 * 1024

EXT_PATTERN = re.compile(r"^\.[a-zA-Z0-9]{1,10}$")

s3 = boto3.client("s3")


@require_GET
def health(request):
    return JsonResponse({"status": "ok", "service": "user-api"})


@require_GET
def list_users(request):
    return JsonResponse(
        [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}],
        safe=False,
    )


@require_GET
def get_user(request, user_id):
    return JsonResponse({"id": user_id, "name": f"User-{user_id}"})


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
