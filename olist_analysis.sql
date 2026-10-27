-- ============================================================================
-- Olist delivery performance & customer satisfaction: SQL workflow
-- Database: PostgreSQL | Schema: olist
-- Run this file top to bottom. Every statement below was used in the project.
--
--   Part 1  Create the schema and raw tables
--   Part 2  Load the CSV files (done outside SQL)
--   Part 3  Profile the raw data and run quality checks
--   Part 4  Clean: build the views the analysis runs on
--   Part 5  Analysis queries (the findings shown on the dashboard)
--   Part 6  Build the BI views that Power BI imports
--   Part 7  Final checks on the BI views
-- ============================================================================

-- ============================================================================
-- PART 1: Create schema and raw tables (one table per CSV file)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS olist;
SET search_path TO olist;

CREATE TABLE customers (
  customer_id TEXT, customer_unique_id TEXT,
  customer_zip_code_prefix TEXT, customer_city TEXT, customer_state TEXT);

CREATE TABLE geolocation (
  geolocation_zip_code_prefix TEXT, geolocation_lat NUMERIC,
  geolocation_lng NUMERIC, geolocation_city TEXT, geolocation_state TEXT);

CREATE TABLE orders (
  order_id TEXT, customer_id TEXT, order_status TEXT,
  order_purchase_timestamp TIMESTAMP, order_approved_at TIMESTAMP,
  order_delivered_carrier_date TIMESTAMP, order_delivered_customer_date TIMESTAMP,
  order_estimated_delivery_date TIMESTAMP);

CREATE TABLE order_items (
  order_id TEXT, order_item_id INT, product_id TEXT, seller_id TEXT,
  shipping_limit_date TIMESTAMP, price NUMERIC, freight_value NUMERIC);

CREATE TABLE order_payments (
  order_id TEXT, payment_sequential INT, payment_type TEXT,
  payment_installments INT, payment_value NUMERIC);

CREATE TABLE order_reviews (
  review_id TEXT, order_id TEXT, review_score INT,
  review_comment_title TEXT, review_comment_message TEXT,
  review_creation_date TIMESTAMP, review_answer_timestamp TIMESTAMP);

CREATE TABLE products (
  product_id TEXT, product_category_name TEXT,
  product_name_lenght INT, product_description_lenght INT, product_photos_qty INT,
  product_weight_g INT, product_length_cm INT, product_height_cm INT, product_width_cm INT);

CREATE TABLE sellers (
  seller_id TEXT, seller_zip_code_prefix TEXT, seller_city TEXT, seller_state TEXT);

CREATE TABLE category_translation (
  product_category_name TEXT, product_category_name_english TEXT);

-- ============================================================================
-- PART 2: Load data
-- ============================================================================

-- Load each of the 9 Olist CSV files into the table with the matching name
-- (olist_orders_dataset.csv -> olist.orders, and so on).
-- Loading is not done in this script.

-- ============================================================================
-- PART 3: Profile the raw data and run quality checks
-- ============================================================================

-- 3.1 Row count of every raw table
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM olist.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM olist.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM olist.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM olist.order_reviews
UNION ALL SELECT 'customers', COUNT(*) FROM olist.customers
UNION ALL SELECT 'products', COUNT(*) FROM olist.products
UNION ALL SELECT 'sellers', COUNT(*) FROM olist.sellers
UNION ALL SELECT 'geolocation', COUNT(*) FROM olist.geolocation
UNION ALL SELECT 'category_translation', COUNT(*) FROM olist.category_translation;

-- 3.2 Order status mix (only "delivered" orders can be judged on lateness)
SELECT order_status, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM olist.orders
GROUP BY order_status
ORDER BY orders DESC;

-- 3.3 Date range, and orders with no delivery date
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS no_delivery_date,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL
                        AND order_status = 'delivered') AS delivered_but_no_date
FROM olist.orders;

-- 3.4 Duplicates: duplicate orders, duplicate review ids, orders with several reviews, customers with several orders
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM olist.orders) AS dup_orders,
  (SELECT COUNT(*) - COUNT(DISTINCT review_id) FROM olist.order_reviews) AS dup_review_ids,
  (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM olist.order_reviews) AS extra_reviews_per_order,
  (SELECT COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM olist.customers) AS repeat_customer_rows;

