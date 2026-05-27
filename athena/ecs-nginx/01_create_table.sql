-- ----------------------------------------------------------------------------
-- ECS nginx-sidecar logs (FireLens → Firehose → S3) — Athena table
-- ----------------------------------------------------------------------------
-- Backs the partitioned layout produced by the `ecs-logs-nginx` Firehose
-- stream (terraform/project/modules/app/firehose.tf):
--
--   s3://<bucket>/ecs-logs-nginx/year=YYYY/month=MM/day=DD/
--
-- Records are GZIP-compressed JSONL. nginx is configured with
-- `log_format json_combined` (apps/nginx/nginx.conf), and Fluent Bit's
-- nginx_json_app parser (FILTER Match nginx-firelens-*) flattens those fields
-- (time / remote_addr / method / uri / status / bytes_sent / referer /
-- user_agent / x_forwarded_for) into top-level columns alongside FireLens
-- metadata (source / container_* / ecs_*).
--
-- Placeholders (substituted by ./scripts/athena-query.sh):
--   ${database}      — Glue database (athena_database_name output)
--   ${bucket}        — access-log bucket (access_log_bucket_id output)
--   ${year_start}    — earliest year for projection (default 2026)
--   ${year_end}      — upper bound for projection range (default 2030)
-- ----------------------------------------------------------------------------

CREATE EXTERNAL TABLE IF NOT EXISTS ${database}.ecs_nginx_logs (
  -- nginx JSON access-log fields (log_format json_combined)
  `time`                STRING,
  `remote_addr`         STRING,
  `method`              STRING,
  `uri`                 STRING,
  `status`              INT,
  `bytes_sent`          BIGINT,
  `referer`             STRING,
  `user_agent`          STRING,
  `x_forwarded_for`     STRING,
  -- raw line for unparsed records (e.g. /docker-entrypoint.d startup chatter)
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
LOCATION 's3://${bucket}/ecs-logs-nginx/'
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
  'storage.location.template' = 's3://${bucket}/ecs-logs-nginx/year=${year}/month=${month}/day=${day}/'
);
