/* ============================================================
   01_data_quality_checks.sql
   Project: Trucking Logistics Profitability Analysis
   Purpose: Validate data quality before KPI calculation
   Dialect: MySQL
   ============================================================ */


-- ============================================================
-- 1. DATA COVERAGE
-- ============================================================

SELECT 'trucks' AS table_name, COUNT(*) AS row_count FROM trucks
UNION ALL
SELECT 'drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'clients', COUNT(*) FROM clients
UNION ALL
SELECT 'routes', COUNT(*) FROM routes
UNION ALL
SELECT 'client_rates', COUNT(*) FROM client_rates
UNION ALL
SELECT 'trips', COUNT(*) FROM trips
UNION ALL
SELECT 'fuel_contracts', COUNT(*) FROM fuel_contracts
UNION ALL
SELECT 'fuel_purchases', COUNT(*) FROM fuel_purchases
UNION ALL
SELECT 'truck_downtime', COUNT(*) FROM truck_downtime;


SELECT
    MIN(date_departure) AS trips_start_date,
    MAX(date_departure) AS trips_end_date,
    COUNT(*) AS total_trips
FROM trips;


SELECT
    MIN(purchase_date) AS fuel_start_date,
    MAX(purchase_date) AS fuel_end_date,
    COUNT(*) AS total_fuel_purchases
FROM fuel_purchases;


-- ============================================================
-- 2. PRIMARY KEY DUPLICATES
-- ============================================================

