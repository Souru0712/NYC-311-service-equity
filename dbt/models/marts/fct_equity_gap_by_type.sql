-- fct_equity_gap_by_type.sql
--
-- GRAIN: complaint_type (one row per complaint type)
-- PURPOSE: Produces the defensible "Q1 vs Q5" gap PER complaint type — the
--          new headline of the project. The gap is a ratio of two final
--          median-hour numbers, computed ONCE here. No ratio-of-ratios.
--
-- GUARD:   Requires BOTH Q1 and Q5 to clear a complaint-volume floor before a
--          gap is reported. This is what kills the Cranes & Derricks artifact
--          (191 complaints citywide -> excluded). Real Time Enforcement
--          (6,543) and other high-volume types survive.
--
-- USAGE:   The dashboard's headline KPI should read the TOP row of this model
--          (largest gap among types that clear the floor), e.g.
--          "Real Time Enforcement: Q1 median P90 = X hrs vs Q5 = Y hrs (3.7x)".

with summary as (

    select * from {{ ref('fct_equity_quintile_summary') }}

),

q1 as (
    select
        complaint_type,
        n_complaints            as q1_n_complaints,
        median_tract_p90_hours  as q1_p90_hours
    from summary
    where income_quintile = 1
),

q5 as (
    select
        complaint_type,
        n_complaints            as q5_n_complaints,
        median_tract_p90_hours  as q5_p90_hours
    from summary
    where income_quintile = 5
),

joined as (

    select
        q1.complaint_type,
        q1.q1_n_complaints,
        q5.q5_n_complaints,
        q1.q1_p90_hours,
        q5.q5_p90_hours
    from q1
    inner join q5 on q1.complaint_type = q5.complaint_type
    -- inner join: a gap requires BOTH quintiles present at the tract grain

)

select
    complaint_type,
    q1_n_complaints,
    q5_n_complaints,
    q1_p90_hours,
    q5_p90_hours,
    -- gap computed exactly once, here, as a ratio of two median-hour numbers.
    -- > 1.0 means Q1 (low income) waits longer; < 1.0 means Q5 waits longer.
    round(q1_p90_hours / nullif(q5_p90_hours, 0), 2)    as q1_over_q5_gap
from joined
-- volume guard: both quintiles need enough complaints for a stable P90.
-- 500 each is conservative; Real Time Enforcement's 6,543 clears it easily.
where q1_n_complaints >= 500
  and q5_n_complaints >= 500
order by q1_over_q5_gap desc