-- 3.5 Orders per month (all statuses), to see the period covered
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month, COUNT(*) AS orders
FROM olist.orders GROUP BY 1 ORDER BY 1;

-- 3.6 Quality checks: impossible dates, bad prices, orphan rows, missing categories
SELECT
  (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase,
  (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_carrier_date < order_purchase_timestamp) AS carrier_before_purchase,
  (SELECT COUNT(*) FROM olist.order_items WHERE price <= 0 OR freight_value < 0) AS bad_prices,
  (SELECT COUNT(*) FROM olist.orders o WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.order_id = o.order_id)) AS orders_without_items,
  (SELECT COUNT(*) FROM olist.order_items i WHERE NOT EXISTS (SELECT 1 FROM olist.orders o WHERE o.order_id = i.order_id)) AS items_without_order,
  (SELECT COUNT(*) FROM olist.order_payments WHERE payment_value = 0) AS zero_payments,
  (SELECT COUNT(*) FROM olist.order_payments WHERE payment_type = 'not_defined') AS undefined_payment_type,
  (SELECT COUNT(*) FROM olist.products WHERE product_category_name IS NULL) AS products_no_category,
  (SELECT COUNT(DISTINCT p.product_category_name) FROM olist.products p
     LEFT JOIN olist.category_translation t ON t.product_category_name = p.product_category_name
     WHERE t.product_category_name IS NULL AND p.product_category_name IS NOT NULL) AS categories_not_translated;

-- ============================================================================
-- PART 4: Clean the data: views the analysis is built on
-- ============================================================================

-- 4.1 delivered_orders: one row per delivered order with a delivery date.
--      Customer ids are mapped to the real customer (customer_unique_id), only the latest
--      review is kept per order, and lateness (is_late, days_vs_estimate) is calculated.
CREATE OR REPLACE VIEW olist.delivered_orders AS
WITH latest_review AS (
  SELECT DISTINCT ON (order_id) order_id, review_score
  FROM olist.order_reviews
  ORDER BY order_id, review_answer_timestamp DESC
)
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS days_vs_estimate,
       (o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date) AS is_late,
       r.review_score
FROM olist.orders o
JOIN olist.customers c ON c.customer_id = o.customer_id
LEFT JOIN latest_review r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

-- 4.2 Check the cleaned view: order count, late %, average score, orders with no review
SELECT COUNT(*) AS orders,
       ROUND(100.0 * AVG(is_late::int), 1) AS late_pct,
       ROUND(AVG(review_score), 2) AS avg_score,
       COUNT(*) FILTER (WHERE review_score IS NULL) AS no_review
FROM olist.delivered_orders;

-- 4.3 analysis_orders: restrict to the full-month window Jan 2017 to Aug 2018
CREATE OR REPLACE VIEW olist.analysis_orders AS
SELECT * FROM olist.delivered_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp <  '2018-09-01';

-- ============================================================================
-- PART 5: Analysis queries
-- ============================================================================

-- 5.1 Late vs on-time: orders, average score, % rated 1-2 stars
SELECT is_late,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(review_score), 1) AS pct_low_score
FROM olist.analysis_orders
GROUP BY is_late;

-- 5.2 Rating by how many days late
SELECT CASE WHEN days_vs_estimate <= 0  THEN '1. on time / early'
            WHEN days_vs_estimate <= 3  THEN '2. 1-3 days late'
            WHEN days_vs_estimate <= 7  THEN '3. 4-7 days late'
            WHEN days_vs_estimate <= 14 THEN '4. 8-14 days late'
            ELSE '5. 15+ days late' END AS delay_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(review_score), 1) AS pct_low_score
FROM olist.analysis_orders
GROUP BY 1
ORDER BY 1;

-- 5.3 Share of low-rated orders that were late
SELECT COUNT(*) AS low_score_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 1) AS pct_that_were_late
FROM olist.analysis_orders
WHERE review_score <= 2;

