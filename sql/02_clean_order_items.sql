-- 02_clean_order_items.sql
-- Cleans data/order_items.csv. Reused by 03_revenue_may2024.sql.
--
-- Issues found and handling (see also data_quality_issues.md):
--
-- 1. unit_price: 5 rows have a literal '$' prefix (e.g. '$34.41') stored as text.
--    Stripped '$' before CAST to a numeric type.
--
-- 2. discount_amount is NULL in 381/530 rows. COALESCE'd to 0 -- NULL must not
--    propagate through net-revenue arithmetic (NULL * x = NULL would silently
--    drop these rows from any SUM).
--
-- 3. Orphan product_id 'P999' (1 row, I-number unknown til joined) has no match
--    in products.csv. DECISION: keep the line item (revenue is real, order total
--    should not silently shrink) but LEFT JOIN to products so category comes back
--    NULL, then COALESCE category -> 'Uncategorized' and flag via is_orphan_product.
--    Alternative (excluding it) would understate revenue with no stated business
--    reason to drop a paid line item just because master data is incomplete --
--    flagging was judged the safer default. Reviewer can filter is_orphan_product
--    if the other interpretation is preferred.
--
-- 4. Known bad rows (order O1019):
--      I5041 quantity=1, unit_price=0        -> net = 0, not excluded (quantity/price
--        are both individually "valid" values, zero-price could be a legitimate promo
--        item; flagged via has_zero_price so it's visible, not silently dropped).
--      I5042 quantity=0                       -> net = 0 regardless of price; flagged
--        via has_zero_qty. A zero-quantity line item contributes nothing to revenue
--        by construction, so it is harmless to keep, but it's still a data-entry bug
--        worth surfacing.
--      I5043 unit_price=-5.0, quantity=3      -> net = -15.0. Negative unit_price is
--        not a plausible price; DECISION: flag via has_negative_price but still
--        include in net revenue as computed (do not silently clip to 0) because
--        we don't know if this represents a return/adjustment vs. a typo, and
--        clipping would be its own silent assumption. Flag lets analyst decide.
--
-- 5. Duplicate line items: (order_id, product_id, quantity, unit_price,
--    discount_amount) identical across two distinct order_item_id values for
--    (O1094, P008) [I5246/I5249] and (O1142, P026) [I5357/I5358]. These look like
--    true duplicate entries (not two genuinely separate line items that happen to
--    share qty/price), since order_item_id is otherwise the grain key and nothing
--    else differs. DECISION: dedupe, keeping the lowest order_item_id, flagged via
--    a comment -- NOT silently dropped without a note. Other repeated
--    (order_id, product_id) pairs with differing qty/price/discount (e.g. O1030/P018,
--    O1082/P024, etc.) are treated as legitimate separate line items and kept as-is.

WITH cleaned AS (
    SELECT
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        oi.quantity,
        CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE) AS unit_price,
        COALESCE(oi.discount_amount, 0) AS discount_amount,
        (oi.quantity = 0) AS has_zero_qty,
        (CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE) = 0) AS has_zero_price,
        (CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE) < 0) AS has_negative_price,
        (p.product_id IS NULL) AS is_orphan_product,
        COALESCE(p.category, 'Uncategorized') AS category,
        p.is_active,
        ROW_NUMBER() OVER (
            PARTITION BY oi.order_id, oi.product_id, oi.quantity,
                         CAST(REPLACE(oi.unit_price, '$', '') AS DOUBLE),
                         COALESCE(oi.discount_amount, 0)
            ORDER BY oi.order_item_id
        ) AS dup_rn
    FROM order_items oi
    LEFT JOIN products p ON p.product_id = oi.product_id
)
SELECT
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    discount_amount,
    category,
    is_active,
    is_orphan_product,
    has_zero_qty,
    has_zero_price,
    has_negative_price,
    (quantity * unit_price - discount_amount) AS net_revenue
FROM cleaned
WHERE dup_rn = 1  -- drops the 2 exact-duplicate rows (I5249, I5358), keeps first-seen
ORDER BY order_id, order_item_id;