WITH duplicate_checks AS (
    SELECT 'trips.trip_id' AS check_name, COUNT(*) AS duplicate_ids
    FROM (
        SELECT trip_id
        FROM trips
        GROUP BY trip_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'trucks.truck_id', COUNT(*)
    FROM (
        SELECT truck_id
        FROM trucks
        GROUP BY truck_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'drivers.driver_id', COUNT(*)
    FROM (
        SELECT driver_id
        FROM drivers
        GROUP BY driver_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'clients.client_id', COUNT(*)
    FROM (
        SELECT client_id
        FROM clients
        GROUP BY client_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'routes.route_id', COUNT(*)
    FROM (
        SELECT route_id
        FROM routes
        GROUP BY route_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'fuel_purchases.fuel_id', COUNT(*)
    FROM (
        SELECT fuel_id
        FROM fuel_purchases
        GROUP BY fuel_id
        HAVING COUNT(*) > 1
    ) x

    UNION ALL

    SELECT 'fuel_contracts.contract_id', COUNT(*)
    FROM (
        SELECT contract_id
        FROM fuel_contracts
        GROUP BY contract_id
        HAVING COUNT(*) > 1
    ) x
)

SELECT *
FROM duplicate_checks
ORDER BY check_name;


-- ============================================================
-- 3. MISSING VALUES IN CRITICAL FIELDS
-- ============================================================

SELECT
    'trips critical fields' AS check_name,
    COUNT(*) AS failed_records
FROM trips
WHERE date_departure IS NULL
   OR truck_id IS NULL
   OR driver_id IS NULL
   OR client_id IS NULL
   OR route_id IS NULL
   OR distance_km IS NULL
   OR cargo_tons_actual IS NULL
   OR status IS NULL

UNION ALL

SELECT
    'client_rates critical fields',
    COUNT(*)
FROM client_rates
WHERE client_id IS NULL
   OR distance_from_km IS NULL
   OR distance_to_km IS NULL
   OR weight_from_tons IS NULL
   OR weight_to_tons IS NULL
   OR rate_uah_per_ton_km IS NULL
   OR valid_from IS NULL
   OR valid_to IS NULL

UNION ALL

SELECT
    'fuel_purchases critical fields',
    COUNT(*)
FROM fuel_purchases
WHERE contract_id IS NULL
   OR truck_id IS NULL
   OR purchase_date IS NULL
   OR liters IS NULL
   OR fixed_price_per_liter_uah IS NULL
   OR fuel_cost_uah IS NULL;


-- ============================================================
-- 4. REFERENTIAL INTEGRITY
-- ============================================================

SELECT
    'trips -> trucks' AS relationship,
    COUNT(*) AS invalid_records
FROM trips t
LEFT JOIN trucks tr
    ON t.truck_id = tr.truck_id
WHERE tr.truck_id IS NULL

UNION ALL

SELECT
    'trips -> drivers',
    COUNT(*)
FROM trips t
LEFT JOIN drivers d
    ON t.driver_id = d.driver_id
WHERE d.driver_id IS NULL

UNION ALL

SELECT
    'trips -> clients',
    COUNT(*)
FROM trips t
LEFT JOIN clients c
    ON t.client_id = c.client_id
WHERE c.client_id IS NULL

UNION ALL

SELECT
    'trips -> routes',
    COUNT(*)
FROM trips t
LEFT JOIN routes r
    ON t.route_id = r.route_id
WHERE r.route_id IS NULL

UNION ALL

SELECT
    'routes -> clients',
    COUNT(*)
FROM routes r
LEFT JOIN clients c
    ON r.client_id = c.client_id
WHERE c.client_id IS NULL

UNION ALL

SELECT
    'fuel_purchases -> fuel_contracts',
    COUNT(*)
FROM fuel_purchases fp
LEFT JOIN fuel_contracts fc
    ON fp.contract_id = fc.contract_id
WHERE fc.contract_id IS NULL

UNION ALL

SELECT
    'fuel_purchases -> trucks',
    COUNT(*)
FROM fuel_purchases fp
LEFT JOIN trucks tr
    ON fp.truck_id = tr.truck_id
WHERE tr.truck_id IS NULL;


-- ============================================================
-- 5. BUSINESS RULE VALIDATION
-- ============================================================

-- 5.1 No trips during truck downtime

SELECT
    'trips during truck downtime' AS check_name,
    COUNT(*) AS failed_records
FROM trips t
JOIN truck_downtime dt
    ON t.truck_id = dt.truck_id
   AND t.date_departure BETWEEN dt.date_from AND dt.date_to;


-- 5.2 Odometer increases by truck

WITH odometer_check AS (
    SELECT
        fuel_id,
        truck_id,
        purchase_date,
        odometer_km,
        LAG(odometer_km) OVER (
            PARTITION BY truck_id
            ORDER BY purchase_date, fuel_id
        ) AS previous_odometer_km
    FROM fuel_purchases
)

SELECT
    'odometer decreases by truck' AS check_name,
    COUNT(*) AS failed_records
FROM odometer_check
WHERE previous_odometer_km IS NOT NULL
  AND odometer_km < previous_odometer_km;


-- 5.5 Fuel purchase price matches contract price

SELECT
    'fuel price mismatches vs contract' AS check_name,
    COUNT(*) AS failed_records
FROM fuel_purchases fp
JOIN fuel_contracts fc
    ON fp.contract_id = fc.contract_id
WHERE fp.fixed_price_per_liter_uah <> fc.fixed_price_per_liter_uah;


-- 5.6 Fuel contract volume is not overused

SELECT
    'fuel contract overuse' AS check_name,
    COUNT(*) AS failed_contracts
FROM (
    SELECT
        fc.contract_id,
        fc.liters_purchased,
        COALESCE(SUM(fp.liters), 0) AS liters_used
    FROM fuel_contracts fc
    LEFT JOIN fuel_purchases fp
        ON fc.contract_id = fp.contract_id
    GROUP BY
        fc.contract_id,
        fc.liters_purchased
) x
WHERE liters_used > liters_purchased * 1.01;


-- ============================================================
-- 6. RATE MATCHING VALIDATION
-- ============================================================

-- 6.1 Diagnostic check: strict rate matching including weight band.
-- Some local trips can exceed nominal capacity and the highest tariff
-- weight band. These records are reviewed and handled in the revenue
-- model using ranked rate matching.

WITH strict_trip_rate_matches AS (
    SELECT
        t.trip_id,
        COUNT(r.rate_id) AS matching_rates
    FROM trips t
    LEFT JOIN client_rates r
        ON t.client_id = r.client_id
       AND t.date_departure BETWEEN r.valid_from AND r.valid_to
       AND t.distance_km >= r.distance_from_km
       AND t.distance_km < r.distance_to_km
       AND t.cargo_tons_actual >= r.weight_from_tons
       AND t.cargo_tons_actual < r.weight_to_tons
    WHERE t.status <> 'cancelled'
    GROUP BY t.trip_id
)

SELECT
    'strict weight-band rate gaps' AS check_name,
    COUNT(*) AS records_count
FROM strict_trip_rate_matches
WHERE matching_rates = 0

UNION ALL

SELECT
    'strict multiple rate matches',
    COUNT(*)
FROM strict_trip_rate_matches
WHERE matching_rates > 1;


-- 6.2 Core DQ check: rate exists by client, date and distance.
-- Weight-band fallback is handled later in the revenue model.

WITH basic_trip_rate_matches AS (
    SELECT
        t.trip_id,
        COUNT(r.rate_id) AS matching_rates
    FROM trips t
    LEFT JOIN client_rates r
        ON t.client_id = r.client_id
       AND t.date_departure BETWEEN r.valid_from AND r.valid_to
       AND t.distance_km >= r.distance_from_km
       AND t.distance_km < r.distance_to_km
    WHERE t.status <> 'cancelled'
    GROUP BY t.trip_id
)

SELECT
    'trips without client/date/distance rate' AS check_name,
    COUNT(*) AS failed_records
FROM basic_trip_rate_matches
WHERE matching_rates = 0;