-- 5.4 On-time orders only: does a long wait still hurt?
SELECT CASE WHEN (order_delivered_customer_date::date - order_purchase_timestamp::date) <= 7  THEN '1. up to 7 days'
            WHEN (order_delivered_customer_date::date - order_purchase_timestamp::date) <= 14 THEN '2. 8-14 days'
            WHEN (order_delivered_customer_date::date - order_purchase_timestamp::date) <= 21 THEN '3. 15-21 days'
            ELSE '4. 22+ days' END AS actual_delivery_time,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(review_score), 1) AS pct_low_score
FROM olist.analysis_orders
WHERE NOT is_late
GROUP BY 1
ORDER BY 1;

-- 5.5 Overall repeat-purchase rate
WITH cust AS (
  SELECT customer_unique_id, COUNT(*) AS n_orders
  FROM olist.analysis_orders GROUP BY 1)
SELECT COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE n_orders >= 2) AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n_orders >= 2) / COUNT(*), 2) AS repeat_pct
FROM cust;

-- 5.6 Repeat within 180 days, by first-order experience
WITH ranked AS (
  SELECT customer_unique_id, order_purchase_timestamp, is_late, review_score,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS rn
  FROM olist.analysis_orders),
first_o AS (SELECT * FROM ranked WHERE rn = 1 AND order_purchase_timestamp < '2018-03-01'),
second_o AS (SELECT * FROM ranked WHERE rn = 2)
SELECT f.is_late AS first_order_late,
       CASE WHEN f.review_score IS NULL THEN 'no review'
            WHEN f.review_score <= 2 THEN 'low (1-2)'
            WHEN f.review_score = 3 THEN 'neutral (3)'
            ELSE 'high (4-5)' END AS first_order_score,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.order_purchase_timestamp <= f.order_purchase_timestamp + INTERVAL '180 days') / COUNT(*), 2) AS repeat_180d_pct
FROM first_o f
LEFT JOIN second_o s ON s.customer_unique_id = f.customer_unique_id
GROUP BY 1, 2
ORDER BY 1, 2;

-- 5.7 Seller concentration: share of low-rated and late orders from the top 10% of sellers
WITH so AS (
  SELECT DISTINCT i.seller_id, a.order_id, a.is_late, a.review_score
  FROM olist.order_items i
  JOIN olist.analysis_orders a ON a.order_id = i.order_id),
stats AS (
  SELECT seller_id, COUNT(*) AS orders,
         COUNT(*) FILTER (WHERE review_score <= 2) AS low_orders,
         COUNT(*) FILTER (WHERE is_late) AS late_orders
  FROM so GROUP BY 1),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY low_orders DESC, seller_id) AS rnk,
            COUNT(*) OVER () AS n_sellers
  FROM stats)
SELECT MAX(n_sellers) AS sellers,
       SUM(low_orders) AS total_low_orders,
       ROUND(100.0 * SUM(low_orders)  FILTER (WHERE rnk <= n_sellers * 0.1) / SUM(low_orders), 1) AS pct_low_from_top10pct,
       ROUND(100.0 * SUM(late_orders) FILTER (WHERE rnk <= n_sellers * 0.1) / SUM(late_orders), 1) AS pct_late_from_top10pct
FROM ranked;

-- 5.8 Flagged sellers (30+ orders and 30%+ low-rated) and their share of orders and low ratings
WITH so AS (
  SELECT DISTINCT i.seller_id, a.order_id, a.is_late, a.review_score
  FROM olist.order_items i
  JOIN olist.analysis_orders a ON a.order_id = i.order_id),
stats AS (
  SELECT seller_id, COUNT(*) AS orders, COUNT(review_score) AS reviewed,
         COUNT(*) FILTER (WHERE review_score <= 2) AS low_orders
  FROM so GROUP BY 1),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY low_orders DESC, seller_id) AS rnk,
            COUNT(*) OVER () AS n_sellers
  FROM stats)
SELECT
  ROUND(100.0 * SUM(orders) FILTER (WHERE rnk <= n_sellers * 0.1) / SUM(orders), 1) AS pct_orders_from_top10pct,
  COUNT(*) FILTER (WHERE orders >= 30 AND 100.0 * low_orders / NULLIF(reviewed, 0) >= 30) AS flagged_sellers,
  ROUND(100.0 * SUM(low_orders) FILTER (WHERE orders >= 30 AND 100.0 * low_orders / NULLIF(reviewed, 0) >= 30) / SUM(low_orders), 1) AS pct_low_from_flagged,
  ROUND(100.0 * SUM(orders) FILTER (WHERE orders >= 30 AND 100.0 * low_orders / NULLIF(reviewed, 0) >= 30) / SUM(orders), 1) AS pct_orders_from_flagged
