#!/usr/bin/env bash
# Run an Athena query against the logging workgroup.
#
# Substitutes the following placeholders from terraform outputs:
#   ${database}, ${bucket}, ${workgroup}, ${year_start}, ${year_end}
# Pass any other ${...} placeholders (e.g. ${distributionid}) via -e KEY=VALUE
# or as already-set environment variables — those flow through envsubst too.
#
# Usage:
#   scripts/athena-query.sh <path-to-sql>
#   scripts/athena-query.sh -e distributionid=EXXXXX athena/cloudfront/01_create_table.sql
#   scripts/athena-query.sh --print athena/cloudfront/01_create_table.sql  # dry-run
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/project/environments/${ENVIRONMENT:-dev}"

PRINT_ONLY=0
declare -a EXTRA_VARS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--var)
      EXTRA_VARS+=("$2"); shift 2 ;;
    --print)
      PRINT_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      SQL_FILE="$1"; shift ;;
  esac
done

if [[ -z "${SQL_FILE:-}" ]]; then
  echo "ERROR: missing SQL file argument" >&2
  exit 2
fi
if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: SQL file not found: $SQL_FILE" >&2
  exit 2
fi

# Pull required values from terraform output (json) so the SQL stays portable.
TF_OUT=$(terraform -chdir="$TF_DIR" output -json)
database=$(printf '%s' "$TF_OUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["athena_database_name"]["value"])')
bucket=$(printf '%s' "$TF_OUT"  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["access_log_bucket_id"]["value"])')
workgroup=$(printf '%s' "$TF_OUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["athena_workgroup_name"]["value"])')

# Sensible defaults for the projection range. Override via -e if needed.
year_start="${year_start:-2026}"
year_end="${year_end:-2030}"
export database bucket workgroup year_start year_end

# Whitelist envsubst to leave unknown ${...} alone (otherwise it would also
# eat e.g. ${distributionid} when we want it to survive into Athena).
WHITELIST='${database} ${bucket} ${workgroup} ${year_start} ${year_end}'
for kv in "${EXTRA_VARS[@]}"; do
  k="${kv%%=*}"; v="${kv#*=}"
  export "$k=$v"
  WHITELIST="${WHITELIST} \${${k}}"
done

RENDERED=$(envsubst "$WHITELIST" < "$SQL_FILE")

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  printf '%s\n' "$RENDERED"
  exit 0
fi

echo "--- Submitting query to workgroup: $workgroup ---"
EXEC_ID=$(aws athena start-query-execution \
  --query-string "$RENDERED" \
  --work-group "$workgroup" \
  --query 'QueryExecutionId' \
  --output text)
echo "QueryExecutionId: $EXEC_ID"

# Poll until terminal state.
while :; do
  STATE=$(aws athena get-query-execution \
    --query-execution-id "$EXEC_ID" \
    --query 'QueryExecution.Status.State' \
    --output text)
  case "$STATE" in
    SUCCEEDED) break ;;
    FAILED|CANCELLED)
      REASON=$(aws athena get-query-execution \
        --query-execution-id "$EXEC_ID" \
        --query 'QueryExecution.Status.StateChangeReason' \
        --output text)
      echo "Query $STATE: $REASON" >&2
      exit 1 ;;
    *) sleep 2 ;;
  esac
done

echo "--- Results ---"
aws athena get-query-results \
  --query-execution-id "$EXEC_ID" \
  --output table \
  --max-items 50
