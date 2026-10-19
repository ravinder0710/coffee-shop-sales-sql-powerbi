-- =============================================================================
-- PROJECT      : MONDAY COFFEE - CITY & SALES ANALYSIS
-- PROJECT TYPE : Data Analyst Portfolio Project
-- DATABASE     : PostgreSQL
-- AUTHOR       : Ravinder Gupta
-- =============================================================================
-- PROJECT OVERVIEW
-- This project analyzes city demographics, estimated coffee consumption,
-- customer activity, product sales, revenue, monthly growth, and market potential.
--
-- BUSINESS QUESTIONS COVERED
--   Q1  Estimated coffee consumers by city
--   Q2  Total Q4 2023 revenue and revenue by city
--   Q3  Sales transactions and revenue by product
--   Q4  Revenue per distinct purchasing customer by city
--   Q5  Population, estimated consumers, and actual purchasing customers
--   Q6  Top 3 products by transaction count in each city
--   Q7  Distinct coffee-product purchasers by city
--   Q8  Revenue per customer compared with rent indicators
--   Q9  Monthly revenue growth by city
--   Q10 Top 3 cities by revenue and market potential
--
-- TECHNICAL NOTES
--   * This script uses PostgreSQL syntax (EXTRACT, ::NUMERIC, DATE_TRUNC).
--   * Import CSVs in this order: city -> products -> customers -> sales.
--   * The source schema has no quantity column. COUNT(sale_id) measures
--     transactions, not physical units sold.
--   * Q7 retains the source assumption that product IDs 1-14 are coffee products.
--     Validate this mapping against the products table before publishing results.
-- =============================================================================

-- =============================================================================
-- SECTION 0 : DATA INSPECTION & VALIDATION
-- =============================================================================
SELECT * FROM city;
SELECT * FROM products;
SELECT * FROM customers;
SELECT * FROM sales;

-- Inspect column names and data types.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('city', 'products', 'customers', 'sales')
ORDER BY table_name, ordinal_position;

-- Confirm the sales data coverage.
SELECT MIN(sale_date) AS first_sale_date,
       MAX(sale_date) AS last_sale_date,
       COUNT(*) AS sales_record_count
FROM sales;

-- =============================================================================
-- OPTIONAL RESET & SCHEMA CREATION
-- WARNING: Uncomment DROP statements only if you intend to delete existing data.
-- PostgreSQL database creation/connection is performed separately from this file.
-- =============================================================================
-- DROP TABLE IF EXISTS sales;
-- DROP TABLE IF EXISTS customers;
-- DROP TABLE IF EXISTS products;
-- DROP TABLE IF EXISTS city;

-- CREATE TABLE city (
--     city_id INT PRIMARY KEY,
--     city_name VARCHAR(50) NOT NULL,
--     population BIGINT,
--     estimated_rent NUMERIC(12,2),
--     city_rank INT
-- );
-- CREATE TABLE products (
--     product_id INT PRIMARY KEY,
--     product_name VARCHAR(100) NOT NULL,
--     price NUMERIC(10,2)
-- );
-- CREATE TABLE customers (
--     customer_id INT PRIMARY KEY,
--     customer_name VARCHAR(100),
--     city_id INT REFERENCES city(city_id)
-- );
-- CREATE TABLE sales (
--     sale_id INT PRIMARY KEY,
--     sale_date DATE,
--     product_id INT REFERENCES products(product_id),
--     customer_id INT REFERENCES customers(customer_id),
--     total NUMERIC(12,2),
--     rating INT
-- );
-- DESIGN NOTE: NUMERIC/DECIMAL is generally preferable to FLOAT for currency.

-- =============================================================================
-- SECTION 1 : CITY DEMOGRAPHICS & COFFEE CONSUMER POTENTIAL
-- =============================================================================

-- Q1. Estimated Coffee Consumers by City
-- Business question: If 25% of the population consumes coffee, what is the
-- estimated number of coffee consumers in each city?
SELECT
    city_name,
    population,
    ROUND((population * 0.25 / 1000000.0)::NUMERIC, 2)
        AS estimated_coffee_consumers_millions,
    city_rank
FROM city
ORDER BY estimated_coffee_consumers_millions DESC;

-- Q5. Population, Estimated Consumers & Actual Purchasing Customers
-- LEFT JOIN retains cities with no recorded sales. DISTINCT prevents a customer
-- with multiple sales from being counted more than once.
WITH purchasing_customers AS (
    SELECT ci.city_id,
           COUNT(DISTINCT s.customer_id) AS actual_purchasing_customers
    FROM city AS ci
    LEFT JOIN customers AS c ON c.city_id = ci.city_id
    LEFT JOIN sales AS s ON s.customer_id = c.customer_id
    GROUP BY ci.city_id
)
SELECT
    ci.city_name,
    ci.population,
    ROUND((ci.population * 0.25 / 1000000.0)::NUMERIC, 2)
        AS estimated_coffee_consumers_millions,
    COALESCE(pc.actual_purchasing_customers, 0) AS actual_purchasing_customers
