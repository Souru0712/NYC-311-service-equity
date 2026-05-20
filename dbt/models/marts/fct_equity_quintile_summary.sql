-- fct_equity_quintile_summary.sql
--
-- GRAIN: complaint_type × income_quintile
-- PURPOSE: Equity comparison WITHIN each complaint type. The aggregate
--          (across-complaint-type) comparison is intentionally NOT produced
--          here, because it inverts due to complaint-mix confounding
--          (Q5 P90 is dominated by structurally slow complaint types).
--
-- METHOD:  1. Compute P90 response time per (tract × complaint_type).
--          2. Require >= 30 complaints in that cell (stable P90 tail).
--          3. Take the MEDIAN of those tract-level P90s within each
--             (complaint_type × income_quintile). Median, not mean, so a few
--             outlier tracts cannot drag the number (this is the fix for the
--             old AVG-of-ratios explosion that produced scores like 54.5).
--          4. Report raw HOURS. No ratios are stored at the tract level.
--             The Q1-vs-Q5 gap is computed ONCE, at the end, as a ratio of
--             two final median-hour numbers (see fct_equity_gap_by_type below
--             / or compute in the BI layer).
--
-- NOTE ON COLUMN NAMES: assumes response_time_hours, tract_geoid,
-- complaint_type on the fact and income_quintile on dim_tract, per the
-- direction queries. Adjust refs if your actual columns differ.

with requests as (

    select
        f.tract_geoid,
        f.complaint_type,
        d.income_quintile,
        f.response_time_hours
    from {{ ref('fct_request_response_time') }} f
    inner join {{ ref('dim_tract') }} d
        on f.tract_geoid = d.tract_geoid
    where d.income_quintile is not null
      and f.response_time_hours is not null

),

-- Step 1 + 2: per-tract P90 within each complaint type, with volume floor.
tract_complaint_p90 as (

    select
        tract_geoid,
        complaint_type,
        income_quintile,
        count(*)                                        as tract_complaint_n,
        approx_percentile(response_time_hours, 0.90)    as tract_p90_hours,
        approx_percentile(response_time_hours, 0.50)    as tract_p50_hours
    from requests
    group by 1, 2, 3
    having count(*) >= 30   -- tail-stability floor; defensible in interview

),

-- Step 3: median of tract-level P90s within complaint_type × quintile.
quintile_summary as (

    select
        complaint_type,
        income_quintile,
        count(*)                            as n_tracts,        -- tracts surviving the floor
        sum(tract_complaint_n)              as n_complaints,    -- total complaints behind the row
        median(tract_p90_hours)             as median_tract_p90_hours,
        median(tract_p50_hours)             as median_tract_p50_hours
    from tract_complaint_p90
    group by 1, 2

)

select
    complaint_type,
    income_quintile,
    n_tracts,
    n_complaints,
    round(median_tract_p90_hours, 1)        as median_tract_p90_hours,
    round(median_tract_p50_hours, 1)        as median_tract_p50_hours
from quintile_summary
order by complaint_type, income_quintile
