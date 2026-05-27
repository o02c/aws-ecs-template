-- ----------------------------------------------------------------------------
-- ecs_app_logs_jst — view that adds a JST companion column to ecs_app_logs
-- ----------------------------------------------------------------------------
-- The base table stores `timestamp` as ISO 8601 with explicit UTC offset
-- (+00:00). UTC stays the on-disk source of truth; this view exposes a
-- `timestamp_jst` companion for dashboards and ad-hoc queries.
--
-- Use this view for presentation. Keep partition pruning on year/month/day —
-- they remain bound to UTC, so a JST-day window can straddle two UTC days.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW ${database}.ecs_app_logs_jst AS
SELECT
  date_format(
    from_iso8601_timestamp("timestamp") AT TIME ZONE 'Asia/Tokyo',
    '%Y-%m-%dT%H:%i:%s.%f+09:00'
  ) AS timestamp_jst,
  *
FROM ${database}.ecs_app_logs;