FROM city AS ci
LEFT JOIN purchasing_customers AS pc ON pc.city_id = ci.city_id
ORDER BY actual_purchasing_customers DESC, ci.city_name;

-- =============================================================================
-- SECTION 2 : REVENUE & PRODUCT PERFORMANCE
-- =============================================================================

-- Q2A. Total Revenue in Q4 2023
-- A half-open date range is clear and works well with date indexes.
SELECT SUM(total) AS total_revenue_q4_2023
FROM sales
WHERE sale_date >= DATE '2023-10-01'
  AND sale_date <  DATE '2024-01-01';

-- Q2B. Revenue by City in Q4 2023
SELECT
    ci.city_name,
    SUM(s.total) AS total_revenue_q4_2023
FROM sales AS s
JOIN customers AS c ON c.customer_id = s.customer_id
JOIN city AS ci ON ci.city_id = c.city_id
WHERE s.sale_date >= DATE '2023-10-01'
  AND s.sale_date <  DATE '2024-01-01'
GROUP BY ci.city_name
ORDER BY total_revenue_q4_2023 DESC;

-- Q3. Sales Transactions by Product
-- The source table has no quantity field, so this counts sales records rather
-- than units. LEFT JOIN includes products that have never sold.
SELECT
    p.product_id,
    p.product_name,
    COUNT(s.sale_id) AS total_sales_transactions,
    COALESCE(SUM(s.total), 0) AS total_revenue
FROM products AS p
LEFT JOIN sales AS s ON s.product_id = p.product_id
GROUP BY p.product_id, p.product_name
ORDER BY total_sales_transactions DESC, p.product_name;

-- Q6. Top 3 Selling Products by City (ranked by transaction count)
-- DENSE_RANK preserves ties; a city can therefore return more than three rows
-- if multiple products tie at rank 3.
WITH product_city_sales AS (
    SELECT
        ci.city_name,
        p.product_name,
        COUNT(s.sale_id) AS total_sales_transactions
    FROM sales AS s
    JOIN products AS p ON p.product_id = s.product_id
    JOIN customers AS c ON c.customer_id = s.customer_id
    JOIN city AS ci ON ci.city_id = c.city_id
    GROUP BY ci.city_name, p.product_name
), ranked_products AS (
    SELECT *,
           DENSE_RANK() OVER (
               PARTITION BY city_name
               ORDER BY total_sales_transactions DESC
           ) AS product_rank
    FROM product_city_sales
)
SELECT city_name, product_name, total_sales_transactions, product_rank
FROM ranked_products
WHERE product_rank <= 3
ORDER BY city_name, product_rank, product_name;

-- =============================================================================
-- SECTION 3 : CUSTOMER & CITY ECONOMICS
-- =============================================================================

-- Q4. Revenue per Distinct Purchasing Customer by City
-- This is revenue per purchasing customer across the data period, not average
-- transaction value.
SELECT
    ci.city_name,
    SUM(s.total) AS total_revenue,
    COUNT(DISTINCT s.customer_id) AS distinct_purchasing_customers,
    ROUND(
        SUM(s.total)::NUMERIC / NULLIF(COUNT(DISTINCT s.customer_id), 0), 2
    ) AS revenue_per_purchasing_customer
FROM sales AS s
JOIN customers AS c ON c.customer_id = s.customer_id
JOIN city AS ci ON ci.city_id = c.city_id
GROUP BY ci.city_name
ORDER BY total_revenue DESC;

-- Q7. Unique Customers Who Purchased Coffee Products
-- Source assumption: product IDs 1-14 represent coffee products. Verify this
-- mapping in products; if product categories exist, filter on category instead.
SELECT
    ci.city_name,
    COUNT(DISTINCT s.customer_id) AS unique_coffee_purchasing_customers
FROM city AS ci
LEFT JOIN customers AS c ON c.city_id = ci.city_id
LEFT JOIN sales AS s
    ON s.customer_id = c.customer_id
   AND s.product_id BETWEEN 1 AND 14
GROUP BY ci.city_name
ORDER BY unique_coffee_purchasing_customers DESC, ci.city_name;

