import pandas as pd
import snowflake.connector
import streamlit as st


@st.cache_resource
def get_snowflake_conn():
    """One Snowflake connection per Streamlit session. Reads from st.secrets."""
    return snowflake.connector.connect(
        user=st.secrets["snowflake"]["user"],
        password=st.secrets["snowflake"]["password"],
        account=st.secrets["snowflake"]["account"],
        warehouse=st.secrets["snowflake"]["warehouse"],
        database="NYC_311",
        schema="MARTS",
        role=st.secrets["snowflake"]["role"],
    )


@st.cache_data(ttl=3600, show_spinner=False)
def run_query(sql: str) -> pd.DataFrame:
    conn = get_snowflake_conn()
    df = pd.read_sql(sql, conn)
    # Snowflake returns uppercase column names — lowercase them for consistent
    # access in all dashboard pages (e.g. df["complaint_type"] not df["COMPLAINT_TYPE"])
    df.columns = [c.lower() for c in df.columns]
    return df


@st.cache_data(ttl=3600, show_spinner=False)
def get_last_refresh() -> str:
    """Return the latest ingestion timestamp from RAW.SOCRATA_311 as a formatted string."""
    try:
        df = run_query("SELECT MAX(ingestion_timestamp) AS ts FROM RAW.SOCRATA_311")
        ts = df["ts"].iloc[0]
        if ts is None:
            return "Unknown"
        return str(ts)[:16]
    except Exception:
        return "Unknown"
