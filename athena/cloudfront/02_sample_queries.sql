-- ----------------------------------------------------------------------------
-- CloudFront access-log sample queries
-- ----------------------------------------------------------------------------
-- Every query MUST filter on `distributionid` (the partition column uses
-- `projection.type = injected`), and SHOULD filter on year/month/day/hour to
-- reduce scan volume. Replace ${distributionid} below or feed it via the
-- helper script:
--
--   just athena-query "$(cat athena/cloudfront/02_sample_queries.sql | sed -n '/-- Q1/,/-- Q2/p')"
--
-- The helper substitutes ${database}, ${bucket} from terraform outputs; you
-- still pass the distribution ID and date range in the query itself.
-- ----------------------------------------------------------------------------

-- Q1: Smoke test — verify partition projection works end-to-end.
-- Returns 5 sample rows from a specific distribution / day.
SELECT
  "date",
  "time",
  cs_method,
  cs_uri_stem,
  sc_status,
  time_taken
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
LIMIT 5;


-- Q2: Status-code distribution for a single day.
SELECT
  sc_status,
  COUNT(*) AS hits
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
GROUP BY sc_status
ORDER BY hits DESC;


-- Q3: Top 20 5xx-error URIs over the last day.
SELECT
  cs_uri_stem,
  sc_status,
  COUNT(*) AS errors
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
  AND sc_status >= 500
GROUP BY cs_uri_stem, sc_status
ORDER BY errors DESC
LIMIT 20;


-- Q4: Cache hit/miss ratio per hour for a given day.
SELECT
  hour,
  x_edge_result_type,
  COUNT(*) AS hits
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
GROUP BY hour, x_edge_result_type
ORDER BY hour, hits DESC;


-- Q5: Slowest endpoints (p95 time_taken) for a single hour.
SELECT
  cs_uri_stem,
  COUNT(*)                                              AS requests,
  APPROX_PERCENTILE(time_taken, 0.95)                   AS p95_seconds,
  APPROX_PERCENTILE(time_taken, 0.99)                   AS p99_seconds
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
  AND hour  = 12
GROUP BY cs_uri_stem
HAVING COUNT(*) > 50
ORDER BY p95_seconds DESC
LIMIT 20;


-- Q6: Top 20 client IPs (basic abuse / hotspot finder) for one day.
-- x_forwarded_for is the original viewer when behind a proxy; c_ip is the
-- direct viewer (often equal). Both are present in CloudFront logs.
SELECT
  c_ip,
  COUNT(*) AS requests,
  COUNT(DISTINCT cs_uri_stem) AS distinct_paths
FROM ${database}.cloudfront_logs
WHERE distributionid = '${distributionid}'
  AND year  = 2026
  AND month = 5
  AND day   = 15
GROUP BY c_ip
ORDER BY requests DESC
LIMIT 20;
