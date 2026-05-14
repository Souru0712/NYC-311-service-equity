-- ============================================================
-- NYC 311 SERVICE EQUITY MART — ORGANIZED QUERIES
-- ============================================================


-- ============================================================
-- 1. CREATE / GRANT
-- ============================================================

CREATE DATABASE IF NOT EXISTS NYC_311;
CREATE SCHEMA IF NOT EXISTS NYC_311.RAW;
CREATE SCHEMA IF NOT EXISTS NYC_311.STAGING;
CREATE SCHEMA IF NOT EXISTS NYC_311.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS NYC_311.MARTS;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE;

CREATE USER IF NOT EXISTS your-user
  PASSWORD          = 'your-password'
  DEFAULT_ROLE      = TRANSFORMER
  DEFAULT_WAREHOUSE = COMPUTE_WH
  DEFAULT_NAMESPACE = NYC_311
  MUST_CHANGE_PASSWORD = FALSE;

CREATE ROLE IF NOT EXISTS TRANSFORMER;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TRANSFORMER;
GRANT USAGE ON DATABASE NYC_311 TO ROLE TRANSFORMER;
GRANT ALL ON ALL SCHEMAS IN DATABASE NYC_311 TO ROLE TRANSFORMER;
GRANT ROLE TRANSFORMER TO USER your-user;

CREATE OR REPLACE STAGE NYC_311.RAW.S3_STAGE
  URL = 's3://nyc-311-equity-mart/'
  CREDENTIALS = (
    AWS_KEY_ID     = '**insert here**'
    AWS_SECRET_KEY = '**insert here**'
  )
  FILE_FORMAT = (TYPE = PARQUET);

GRANT ALL ON ALL STAGES IN SCHEMA NYC_311.RAW                        TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA NYC_311.RAW          TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA NYC_311.STAGING      TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA NYC_311.INTERMEDIATE TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA NYC_311.MARTS        TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE STAGES IN SCHEMA NYC_311.RAW          TO ROLE TRANSFORMER;
GRANT ALL PRIVILEGES ON FUTURE VIEWS  IN SCHEMA NYC_311.STAGING      TO ROLE TRANSFORMER;


-- ============================================================
-- 2. SHOW
-- ============================================================

SHOW STAGES IN SCHEMA NYC_311.RAW;
SHOW GRANTS TO ROLE TRANSFORMER;


-- ============================================================
-- 3. RAW
-- ============================================================

-- First 5 rows
SELECT * FROM NYC_311.RAW.SOCRATA_311 LIMIT 5;

-- Row count and latest ingestion timestamp
SELECT COUNT(*), MAX(ingestion_timestamp) FROM RAW.SOCRATA_311;

-- Row counts per load date
SELECT
    ingestion_timestamp::DATE AS load_date,
    COUNT(*) AS rows_loaded
FROM NYC_311.RAW.SOCRATA_311
GROUP BY 1
ORDER BY 1 DESC;

-- Latest resolved date
SELECT MAX(resolution_action_updated_date) FROM RAW.SOCRATA_311;

-- Distinct complaint types in raw
SELECT COUNT(DISTINCT complaint_type) FROM NYC_311.RAW.SOCRATA_311;

-- Truncate raw (use with caution)
TRUNCATE TABLE NYC_311.RAW.SOCRATA_311;


-- ============================================================
-- 4. STAGING
-- ============================================================

-- Row count and latest ACS vintage year
SELECT COUNT(*), MAX(vintage_year) FROM RAW.ACS_DEMOGRAPHICS;

-- Distinct complaint types after dedup + cast
SELECT COUNT(DISTINCT complaint_type) FROM NYC_311.STAGING.STG_311_REQUESTS;


-- ============================================================
-- 5. INTERMEDIATE
-- ============================================================

-- Distinct complaint types after filtering to closed complaints with response time
SELECT COUNT(DISTINCT complaint_type) FROM NYC_311.INTERMEDIATE.INT_311_WITH_RESPONSE_TIME;

-- tract_geoid format from pygris spatial join
SELECT DISTINCT tract_geoid FROM NYC_311.INTERMEDIATE.INT_311_WITH_RESPONSE_TIME LIMIT 3;


-- ============================================================
-- 6. MARTS
-- ============================================================

-- DIM_TRACT: row count (expect ~2168) and geoid format
SELECT COUNT(*) FROM NYC_311.MARTS.DIM_TRACT;
SELECT DISTINCT tract_geoid FROM NYC_311.MARTS.DIM_TRACT LIMIT 3;

-- FCT_REQUEST_RESPONSE_TIME: row count (expect > 0)
SELECT COUNT(*) FROM NYC_311.MARTS.FCT_REQUEST_RESPONSE_TIME;

-- FCT_EQUITY_SPLITS: row count (expect > 0)
SELECT COUNT(*) FROM NYC_311.MARTS.FCT_EQUITY_SPLITS;

-- Distinct complaint types in mart
SELECT COUNT(DISTINCT complaint_type) FROM NYC_311.MARTS.FCT_EQUITY_SPLITS;
SELECT DISTINCT complaint_type FROM NYC_311.MARTS.FCT_EQUITY_SPLITS ORDER BY 1;

-- Top 10 complaint types by average equity score
SELECT complaint_type, AVG(equity_score) AS avg_score
FROM NYC_311.MARTS.FCT_EQUITY_SPLITS
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- city_p90 and equity score sanity check
SELECT complaint_type, AVG(city_p90), AVG(equity_score)
FROM MARTS.FCT_EQUITY_SPLITS
GROUP BY complaint_type
ORDER BY AVG(equity_score) DESC
LIMIT 10;

-- Equity score distribution (should cluster around 1.0)
SELECT
    ROUND(equity_score, 1) AS score_bucket,
    COUNT(*) AS tract_months
FROM MARTS.FCT_EQUITY_SPLITS
GROUP BY 1
ORDER BY 1;

-- Date range for income quintiles 1 and 5
SELECT MIN(request_month), MAX(request_month)
FROM MARTS.FCT_EQUITY_SPLITS
WHERE income_quintile IN (1, 5);


-- ============================================================
-- 7. AI SYNTHESIS
-- ============================================================

DROP TABLE MARTS.AI_SYNTHESIS_CACHE;

CREATE TABLE IF NOT EXISTS MARTS.AI_SYNTHESIS_CACHE (
    data_hash      VARCHAR PRIMARY KEY,
    status         VARCHAR DEFAULT 'pending',
    synthesis_text VARCHAR,
    generated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SELECT * FROM MARTS.AI_SYNTHESIS_CACHE;
