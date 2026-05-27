-- ----------------------------------------------------------------------------
-- Audit logs (FireLens rewrite_tag → audit Firehose → S3) — Athena table
-- ----------------------------------------------------------------------------
-- Backs the partitioned layout produced by terraform/project/modules/app/
-- firehose.tf for the `audit` Firehose stream:
--
--   s3://<bucket>/audit/year=YYYY/month=MM/day=DD/
--
-- Records flow here when the application emits a JSON log with `type=audit`
-- (see apps/<svc>/config/logging_formatter.py extras). The rewrite_tag FILTER
-- in fluent-bit-extra.conf removes them from the regular ecs_logs stream.
--
-- audit is retained for compliance (no S3 expiration). Athena-queryable while
-- objects remain in Standard / Standard-IA / Glacier IR (~180 days); older
-- partitions require Glacier restore before query.
--
-- Placeholders (substituted by ./scripts/athena-query.sh):
--   ${database}      — Glue database (athena_database_name output)
--   ${bucket}        — access-log bucket (access_log_bucket_id output)
--   ${year_start}    — earliest year for projection (default 2026)
--   ${year_end}      — upper bound for projection range (default 2030)
-- ----------------------------------------------------------------------------

CREATE EXTERNAL TABLE IF NOT EXISTS ${database}.audit_logs (
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
LOCATION 's3://${bucket}/audit/'
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
  'storage.location.template' = 's3://${bucket}/audit/year=${year}/month=${month}/day=${day}/'
);
