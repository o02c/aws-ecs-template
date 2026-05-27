-- ----------------------------------------------------------------------------
-- Audit-log sample queries
-- ----------------------------------------------------------------------------

-- Q1: All audit events for a single day.
SELECT
  "timestamp",
  user_id,
  action,
  resource,
  detail
FROM ${database}.audit_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 24
ORDER BY "timestamp" DESC
LIMIT 100;


-- Q2: Auth-related events (LOGIN / LOGOUT / failed attempts) for a day.
SELECT
  "timestamp",
  user_id,
  action,
  detail
FROM ${database}.audit_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 24
  AND action IN ('LOGIN', 'LOGOUT', 'LOGIN_FAILED')
ORDER BY "timestamp" DESC;


-- Q3: Per-user activity count over a day.
SELECT
  user_id,
  COUNT(*) AS events
FROM ${database}.audit_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 24
  AND user_id IS NOT NULL
GROUP BY user_id
ORDER BY events DESC
LIMIT 50;


-- Q4: Action distribution over a day.
SELECT
  action,
  COUNT(*) AS events
FROM ${database}.audit_logs
WHERE year  = 2026
  AND month = 5
  AND day   = 24
GROUP BY action
ORDER BY events DESC;
