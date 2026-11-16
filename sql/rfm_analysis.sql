-- =====================================================================
-- E-commerce Customer Segmentation (Olist) - SQL part
-- Dialect: SQLite (3.25+ for window functions). Tables: orders, customers, payments
-- =====================================================================

-- Indexes on join keys (big speed-up in SQLite)
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_customers_id    ON customers(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_order  ON payments(order_id);

-- Step 1: One row per DELIVERED order with the REAL customer id and order value
CREATE TABLE delivered_orders AS
SELECT
    o.order_id,
    c.customer_unique_id,                         -- real person (customer_id changes every order!)
    DATE(o.order_purchase_timestamp)  AS order_date,
    p.order_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS order_value   -- an order can have several payments
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';

CREATE INDEX IF NOT EXISTS idx_delivered_customer ON delivered_orders(customer_unique_id);

-- Step 2: Recency, Frequency, Monetary per customer + R and M scores (1-5)
-- Reference date = 2018-09-01 (the day after our data ends)
WITH rfm AS (
    SELECT
        customer_unique_id,
        CAST(JULIANDAY('2018-09-01') - JULIANDAY(MAX(order_date)) AS INTEGER) AS recency_days,
        COUNT(DISTINCT order_id)                                            AS frequency,
        ROUND(SUM(order_value), 2)                                          AS monetary
    FROM delivered_orders
    GROUP BY customer_unique_id
)
SELECT
    *,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- most recent buyers get 5
    NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score   -- biggest spenders get 5
FROM rfm;

-- Business question: how many customers ever came back for a 2nd order?
SELECT
    COUNT(*)                                              AS total_customers,
    SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END)         AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS n_orders
    FROM delivered_orders
    GROUP BY customer_unique_id
);

-- Cohort base: each customer's first purchase month + every month they ordered in
WITH first_purchase AS (
    SELECT customer_unique_id, MIN(STRFTIME('%Y-%m', order_date)) AS cohort_month
    FROM delivered_orders
    GROUP BY customer_unique_id
)
SELECT DISTINCT
    f.cohort_month,
    STRFTIME('%Y-%m', d.order_date) AS order_month,
    d.customer_unique_id
FROM delivered_orders d
JOIN first_purchase f ON d.customer_unique_id = f.customer_unique_id;

