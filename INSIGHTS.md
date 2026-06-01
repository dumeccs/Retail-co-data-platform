Here's the standalone insights document. Paste it into `INSIGHTS.md`.

# RetailCo — Business Insights

**Period analysed:** May 2024 – May 2026 (≈24 months) · **Source:** Kimball warehouse (`marts.*`) · **Scope:** all four stores (Lagos, Abuja, Port Harcourt, Kano)

All revenue figures exclude cancelled orders. Currency: Nigerian Naira (₦).

---

## Executive summary

- The business is **steady-state**: ~₦2.7B revenue and ~3,200 orders every month, essentially flat over the 24-month window — no growth trend, but no decline either.
- The single clearest profit lever is **discount discipline**: discounted lines earn roughly **half** the margin of full-price lines (13.8% vs 28.9%).
- Customer **segments are behaviourally indistinguishable** (AOV ₦848k–₦859k, ~15 orders each across all four segments) — current segmentation has no analytical value as-is.
- Payments are **digital-first and evenly spread** across five methods, with a uniform ~2% refund rate.
- Data quality is strong and monitored: **2.03%** of payments are anomalous and automatically isolated; soft-deleted customers/products are retained for historical accuracy.

---

## 1. Revenue performance

Revenue is stable at **~₦2.7B/month** across ~3,200 monthly orders, holding flat from mid-2024 through early-2026 (the May-2024 and May-2026 endpoints are partial months and should be ignored in trend reading). Total net revenue over the period is **~₦65.9B**.

Revenue is **well-diversified across eight categories**, each contributing ₦7.5B–₦9.1B net — led by **Electronics (₦9.09B)** and **Books & Media (₦8.97B)**, with no single category dominant. The four stores carry comparable volume. Top individual products (e.g. SKU-01135, SKU-00930) each generate ₦80M–₦97M, but no product is a concentration risk.

**Recommendation:** the flat trend and balanced mix mean upside comes from *growth initiatives* (acquisition, basket size) rather than rebalancing — there's no obviously under- or over-weighted category to correct.

## 2. Customer behaviour

Across ~5,000 customers, the average customer places **~15 orders** (median 15, range 3–31) at an **average order value of ~₦850k**. The striking result is across **segments** (wholesale, retail, corporate, vip):

| Segment | Customers | Orders/customer | Avg order value |
|---|---|---|---|
| wholesale | 1,291 | 15.2 | ₦851,660 |
| retail | 1,288 | 15.2 | ₦856,630 |
| corporate | 1,212 | 15.3 | ₦848,167 |
| vip | 1,209 | 15.1 | ₦858,656 |

The segments are **functionally identical** on every behavioural metric. Whatever logic assigns these labels, it does not correspond to differences in how customers actually buy.

**Recommendation:** rebuild segmentation on **observed behaviour** (recency/frequency/monetary, category affinity) rather than the inherited labels — the current scheme can't support targeting, pricing, or retention strategy.

## 3. Product & discount analysis

Margins by category cluster between **23.9% and 28.4%**, with **Health & Beauty richest (28.4%)** and **Food & Beverage thinnest (23.9%)**. Discounting is applied lightly and uniformly — ~3.5% of gross sales across every category.

But the line-level view exposes the real cost of discounting:

| Line type | Lines | Avg discount | Margin |
|---|---|---|---|
| Full price | 274,086 | 0% | **28.9%** |
| Discounted | 68,679 | 17.5% | **13.8%** |

A discounted line carries an average **17.5% markdown that cuts its margin roughly in half**. Only ~20% of lines are discounted today, so the blended impact is modest — but each incremental discount is expensive.

**Recommendation:** treat discount depth as a governed lever. Cap markdowns (especially on thin-margin Food & Beverage), and require a contribution-margin check before discounting — the data shows margin is far more sensitive to discount *depth* than to category mix.

## 4. Payment channel insights

Payments are **highly digital** — four of five methods (USSD, Mobile Money, Card, Bank Transfer) are digital; only Cash is not. Volume and value are **evenly distributed** (~₦11.4B–₦11.8B net collected per method, ~14k payments each), with **USSD marginally leading** (₦11.79B net). No channel dominates.

**Refund rates are uniform at ~2%** (1.97%–2.16%) across all methods — no channel shows anomalous refund behaviour.

**Recommendation:** the even split means no channel-consolidation savings are obvious; the priority is keeping all five channels reliable. The ~2% refund baseline is healthy and worth monitoring per method for drift.

## 5. Operational data quality

The pipeline isolates anomalies automatically into a `flagged_payments` artifact rather than letting them distort revenue. **2.03% of payments (1,460) are anomalous:**

| Type | Count | Value |
|---|---|---|
| Unexplained negatives | 756 | −₦1.9M total (−₦105 to −₦4,993) |
| Zero-amount | 704 | ₦0 |

These are excluded from all revenue and payment analysis above; **valid refunds (negative + `payment_type='refund'`) are kept** and netted correctly.

Additionally, **107 customers and 50 products are soft-deleted** but retained in the warehouse as closed historical records (`is_current=false`), so older orders still resolve to the correct (now-discontinued) entity. Order-lifecycle integrity is **clean** — every delivered/shipped order has all prior milestone timestamps, and the only "missing" timestamps belong to orders legitimately still in `pending`/`paid` or `cancelled` states.

**Recommendation:** route the `flagged_payments` table into a weekly operational review — a 2% anomaly rate is manageable but worth investigating at source (the 704 zero-amount records in particular suggest a payment-capture gap in the ERP).

---

## Methodology & caveats

- Figures come from the dimensional warehouse; facts join to the **SCD2 version of each customer/product valid at the time of the event**, so margins, segments, and prices reflect what was true at the moment of sale.
- This is a **synthetic dataset**: product names and categories are randomly paired (e.g. a "Salad" under Automotive), so individual product semantics are meaningless — only aggregates are meaningful. The near-uniform segments are likely also a data-generation artifact, though the finding (that the labels don't differentiate behaviour) stands.
- Some source records carry **future-dated update timestamps**; these were validated as harmless to the analysis (all facts resolved to real dimension members) and are noted as a source-system quirk, not a pipeline error.
- The first and last calendar months are partial extraction windows and are excluded from trend conclusions.


