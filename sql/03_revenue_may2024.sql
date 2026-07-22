-- 03_revenue_may2024.sql
-- Q3a: net revenue per store for May-2024-created, currently-completed orders.
-- Q3b: per store, the single category that drove the most of that revenue.
--
-- Filters (per assignment wording, fact #6):
--   - order's CURRENT status (from 01_current_orders.sql, already normalized) = 'completed'
--   - order's CREATE-event month (create_month from 01_current_orders.sql) = May 2024
--     (NOT latest event month -- see fact #5)
-- net = quantity * unit_price - discount_amount, using cleaned line items from 02.
--
-- Inactive products (fact #8): is_active=false line items are NOT excluded --
-- assignment only asks to filter by order status + month; product active/inactive
-- is a separate, unrelated attribute and excluding it would be an unrequested
-- interpretation. These contribute 50 line items / $3,185.94 (verified via
-- is_active = false as a boolean filter, which correctly excludes the orphan
-- P999 row too, since it has no is_active value at all) to the May 2024
-- completed total. If the intent was to exclude discontinued products from a
-- forward-looking revenue report, that's a follow-up question for
-- stakeholders, not a silent default here.

-- scoped_may2024_completed is a CTE, repeated verbatim at the top of the Q3a
-- and Q3b statements below (no CREATE VIEW / persistent object -- plain
-- read-only SQL, no state left behind after running this file).
-- Q3a: net revenue per store
WITH parsed_events AS (
    -- reuse of 01_current_orders.sql logic; inlined here only because this is
    -- a single-file deliverable per file -- do not re-derive "latest event"
    -- logic anywhere else, always go through this CTE (or the 01 query directly).
    SELECT
        order_id, store_id, event_seq, op,
        TRIM(LOWER(order_status)) AS status_norm,
        COALESCE(
            TRY_STRPTIME(event_ts, '%Y-%m-%d %H:%M:%S'),
            TRY_STRPTIME(event_ts, '%m/%d/%Y %H:%M')
        ) AS event_ts_parsed
    FROM order_events
),
latest_event AS (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY event_seq DESC) AS rn
        FROM parsed_events
    ) t WHERE rn = 1
),
create_event AS (
    SELECT order_id, event_ts_parsed AS create_ts
    FROM parsed_events WHERE op = 'c'
),
current_orders AS (
    SELECT
        le.order_id,
        le.store_id,
        -- deleted rows ALWAYS resolve to 'deleted' -- see 01_current_orders.sql
        -- for why the raw order_status on the delete row cannot be trusted.
        CASE WHEN le.op = 'd' THEN 'deleted' ELSE le.status_norm END AS current_status,
        DATE_TRUNC('month', ce.create_ts) AS create_month
    FROM latest_event le
    LEFT JOIN create_event ce USING (order_id)
),
clean_items AS (
    -- reuse of 02_clean_order_items.sql (dedup + $ strip + discount coalesce);
    -- inlined for the same single-file-deliverable reason as above.
    SELECT
        oi.order_id, oi.product_id,
        oi.quantity,
        CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE) AS unit_price,
        COALESCE(oi.discount_amount, 0) AS discount_amount,
        COALESCE(p.category, 'Uncategorized') AS category,
        ROW_NUMBER() OVER (
            PARTITION BY oi.order_id, oi.product_id, oi.quantity,
                         CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE),
                         COALESCE(oi.discount_amount, 0)
            ORDER BY oi.order_item_id
        ) AS dup_rn
    FROM order_items oi
    LEFT JOIN products p ON p.product_id = oi.product_id
),
scoped_may2024_completed AS (
    SELECT
        co.store_id,
        ci.category,
        (ci.quantity * ci.unit_price - ci.discount_amount) AS net_revenue
    FROM clean_items ci
    JOIN current_orders co ON co.order_id = ci.order_id
    WHERE ci.dup_rn = 1
      AND co.current_status = 'completed'
      AND co.create_month = DATE '2024-05-01'
)
SELECT store_id, SUM(net_revenue) AS net_revenue_may2024
FROM scoped_may2024_completed
GROUP BY store_id
ORDER BY store_id;

-- Q3b: top category per store by completed net revenue (same CTE chain,
-- repeated verbatim -- see note above on why there's no shared view).
-- RANK() partitioned BY store_id (not a global top-N) -- exactly one row per
-- store expected (4 stores total). Ties (if any) would produce >1 row per
-- store; none observed in this data.
WITH parsed_events AS (
    SELECT
        order_id, store_id, event_seq, op,
        TRIM(LOWER(order_status)) AS status_norm,
        COALESCE(
            TRY_STRPTIME(event_ts, '%Y-%m-%d %H:%M:%S'),
            TRY_STRPTIME(event_ts, '%m/%d/%Y %H:%M')
        ) AS event_ts_parsed
    FROM order_events
),
latest_event AS (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY event_seq DESC) AS rn
        FROM parsed_events
    ) t WHERE rn = 1
),
create_event AS (
    SELECT order_id, event_ts_parsed AS create_ts
    FROM parsed_events WHERE op = 'c'
),
current_orders AS (
    SELECT
        le.order_id,
        le.store_id,
        CASE WHEN le.op = 'd' THEN 'deleted' ELSE le.status_norm END AS current_status,
        DATE_TRUNC('month', ce.create_ts) AS create_month
    FROM latest_event le
    LEFT JOIN create_event ce USING (order_id)
),
clean_items AS (
    SELECT
        oi.order_id, oi.product_id,
        oi.quantity,
        CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE) AS unit_price,
        COALESCE(oi.discount_amount, 0) AS discount_amount,
        COALESCE(p.category, 'Uncategorized') AS category,
        ROW_NUMBER() OVER (
            PARTITION BY oi.order_id, oi.product_id, oi.quantity,
                         CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE),
                         COALESCE(oi.discount_amount, 0)
            ORDER BY oi.order_item_id
        ) AS dup_rn
    FROM order_items oi
    LEFT JOIN products p ON p.product_id = oi.product_id
),
scoped_may2024_completed AS (
    SELECT
        co.store_id,
        ci.category,
        (ci.quantity * ci.unit_price - ci.discount_amount) AS net_revenue
    FROM clean_items ci
    JOIN current_orders co ON co.order_id = ci.order_id
    WHERE ci.dup_rn = 1
      AND co.current_status = 'completed'
      AND co.create_month = DATE '2024-05-01'
),
store_category AS (
    SELECT store_id, category, SUM(net_revenue) AS category_revenue
    FROM scoped_may2024_completed
    GROUP BY store_id, category
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY store_id ORDER BY category_revenue DESC) AS rnk
    FROM store_category
)
SELECT store_id, category, category_revenue
FROM ranked
WHERE rnk = 1
ORDER BY store_id;
