# Computed Results (verified via DuckDB)

**Correction (2026-07-22):** the numbers below were recomputed after fixing a bug
where deleted orders (latest event op='d') could inherit a stale 'completed'
order_status from the delete row itself. All 8 of the 210 delete-latest orders
carried a stale order_status='completed' on that row, so they were leaking into
"completed" revenue before the fix. `current_status` for op='d' orders now always
resolves to 'deleted', unconditionally. See `data_quality_issues.md` item #4.

Current-state orders reconstructed: 210 (expected 210)

Orders with latest event = delete: 8 (expected 8)

May-2024-create-month order count: 194 (expected 194)

Duplicate line items dropped: 2

Inactive-product line items included in May 2024 completed revenue: recomputed
under the corrected scope as part of the 381 completed/May-2024 line items
totalling $26,086.52 (see Q3a below); not re-broken-out separately post-fix.

## Q3a: Net revenue per store, May 2024, completed orders

| store_id | net_revenue |
|---|---|
| S1 | 4,931.07 |
| S2 | 5,441.48 |
| S3 | 7,123.14 |
| S4 | 8,590.83 |
| **TOTAL** | **26,086.52** |

## Q3b: Top category per store by completed net revenue (May 2024)

| store_id | category | net_revenue |
|---|---|---|
| S1 | Topicals | 1,507.57 |
| S2 | Concentrates | 1,349.16 |
| S3 | Accessories | 1,441.80 |
| S4 | Vapes | 1,744.85 |

Note: S3's top category flipped from Concentrates to Accessories after the fix
— the 8 wrongly-included "completed" deleted orders were disproportionately
Concentrates for store S3, so removing them changed the ranking.
