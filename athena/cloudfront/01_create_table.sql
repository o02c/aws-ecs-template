-- ----------------------------------------------------------------------------
-- CloudFront standard logging v2 (Hive-partitioned) — Athena table
-- ----------------------------------------------------------------------------
-- Backs the partitioned layout produced by terraform/project/modules/cdn/
-- cloudwatch_log_delivery.tf:
--
--   s3://<bucket>/cloudfront/distributionid=<id>/year=YYYY/month=MM/day=DD/hour=HH/
--
-- Partition projection means no `MSCK REPAIR TABLE` and no Glue crawler — Athena
-- materializes partitions on the fly when a WHERE clause pins the partition
-- columns. `distributionid` uses `injected` projection: every query MUST include
-- e.g. `WHERE distributionid = 'EXXXXXXXXXXXXX'`. Use 02_sample_queries.sql for
-- common patterns.
--
-- Placeholders to replace before running (or feed via ./scripts/athena-query.sh,
-- which substitutes them from terraform outputs):
--   ${database}        — Glue database (output: athena_database_name)
--   ${bucket}          — access-log bucket (output: bucket_id from logging)
--   ${year_start}      — earliest year that may appear in logs (e.g. 2026)
--   ${year_end}        — upper bound for projection range (e.g. 2030)
-- ----------------------------------------------------------------------------

CREATE EXTERNAL TABLE IF NOT EXISTS ${database}.cloudfront_logs (
  `date`                          DATE,
  `time`                          STRING,
  `x_edge_location`               STRING,
  `sc_bytes`                      BIGINT,
  `c_ip`                          STRING,
  `cs_method`                     STRING,
  `cs_host`                       STRING,
  `cs_uri_stem`                   STRING,
  `sc_status`                     INT,
  `cs_referrer`                   STRING,
  `cs_user_agent`                 STRING,
  `cs_uri_query`                  STRING,
  `cs_cookie`                     STRING,
  `x_edge_result_type`            STRING,
  `x_edge_request_id`             STRING,
  `x_host_header`                 STRING,
  `cs_protocol`                   STRING,
  `cs_bytes`                      BIGINT,
  `time_taken`                    FLOAT,
  `x_forwarded_for`               STRING,
  `ssl_protocol`                  STRING,
  `ssl_cipher`                    STRING,
  `x_edge_response_result_type`   STRING,
  `cs_protocol_version`           STRING,
  `fle_status`                    STRING,
  `fle_encrypted_fields`          INT,
  `c_port`                        INT,
  `time_to_first_byte`            FLOAT,
  `x_edge_detailed_result_type`   STRING,
  `sc_content_type`               STRING,
  `sc_content_len`                BIGINT,
  `sc_range_start`                BIGINT,
  `sc_range_end`                  BIGINT
)
PARTITIONED BY (
  `distributionid` STRING,
  `year`           INT,
  `month`          INT,
  `day`            INT,
  `hour`           INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 's3://${bucket}/cloudfront/'
TBLPROPERTIES (
  'skip.header.line.count'         = '2',
  'projection.enabled'             = 'true',
  'projection.distributionid.type' = 'injected',
  'projection.year.type'           = 'integer',
  'projection.year.range'          = '${year_start},${year_end}',
  'projection.month.type'          = 'integer',
  'projection.month.range'         = '1,12',
  'projection.month.digits'        = '2',
  'projection.day.type'            = 'integer',
  'projection.day.range'           = '1,31',
  'projection.day.digits'          = '2',
  'projection.hour.type'           = 'integer',
  'projection.hour.range'          = '0,23',
  'projection.hour.digits'         = '2',
  'storage.location.template'      = 's3://${bucket}/cloudfront/distributionid=${distributionid}/year=${year}/month=${month}/day=${day}/hour=${hour}/'
);
