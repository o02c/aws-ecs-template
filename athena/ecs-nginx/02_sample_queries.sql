-- ----------------------------------------------------------------------------
-- ECS nginx-log sample queries
-- ----------------------------------------------------------------------------

-- Q1: 5xx requests for a single day.
SELECT
  "time",
  remote_addr,
  method,
  uri,
  status,
  bytes_sent,
  user_agent
FROM ${database}.ecs_nginx_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
  AND status >= 500
ORDER BY "time" DESC
LIMIT 20;


-- Q2: Request volume by status class per hour.
SELECT
  date_format(from_iso8601_timestamp("time"), '%H')        AS hour,
  CAST(status / 100 AS INTEGER) * 100                      AS status_class,
  COUNT(*)                                                 AS requests
FROM ${database}.ecs_nginx_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
GROUP BY 1, 2
ORDER BY hour, status_class;


-- Q3: Top 20 slow URIs (need timing in log_format — currently not captured;
-- placeholder query showing how to extend once `request_time` is added).
SELECT
  uri,
  COUNT(*)             AS requests,
  AVG(bytes_sent)      AS avg_bytes,
  MAX(bytes_sent)      AS max_bytes
FROM ${database}.ecs_nginx_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
GROUP BY uri
ORDER BY requests DESC
LIMIT 20;


-- Q4: Top 20 client IPs (basic abuse / hotspot finder) for one day.
SELECT
  remote_addr,
  COUNT(*)                AS requests,
  COUNT(DISTINCT uri)     AS distinct_paths
FROM ${database}.ecs_nginx_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
GROUP BY remote_addr
ORDER BY requests DESC
LIMIT 20;
