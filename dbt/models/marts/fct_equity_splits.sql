-- Aggregated equity fact: grain = complaint_type × tract × month.
--
-- Equity score methodology — P50 of tract P90s (median-tract baseline):
--
--   Step 1 — tract_stats: aggregate all individual requests to tract level.
--            Produces one P90 per tract per complaint type per month.
--
--   Step 2 — city_baseline: take the MEDIAN (P50) of all those tract P90s.
--            Every tract counts equally regardless of complaint volume.
--            A Manhattan tract filing 10,000 NOISE complaints has the same weight
--            as a Staten Island tract filing 50 — preventing high-volume areas
--            from skewing the citywide reference.
--
--   Step 3 — equity_score = this tract's P90 / city_baseline P90.
--            Score = 1.0 → this tract matches the median tract experience.
--            Score > 1.0 → residents wait longer than the typical NYC tract.
--            Score < 1.0 → residents wait less than the typical NYC tract.
--
-- Why not volume-weighted city P90?
--   Using PERCENTILE_CONT(0.9) across all raw requests produces a denominator
--   skewed by whichever boroughs file the most complaints for a given type.
--   For complaint types concentrated in fast-responding areas, this inflates
--   equity scores for tracts in slower boroughs even when their absolute
--   wait times are reasonable.

WITH tract_stats AS (
    -- One row per tract × complaint type × month with all response-time metrics
    SELECT
        f.tract_geoid,
        f.complaint_type,
        f.request_month,
        f.borough,
        COUNT(*)                                                                    AS request_count,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY f.response_time_hours)        AS p50_hours,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY f.response_time_hours)        AS p75_hours,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY f.response_time_hours)        AS p90_hours
    FROM {{ ref('fct_request_response_time') }} f
    GROUP BY f.tract_geoid, f.complaint_type, f.request_month, f.borough
),

city_baseline AS (
    -- Median of all tract P90s — equal weight per tract, not per complaint
    SELECT
        complaint_type,
        request_month,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY p90_hours)                    AS city_p90
    FROM tract_stats
    GROUP BY complaint_type, request_month
)

SELECT
    t.tract_geoid,
    t.complaint_type,
    t.request_month,
    t.borough,
    d.income_quintile,
    d.median_household_income,
    d.pct_below_poverty,
    d.total_population,
    d.pop_black,
    d.pop_hispanic,
    t.request_count,
    t.p50_hours,
    t.p75_hours,
    t.p90_hours,
    c.city_p90,
    ROUND(t.p90_hours / NULLIF(c.city_p90, 0), 4)                                 AS equity_score,
    CURRENT_TIMESTAMP()                                                             AS mart_refreshed_at
FROM tract_stats t
JOIN {{ ref('dim_tract') }} d
    ON t.tract_geoid = d.tract_geoid
JOIN city_baseline c
    ON t.complaint_type = c.complaint_type
    AND t.request_month  = c.request_month
