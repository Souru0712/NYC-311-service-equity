-- fct_equity_trend_monthly.sql
--
-- GRAIN: income_quintile × month
-- PURPOSE: Time-series of service speed by income quintile (Finding 3).
-- METHOD:  Pool EVERY complaint in a quintile for the month, compute ONE
--          direct P90. Quintile-month volume is large, so:
--            - no per-tract ratios (the source of the old 23.32 June-2020 spike)
--            - no volume filter needed
--            - report raw HOURS, not equity scores
--
-- INTERPRETATION CAVEAT (carry into the dashboard + Groq context):
-- This is volume-weighted and pooled ACROSS complaint types, so it inherits
-- the same complaint-mix confound as the aggregate. It is honest as a
-- "typical wait over time" trend, but it is NOT an "income equity gap over
-- time" series. Label it "Median / P90 response time by quintile over time",
-- NOT "equity gap over time". The real equity story is within-complaint-type
-- (fct_equity_gap_by_type), not this trend.

with requests as (

    select
        f.request_month                             as month,   -- pre-computed DATE_TRUNC on the fact
        d.income_quintile,
        f.response_time_hours
    from {{ ref('fct_request_response_time') }} f
    inner join {{ ref('dim_tract') }} d
        on f.tract_geoid = d.tract_geoid
    where d.income_quintile is not null
      and f.response_time_hours is not null
      and f.request_month is not null

)

select
    month,
    income_quintile,
    count(*)                                        as n_complaints,
    round(approx_percentile(response_time_hours, 0.90), 1)  as p90_hours,
    round(approx_percentile(response_time_hours, 0.50), 1)  as p50_hours
from requests
group by 1, 2
order by 1, 2
