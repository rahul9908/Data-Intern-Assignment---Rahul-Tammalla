# Stretch: raw → clean → business-ready layers

The three SQL files already implicitly follow this shape; here's how I'd formalize it as dbt-style layers rather than one-off scripts, since a real pipeline needs these fixes to persist and be re-runnable, not re-derived by hand each time.

**Bronze (raw).** `order_events`, `order_items`, `products`, `stores` loaded as-is, untouched — including every one of the messy rows found here (mixed date formats, `$`-prefixed prices, stale statuses on deleted orders). This layer's only job is being an honest copy of the source; no cleaning happens here, so nothing found downstream can ever be "unrecoverable."

**Silver (clean).** One model per bronze source, each owning exactly one category of fix so the fix lives in one place instead of being duplicated (which is what `01_current_orders.sql` and `03_revenue_may2024.sql` currently do, out of necessity as single-file deliverables — this is exactly the duplication a layered model removes):
- `stg_current_orders` — one row per order_id, latest event by `event_seq`, `current_status` normalized (`TRIM(LOWER())`) and unconditionally forced to `'deleted'` when the latest event is a delete, `create_month` derived from the `op='c'` row only.
- `stg_order_items` — `$`-stripped and cast `unit_price`, `discount_amount` coalesced to 0, dedup on business key, orphan `product_id` left-joined with `'Uncategorized'` fallback, and flag columns (`has_zero_price`, `has_negative_price`, `is_orphan_product`) preserved rather than silently dropped, so gold-layer consumers can decide whether to include or exclude them.

**Gold (business-ready).** `fct_order_revenue` — one row per (order, line item), joining `stg_current_orders` to `stg_order_items` to `products`/`stores`, with `net_revenue` pre-computed. Q3a/Q3b become simple aggregations over this one table instead of duplicated CTE chains. A BI tool or analyst queries only this layer and never needs to know about `$` prefixes or delete-status bugs.

**Why this matters here specifically:** the delete-status bug reviewer caught existed because the fix was duplicated in two files and could drift; a silver-layer model with dbt tests (e.g. `assert count(current_status='deleted' and current_status='completed') == 0` per order) would catch that class of bug automatically on every run, not just when a human happens to review it.