-- Q8. Revenue per Customer vs Rent per Customer
-- estimated_rent / purchasing customers is a comparison proxy, not a direct
-- customer-level expense or a measure of profitability.
WITH city_sales AS (
    SELECT
        ci.city_id,
        ci.city_name,
        SUM(s.total) AS total_revenue,
        COUNT(DISTINCT s.customer_id) AS purchasing_customers
    FROM city AS ci
    JOIN customers AS c ON c.city_id = ci.city_id
    JOIN sales AS s ON s.customer_id = c.customer_id
    GROUP BY ci.city_id, ci.city_name
)
SELECT
    ci.city_name,
    ci.estimated_rent,
    cs.purchasing_customers,
    ROUND(cs.total_revenue::NUMERIC / NULLIF(cs.purchasing_customers, 0), 2)
        AS revenue_per_purchasing_customer,
    ROUND(ci.estimated_rent::NUMERIC / NULLIF(cs.purchasing_customers, 0), 2)
        AS estimated_rent_per_purchasing_customer
FROM city AS ci
JOIN city_sales AS cs ON cs.city_id = ci.city_id
ORDER BY revenue_per_purchasing_customer DESC;

-- =============================================================================
-- SECTION 4 : SALES GROWTH & MARKET POTENTIAL
-- =============================================================================

-- Q9. Monthly Revenue Growth by City
-- LAG compares a month with the previous available month in that city's data.
-- If a city has no sales in a calendar month, the previous row may be more
-- than one calendar month earlier. NULLIF protects against division by zero.
WITH monthly_sales AS (
    SELECT
        ci.city_id,
        ci.city_name,
        DATE_TRUNC('month', s.sale_date)::DATE AS sales_month,
        SUM(s.total) AS monthly_revenue
    FROM sales AS s
    JOIN customers AS c ON c.customer_id = s.customer_id
    JOIN city AS ci ON ci.city_id = c.city_id
    GROUP BY ci.city_id, ci.city_name,
             DATE_TRUNC('month', s.sale_date)::DATE
), revenue_with_previous_month AS (
    SELECT
        city_id,
        city_name,
        sales_month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (
            PARTITION BY city_id ORDER BY sales_month
        ) AS previous_available_month_revenue
    FROM monthly_sales
)
SELECT
    city_name,
    sales_month,
    monthly_revenue,
    previous_available_month_revenue,
    ROUND(
        ((monthly_revenue - previous_available_month_revenue)
          / NULLIF(previous_available_month_revenue, 0))::NUMERIC * 100,
        2
    ) AS revenue_growth_pct
FROM revenue_with_previous_month
ORDER BY city_name, sales_month;

-- Q10. Top 3 Cities by Revenue & Market Potential
-- Ranking is based on recorded revenue. The 25% coffee-consumption estimate is
-- an assumption, not a measured count of coffee consumers.
WITH city_sales AS (
    SELECT
        ci.city_id,
        ci.city_name,
        SUM(s.total) AS total_revenue,
        COUNT(DISTINCT s.customer_id) AS purchasing_customers,
        ROUND(
            SUM(s.total)::NUMERIC / NULLIF(COUNT(DISTINCT s.customer_id), 0), 2
        ) AS revenue_per_purchasing_customer
    FROM city AS ci
    JOIN customers AS c ON c.city_id = ci.city_id
    JOIN sales AS s ON s.customer_id = c.customer_id
    GROUP BY ci.city_id, ci.city_name
)
SELECT
    ci.city_name,
    cs.total_revenue,
    ci.estimated_rent,
    cs.purchasing_customers,
    ROUND((ci.population * 0.25 / 1000000.0)::NUMERIC, 3)
        AS estimated_coffee_consumers_millions,
    cs.revenue_per_purchasing_customer,
    ROUND(ci.estimated_rent::NUMERIC / NULLIF(cs.purchasing_customers, 0), 2)
        AS estimated_rent_per_purchasing_customer
FROM city_sales AS cs
JOIN city AS ci ON ci.city_id = cs.city_id
ORDER BY cs.total_revenue DESC
LIMIT 3;

-- =============================================================================
-- SECTION 5 : BUSINESS RECOMMENDATIONS & VALIDATION
-- =============================================================================
-- The source notes suggest Pune, Delhi, and Jaipur as potential priority cities.
-- Re-run Q10 on the current database before publishing those rankings.
-- Validate the following before making an investment recommendation:
--   1. Revenue date coverage is comparable across cities.
--   2. estimated_rent has a consistent unit and time period.
--   3. Customer counts cover the same time window.
--   4. The 25% coffee-consumption assumption is appropriate for the market.
--   5. Rent/customer is treated as a comparison proxy, not profit.
--   6. Product IDs 1-14 are confirmed as coffee products for Q7.
--
-- Suggested analysis framework:
--   * Revenue leaders: investigate repeat purchasing, demand, and capacity.
--   * High estimated consumer population: evaluate acquisition opportunities.
--   * Rent indicators: assess alongside revenue, costs, and local demand.
--   * Monthly growth: investigate sustained trends and seasonality.
-- =============================================================================
-- END OF PROJECT
-- NEXT STEP: Cross-check dashboard KPIs against these SQL outputs before sharing.
-- =============================================================================
