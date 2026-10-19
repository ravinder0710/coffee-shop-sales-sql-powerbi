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
