-- 01_current_orders.sql
-- Reconstructs one current-state row per order_id from data/order_events.csv.
--
-- ASSUMPTION (fact #2): event_ts is unreliable (mixed formats: most rows
-- 'YYYY-MM-DD HH:MM:SS', but O1026/O1027/O1028's op='c' row is 'MM/DD/YYYY HH:MM').
-- "Latest event" is determined by MAX(event_seq) per order_id, NOT by event_ts,
-- per the assignment's own description that event_seq increments per order.
--
-- ASSUMPTION (fact #3): 8 of 210 orders have their latest event = delete ('d').
-- These are NOT dropped -- they remain as one row each, with current_status
-- always forced to 'deleted', regardless of whatever order_status happens to
-- be on that delete row. 8 of these 8 delete rows carry a stale order_status
-- of 'completed' left over from before the delete, so this override is
-- unconditional, not just a fallback for blank/null values -- see the CASE
-- expression below for why trusting the raw value would be wrong.
--
-- ASSUMPTION (fact #1): order_status has 8 raw string variants for 4 logical
-- statuses (pending/completed/refunded/voided). Always TRIM(LOWER(...)) before
-- comparing. This normalization is applied once here so every downstream query
-- reuses current_status already normalized -- no re-deriving status logic elsewhere.
--
-- create_ts / create_month: taken from the op='c' row (== event_seq = 1, confirmed
-- always true in this data) per "an order belongs to the month of its create event".
-- Handles the two event_ts formats via TRY_STRPTIME fallback chain.

WITH parsed_events AS (
    SELECT
        order_id,
        store_id,
        customer_id,
        event_seq,
        op,
        TRIM(LOWER(order_status)) AS status_norm,
        COALESCE(
            TRY_STRPTIME(event_ts, '%Y-%m-%d %H:%M:%S'),
            TRY_STRPTIME(event_ts, '%m/%d/%Y %H:%M')
        ) AS event_ts_parsed
    FROM order_events
),
latest_event AS (
    -- one row per order_id: the row with the max event_seq (authoritative ordering)
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY event_seq DESC) AS rn
        FROM parsed_events
    ) t
    WHERE rn = 1
),
create_event AS (
    -- the op='c' row per order (== event_seq = 1); used only for create_ts/create_month
    SELECT
        order_id,
        event_ts_parsed AS create_ts
    FROM parsed_events
    WHERE op = 'c'
)
SELECT
    le.order_id,
    le.store_id,
    le.customer_id,
    le.event_seq        AS latest_event_seq,
    le.op                AS latest_op,
    -- deleted rows ALWAYS resolve to 'deleted' regardless of raw order_status on
    -- that delete row -- 8 of the 210 delete rows carry a stale order_status of
    -- 'completed' (a data-entry artifact of the delete event), and trusting that
    -- raw value would leak deleted orders into completed-order revenue totals.
    CASE
        WHEN le.op = 'd' THEN 'deleted'
        ELSE le.status_norm
    END AS current_status,
    le.event_ts_parsed  AS latest_event_ts,
    ce.create_ts,
    DATE_TRUNC('month', ce.create_ts) AS create_month
FROM latest_event le
LEFT JOIN create_event ce USING (order_id)
ORDER BY le.order_id;
-- Expected: 210 rows (one per order_id), including the 8 'd'-latest orders.
