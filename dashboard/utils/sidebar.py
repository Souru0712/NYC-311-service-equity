import streamlit as st


_PAGE_DESCRIPTIONS = {
    "Borough Map":              "Census-tract choropleth — equity score by complaint type or income quintile",
    "Equity By Income":         "Q1 vs Q5 response time gap for a specific complaint type",
    "Complaint Type Breakdown": "P90 / P50 / volume heatmap across all complaint types and boroughs",
    "Agency Breakdown":         "Equity gap and request volume grouped by responsible city agency",
    "Key Findings":             "Top gaps, borough heatmap, trend, and AI-generated synthesis",
}


def setup_sidebar() -> None:
    """Render last-refresh timestamp and page guide in the sidebar."""
    from utils.snowflake_conn import get_last_refresh

    with st.sidebar:
        st.divider()
        last = get_last_refresh()
        st.caption(f"🕐 **Data last refreshed:** {last} UTC")
        st.divider()
        st.caption("**Pages**")
        for page, desc in _PAGE_DESCRIPTIONS.items():
            st.caption(f"**{page}** — {desc}")