FROM ranked;

-- 5.9 Which states hold most of the late orders
SELECT customer_state,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late)
             / SUM(COUNT(*) FILTER (WHERE is_late)) OVER (), 1) AS pct_of_all_late
FROM olist.analysis_orders
GROUP BY 1
ORDER BY late_orders DESC
LIMIT 8;

-- 5.10 How many low ratings would disappear if late orders behaved like on-time ones
WITH r AS (
  SELECT COUNT(*) FILTER (WHERE review_score <= 2) AS low_all,
         COUNT(review_score) FILTER (WHERE is_late) AS late_reviewed,
         COUNT(*) FILTER (WHERE is_late AND review_score <= 2) AS late_low,
         AVG((review_score <= 2)::int) FILTER (WHERE NOT is_late) AS ontime_low_rate
  FROM olist.analysis_orders)
SELECT low_all, late_low,
       ROUND(late_low - late_reviewed * ontime_low_rate) AS avoidable_low,
       ROUND(100.0 * (late_low - late_reviewed * ontime_low_rate) / low_all, 1) AS pct_of_low_avoidable
FROM r;

-- ============================================================================
-- PART 6: Build the BI views that Power BI imports
-- ============================================================================

-- 6.1 bi_items: one row per item sold (with English category name)
CREATE OR REPLACE VIEW olist.bi_items AS
SELECT i.order_id, i.order_item_id, i.seller_id, i.price, i.freight_value,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       a.customer_state, a.is_late, a.review_score,
       (a.review_score <= 2) AS is_low_score
FROM olist.order_items i
JOIN olist.analysis_orders a ON a.order_id = i.order_id
LEFT JOIN olist.products p ON p.product_id = i.product_id
LEFT JOIN olist.category_translation t ON t.product_category_name = p.product_category_name;

-- 6.2 bi_sellers: one row per seller, with the flagged-seller rule
CREATE OR REPLACE VIEW olist.bi_sellers AS
WITH so AS (
  SELECT DISTINCT i.seller_id, a.order_id, a.is_late, a.review_score
  FROM olist.order_items i
  JOIN olist.analysis_orders a ON a.order_id = i.order_id),
s AS (
  SELECT seller_id, COUNT(*) AS orders, COUNT(review_score) AS reviewed,
         COUNT(*) FILTER (WHERE review_score <= 2) AS low_orders,
         COUNT(*) FILTER (WHERE is_late) AS late_orders
  FROM so GROUP BY 1)
SELECT s.*, sl.seller_state,
       ROUND(100.0 * low_orders / NULLIF(reviewed, 0), 1) AS low_score_pct,
       ROUND(100.0 * late_orders / orders, 1) AS late_pct,
       (orders >= 30 AND 100.0 * low_orders / NULLIF(reviewed, 0) >= 30) AS is_flagged
FROM s
LEFT JOIN olist.sellers sl ON sl.seller_id = s.seller_id;

-- 6.3 bi_orders: one row per order (final version, adds seller handling days, carrier transit days,
--      promised days and order value)
CREATE OR REPLACE VIEW olist.bi_orders AS
SELECT a.order_id, a.customer_unique_id, a.customer_state,
       a.order_purchase_timestamp::date AS purchase_date,
       DATE_TRUNC('month', a.order_purchase_timestamp)::date AS purchase_month,
       (a.order_delivered_customer_date::date - a.order_purchase_timestamp::date) AS delivery_days,
       a.days_vs_estimate, a.is_late, a.review_score,
       (a.review_score <= 2) AS is_low_score,
       CASE WHEN a.days_vs_estimate <= 0  THEN '1. on time / early'
            WHEN a.days_vs_estimate <= 3  THEN '2. 1-3 days late'
            WHEN a.days_vs_estimate <= 7  THEN '3. 4-7 days late'
            WHEN a.days_vs_estimate <= 14 THEN '4. 8-14 days late'
            ELSE '5. 15+ days late' END AS delay_bucket,
       ROW_NUMBER() OVER (PARTITION BY a.customer_unique_id
                          ORDER BY a.order_purchase_timestamp) AS order_seq,
       CASE WHEN o.order_delivered_carrier_date >= a.order_purchase_timestamp
            THEN (o.order_delivered_carrier_date::date - a.order_purchase_timestamp::date) END AS seller_handling_days,
       CASE WHEN o.order_delivered_carrier_date >= a.order_purchase_timestamp
            THEN (a.order_delivered_customer_date::date - o.order_delivered_carrier_date::date) END AS carrier_transit_days,
       (a.order_estimated_delivery_date::date - a.order_purchase_timestamp::date) AS promised_days,
       rev.order_value
