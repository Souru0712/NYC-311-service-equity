"""Watermark-based incremental load: Socrata → S3 → Snowflake → dbt.

Called by the GitHub Actions scheduled pipeline. Reads MAX(resolution_action_updated_date)
from Snowflake (minus 48 h buffer) to determine where to start fetching.

Run from the project root:
    python scripts/run_incremental.py
"""
import sys
from datetime import datetime, timezone

import pandas as pd

sys.path.insert(0, ".")

from ingestion.config import Config
from ingestion.s3_writer import write_parquet_to_s3
from ingestion.snowflake_loader import copy_311_from_s3, create_raw_311_table, get_connection
from ingestion.socrata_client import fetch_incremental, get_watermark, records_to_dataframe
from ingestion.tract_geometry import assign_tract_geoid, download_tract_geojson


def main() -> None:
    cfg = Config()

    # ── 1. Get watermark from Snowflake ──────────────────────────────────────
    sf_conn = get_connection(cfg)
    create_raw_311_table(sf_conn)
    watermark = get_watermark(sf_conn)
    print(f"Watermark: {watermark.isoformat()} (48 h buffer applied)")

    # ── 2. Fetch from Socrata since watermark ─────────────────────────────────
    frames = []
    for batch in fetch_incremental(cfg.socrata_app_token, cfg.socrata_dataset_id, watermark):
        frames.append(records_to_dataframe(batch))

    if not frames:
        print("No new records since watermark — nothing to load.")
        sf_conn.close()
        sys.exit(0)

    df = pd.concat(frames, ignore_index=True)
    print(f"Fetched {len(df):,} rows")

    # ── 3. Spatial join ───────────────────────────────────────────────────────
    tracts = download_tract_geojson(cfg.tract_geojson_cache)
    df = assign_tract_geoid(df, tracts)
    coverage = df["tract_geoid"].notna().mean()
    print(f"tract_geoid coverage: {coverage:.1%}")

    # ── 4. Write to S3 ────────────────────────────────────────────────────────
    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    s3_uri = write_parquet_to_s3(
        df,
        bucket=cfg.s3_bucket,
        prefix="raw/socrata_311",
        run_date=run_date,
        aws_access_key=cfg.aws_access_key,
        aws_secret_key=cfg.aws_secret_key,
        aws_region=cfg.aws_region,
    )
    print(f"Written to: {s3_uri}")

    # ── 5. COPY INTO Snowflake ────────────────────────────────────────────────
    copy_311_from_s3(sf_conn, s3_uri, cfg.snowflake_stage)
    sf_conn.close()
    print(f"Loaded {len(df):,} rows into Snowflake")


if __name__ == "__main__":
    main()
