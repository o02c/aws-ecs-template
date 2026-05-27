-- ----------------------------------------------------------------------------
-- ECS app-container logs (FireLens → Firehose → S3) — Athena table
-- ----------------------------------------------------------------------------
-- Backs the partitioned layout produced by the `ecs-logs-app` Firehose stream
-- (terraform/project/modules/app/firehose.tf):
--
--   s3://<bucket>/ecs-logs-app/year=YYYY/month=MM/day=DD/
--
-- Records are GZIP-compressed JSONL. The app container's stdout/stderr is
-- JSON-parsed by Fluent Bit's builtin `json` parser (FILTER in
-- fluent-bit-extra.conf, Match app-firelens-*), so the JsonFormatter fields
-- (timestamp/level/logger/message/type/user_id/action/resource/detail/
-- traceback) are flattened to top-level. FireLens injects source / container_*
-- / ecs_* metadata.
--
-- Audit records (type=audit) are routed to a separate audit Firehose stream
-- via rewrite_tag, so this table only sees non-audit traffic.
--
-- Placeholders (substituted by ./scripts/athena-query.sh):
--   ${database}      — Glue database (athena_database_name output)
--   ${bucket}        — access-log bucket (access_log_bucket_id output)
--   ${year_start}    — earliest year for projection (default 2026)
--   ${year_end}      — upper bound for projection range (default 2030)
-- ----------------------------------------------------------------------------

CREATE EXTERNAL TABLE IF NOT EXISTS ${database}.ecs_app_logs (
  -- app-container JSON fields (Python JsonFormatter)
  `timestamp`           STRING,
  `level`               STRING,
  `logger`              STRING,
  `message`             STRING,
  `type`                STRING,
  `user_id`             STRING,
  `action`              STRING,
  `resource`            STRING,
  `detail`              STRING,
  `traceback`           STRING,
  -- raw line for unparsed records (e.g. non-JSON output before JsonFormatter kicks in)
  `log`                 STRING,
  -- FireLens metadata
  `source`              STRING,
  `container_id`        STRING,
  `container_name`      STRING,
  `ecs_cluster`         STRING,
  `ecs_task_arn`        STRING,
  `ecs_task_definition` STRING
)
PARTITIONED BY (
  `year`  INT,
  `month` INT,
  `day`   INT
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
STORED AS INPUTFORMAT  'org.apache.hadoop.mapred.TextInputFormat'
          OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://${bucket}/ecs-logs-app/'
TBLPROPERTIES (
  'projection.enabled'        = 'true',
  'projection.year.type'      = 'integer',
  'projection.year.range'     = '${year_start},${year_end}',
  'projection.month.type'     = 'integer',
  'projection.month.range'    = '1,12',
  'projection.month.digits'   = '2',
  'projection.day.type'       = 'integer',
  'projection.day.range'      = '1,31',
  'projection.day.digits'     = '2',
  'storage.location.template' = 's3://${bucket}/ecs-logs-app/year=${year}/month=${month}/day=${day}/'
);
