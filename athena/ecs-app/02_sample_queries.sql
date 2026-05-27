-- ----------------------------------------------------------------------------
-- ECS app-log sample queries
-- ----------------------------------------------------------------------------
-- All queries SHOULD filter on year/month/day partitions to enable projection
-- pruning. The scan cost goes from "every gzipped object" to "the matched
-- day's prefix only".
-- ----------------------------------------------------------------------------

-- Q1: Errors for a single day.
SELECT
  "timestamp",
  level,
  logger,
  ecs_task_definition,
  message
FROM ${database}.ecs_app_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
  AND level = 'ERROR'
ORDER BY "timestamp" DESC
LIMIT 50;


-- Q2: Volume by level for a single day.
SELECT
  level,
  COUNT(*) AS records
FROM ${database}.ecs_app_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
GROUP BY level
ORDER BY records DESC;


-- Q3: Recent tracebacks.
SELECT
  "timestamp",
  ecs_task_definition,
  logger,
  message,
  traceback
FROM ${database}.ecs_app_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
  AND traceback IS NOT NULL
ORDER BY "timestamp" DESC
LIMIT 20;


-- Q4: Per-service log volume (user-api vs admin-api).
SELECT
  ecs_task_definition,
  level,
  COUNT(*) AS records
FROM ${database}.ecs_app_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 27
GROUP BY ecs_task_definition, level
ORDER BY ecs_task_definition, records DESC;
