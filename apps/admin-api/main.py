import base64
import os
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

import boto3
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.hazmat.primitives.asymmetric.padding import PKCS1v15
from cryptography.hazmat.primitives.hashes import SHA1
import re

from fastapi import FastAPI, HTTPException, UploadFile

# Configuration
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN", "")
CLOUDFRONT_KEY_PAIR_ID = os.environ.get("CLOUDFRONT_KEY_PAIR_ID", "")
CLOUDFRONT_SIGNING_KEY_SECRET_ARN = os.environ.get(
    "CLOUDFRONT_SIGNING_KEY_SECRET_ARN", ""
)
SIGNED_URL_TTL_SECONDS = int(os.environ.get("SIGNED_URL_TTL_SECONDS", "86400"))
S3_FILES_PREFIX = os.environ.get("S3_FILES_PREFIX", "files")

_signing_key = None
s3 = boto3.client("s3")


def _load_signing_key():
    global _signing_key
    if not CLOUDFRONT_SIGNING_KEY_SECRET_ARN:
        return
    sm = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=CLOUDFRONT_SIGNING_KEY_SECRET_ARN)
    _signing_key = load_pem_private_key(resp["SecretString"].encode(), password=None)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_signing_key()
    yield


app = FastAPI(title="Admin API", lifespan=lifespan)


# --------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------


MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10 MB
EXT_PATTERN = re.compile(r"^\.[a-zA-Z0-9]{1,10}$")


def _build_cloudfront_signed_url(resource_path: str, ttl_seconds: int) -> str:
    if _signing_key is None:
        raise HTTPException(status_code=503, detail="Signing key not configured")
    expires = int((datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)).timestamp())
    policy = (
        '{"Statement":[{"Resource":"'
        + f"https://{CLOUDFRONT_DOMAIN}/{resource_path}"
        + '","Condition":{"DateLessThan":{"AWS:EpochTime":'
        + str(expires)
        + "}}}]}"
    )
    signature = _signing_key.sign(policy.encode(), PKCS1v15(), SHA1())
    encoded_signature = (
        base64.b64encode(signature)
        .decode()
        .replace("+", "-")
        .replace("=", "_")
        .replace("/", "~")
    )

    return (
        f"https://{CLOUDFRONT_DOMAIN}/{resource_path}"
        f"?Policy={base64.b64encode(policy.encode()).decode().replace('+', '-').replace('=', '_').replace('/', '~')}"
        f"&Signature={encoded_signature}"
        f"&Key-Pair-Id={CLOUDFRONT_KEY_PAIR_ID}"
    )


def _upload_to_s3(file_id: str, filename: str, content: bytes) -> str:
    ext = os.path.splitext(filename)[1] if filename else ""
    s3_key = f"{S3_FILES_PREFIX}/{file_id}{ext}"
    s3.put_object(
        Bucket=S3_BUCKET_NAME,
        Key=s3_key,
        Body=content,
        ContentDisposition=f'attachment; filename="{filename}"',
    )
    return s3_key


# --------------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------------


@app.get("/health")
def health():
    return {"status": "ok", "service": "admin-api"}


@app.get("/api/dashboard")
def dashboard():
    return {"total_users": 42, "active_sessions": 7}


@app.get("/api/settings")
def settings():
    return {"maintenance_mode": False, "log_level": "info"}


@app.post("/api/files/upload")
async def upload_file(file: UploadFile):
    file_id = uuid.uuid4().hex
    chunks = []
    total = 0
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_UPLOAD_SIZE:
            raise HTTPException(status_code=413, detail="File too large (max 10MB)")
        chunks.append(chunk)
    content = b"".join(chunks)
    s3_key = _upload_to_s3(file_id, file.filename or "upload", content)
    signed_url = _build_cloudfront_signed_url(s3_key, SIGNED_URL_TTL_SECONDS)
    return {
        "file_id": file_id,
        "s3_key": s3_key,
        "signed_url": signed_url,
        "expires_in_seconds": SIGNED_URL_TTL_SECONDS,
    }


@app.get("/api/files/{file_id}/url")
def get_file_url(file_id: str, ext: str = ""):
    if ext and not EXT_PATTERN.match(ext):
        raise HTTPException(status_code=400, detail="Invalid file extension")
    s3_key = f"{S3_FILES_PREFIX}/{file_id}{ext}"
    signed_url = _build_cloudfront_signed_url(s3_key, SIGNED_URL_TTL_SECONDS)
    return {
        "file_id": file_id,
        "signed_url": signed_url,
        "expires_in_seconds": SIGNED_URL_TTL_SECONDS,
    }
