import streamlit as st


def is_dev() -> bool:
    """Returns True when DEV_MODE=true is set as a top-level key in st.secrets.
    Must appear above any [section] headers in the secrets file.
    On Streamlit Cloud, omit DEV_MODE entirely so public users never see dev controls.
    Locally, set DEV_MODE = 'true' in .streamlit/secrets.toml.
    """
    try:
        return str(st.secrets["DEV_MODE"]).lower() == "true"
    except Exception:
        return False
