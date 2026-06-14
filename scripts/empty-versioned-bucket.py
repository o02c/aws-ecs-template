#!/usr/bin/env python3
"""Delete all object versions and delete markers from an S3 bucket.

If the bucket has S3 Object Lock enabled (e.g. the front-end assets buckets,
GOVERNANCE mode), delete-objects is sent with --bypass-governance-retention so
locked versions can be removed during teardown. Requires the caller to hold
s3:BypassGovernanceRetention. COMPLIANCE-mode locks cannot be bypassed by anyone
and will (correctly) still fail until their retention expires.
"""
import json
import subprocess
import sys
import tempfile
import os

bucket = sys.argv[1]

# Detect Object Lock once up front; only then pay the bypass flag.
object_lock_enabled = (
    subprocess.run(
        ["aws", "s3api", "get-object-lock-configuration", "--bucket", bucket],
        capture_output=True,
    ).returncode
    == 0
)

key_marker = ""
version_id_marker = ""

while True:
    cmd = ["aws", "s3api", "list-object-versions", "--bucket", bucket, "--output", "json"]
    if key_marker:
        cmd += ["--key-marker", key_marker, "--version-id-marker", version_id_marker]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(0)

    data = json.loads(result.stdout)
    objects = [{"Key": v["Key"], "VersionId": v["VersionId"]} for v in data.get("Versions", [])]
    objects += [{"Key": m["Key"], "VersionId": m["VersionId"]} for m in data.get("DeleteMarkers", [])]

    if objects:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump({"Objects": objects, "Quiet": True}, f)
            tmp = f.name

        delete_cmd = ["aws", "s3api", "delete-objects", "--bucket", bucket, "--delete", f"file://{tmp}"]
        if object_lock_enabled:
            delete_cmd.append("--bypass-governance-retention")

        subprocess.run(delete_cmd, capture_output=True)
        os.unlink(tmp)

    if not data.get("IsTruncated"):
        break

    key_marker = data.get("NextKeyMarker", "")
    version_id_marker = data.get("NextVersionIdMarker", "")
