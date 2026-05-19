"""
db_sql Lambda handler.

Event schema (exactly one of `sql` / `s3_key` required):
  {
    "sql":    "SELECT ... WHERE id = :id",   # inline SQL
    "s3_key": "ddl/2026-05-19-patch.sql",    # S3 file (prefix must match SQL_PREFIX env)
    "params": [123, "abc"],                  # optional positional params (pyformat / qmark)
    "fetch":  true                           # optional: return rows (default false)
  }

Env vars (set by terraform):
  DB_HOST, DB_PORT, DB_NAME, DB_USER
  AUTH_MODE   = "secret" (DDL: Secrets Manager) | "iam" (DML: RDS IAM auth token)
  SECRET_ARN  = master user secret ARN (AUTH_MODE=secret only)
  SQL_BUCKET  = S3 bucket name for sql files
  SQL_PREFIX  = "ddl/" or "dml/"  (s3_key must start with this)
  AWS_REGION  = automatically provided by Lambda runtime
"""

import json
import os
import ssl

import boto3
import pg8000.dbapi

DB_HOST = os.environ["DB_HOST"]
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
AUTH_MODE = os.environ["AUTH_MODE"]
SECRET_ARN = os.environ.get("SECRET_ARN", "")
SQL_BUCKET = os.environ["SQL_BUCKET"]
SQL_PREFIX = os.environ["SQL_PREFIX"]
AWS_REGION = os.environ["AWS_REGION"]

_s3 = boto3.client("s3")
_secrets = boto3.client("secretsmanager")
_rds = boto3.client("rds")


def _get_password() -> str:
    if AUTH_MODE == "secret":
        resp = _secrets.get_secret_value(SecretId=SECRET_ARN)
        return json.loads(resp["SecretString"])["password"]
    if AUTH_MODE == "iam":
        return _rds.generate_db_auth_token(
            DBHostname=DB_HOST,
            Port=DB_PORT,
            DBUsername=DB_USER,
            Region=AWS_REGION,
        )
    raise ValueError(f"unknown AUTH_MODE: {AUTH_MODE}")


def _resolve_sql(event: dict) -> str:
    inline = event.get("sql")
    s3_key = event.get("s3_key")
    if bool(inline) == bool(s3_key):
        raise ValueError("exactly one of 'sql' or 's3_key' must be provided")
    if s3_key:
        if not s3_key.startswith(SQL_PREFIX):
            raise ValueError(f"s3_key must start with '{SQL_PREFIX}' (got '{s3_key}')")
        obj = _s3.get_object(Bucket=SQL_BUCKET, Key=s3_key)
        return obj["Body"].read().decode("utf-8")
    return str(inline)


def handler(event, _context):
    sql = _resolve_sql(event)
    params = event.get("params")
    fetch = bool(event.get("fetch", False))

    conn = pg8000.dbapi.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=_get_password(),
        ssl_context=ssl.create_default_context(),
    )
    try:
        cur = conn.cursor()
        cur.execute(sql, params) if params is not None else cur.execute(sql)
        result = {"rowcount": cur.rowcount}
        if fetch and cur.description is not None:
            cols = [c[0] for c in cur.description]
            rows = cur.fetchall()
            result["columns"] = cols
            result["rows"] = [[_jsonable(v) for v in r] for r in rows]
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _jsonable(v):
    # pg8000 returns datetime/Decimal/etc. — stringify anything boto3 won't serialize.
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    return str(v)