FROM olist.analysis_orders a
JOIN olist.orders o ON o.order_id = a.order_id
LEFT JOIN (SELECT order_id, SUM(price + freight_value) AS order_value
           FROM olist.order_items GROUP BY 1) rev ON rev.order_id = a.order_id;

-- 6.4 bi_retention: one row per customer, first order only, did they buy again within 180 days
CREATE OR REPLACE VIEW olist.bi_retention AS
WITH ranked AS (
  SELECT customer_unique_id, order_purchase_timestamp, is_late, review_score,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS rn
  FROM olist.analysis_orders)
SELECT f.customer_unique_id,
       f.is_late AS first_order_late,
       CASE WHEN f.review_score IS NULL THEN 'no review'
            WHEN f.review_score <= 2 THEN 'low (1-2)'
            WHEN f.review_score = 3 THEN 'neutral (3)'
            ELSE 'high (4-5)' END AS first_order_score,
       (s.order_purchase_timestamp IS NOT NULL
        AND s.order_purchase_timestamp <= f.order_purchase_timestamp + INTERVAL '180 days') AS repeated_180d
FROM ranked f
LEFT JOIN ranked s ON s.customer_unique_id = f.customer_unique_id AND s.rn = 2
WHERE f.rn = 1 AND f.order_purchase_timestamp < '2018-03-01';

-- ============================================================================
-- PART 7: Final checks on the BI views
-- ============================================================================

-- 7.1 Row counts of the BI views and number of flagged sellers
SELECT (SELECT COUNT(*) FROM olist.bi_orders) AS bi_orders,
       (SELECT COUNT(*) FROM olist.bi_items) AS bi_items,
       (SELECT COUNT(*) FROM olist.bi_sellers) AS bi_sellers,
       (SELECT COUNT(*) FROM olist.bi_sellers WHERE is_flagged) AS flagged;

-- 7.2 Where does the time go (late vs on-time); the row count should be 96,203
SELECT is_late, COUNT(*) AS orders,
       ROUND(AVG(promised_days), 1)        AS avg_promised_days,
       ROUND(AVG(delivery_days), 1)        AS avg_actual_days,
       ROUND(AVG(seller_handling_days), 1) AS avg_seller_days,
       ROUND(AVG(carrier_transit_days), 1) AS avg_carrier_days
FROM olist.bi_orders GROUP BY is_late;

-- 7.3 Money at stake
SELECT ROUND(SUM(order_value)) AS total_value,
       ROUND(100.0 * SUM(order_value) FILTER (WHERE is_late) / SUM(order_value), 1) AS pct_value_late,
       ROUND(100.0 * SUM(order_value) FILTER (WHERE is_low_score) / SUM(order_value), 1) AS pct_value_low_score
FROM olist.bi_orders;

-- 7.4 Monthly orders, late %, carrier and seller days
SELECT purchase_month, COUNT(*) AS orders,
       ROUND(100.0 * AVG(is_late::int), 1) AS late_pct,
       ROUND(AVG(carrier_transit_days), 1) AS avg_carrier_days,
       ROUND(AVG(seller_handling_days), 1) AS avg_seller_days
FROM olist.bi_orders
GROUP BY 1 ORDER BY 1;

-- 7.5 Monthly promised vs actual delivery days
SELECT purchase_month, ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(delivery_days), 1) AS avg_actual_days
FROM olist.bi_orders GROUP BY 1 ORDER BY 1;
