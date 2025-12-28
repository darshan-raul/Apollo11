import streamlit as st
import pandas as pd
import plotly.express as px
import os
from sqlalchemy import create_engine
import redis
import time

# Config
st.set_page_config(page_title="Apollo 11 Admin", layout="wide", page_icon="🚀")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable")
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")

# Styles
st.markdown("""
<style>
    .reportview-container {
        background: #050510;
        color: white;
    }
    .metric-card {
        background-color: rgba(255,255,255,0.05);
        padding: 20px;
        border-radius: 10px;
        border: 1px solid rgba(0,240,255,0.2);
    }
</style>
""", unsafe_allow_html=True)

# Data Connections
@st.cache_resource
def get_engine():
    return create_engine(DATABASE_URL)

def get_redis():
    return redis.from_url(REDIS_URL)

engine = get_engine()
r = get_redis()

st.title("🚀 Apollo 11 Mission Control (Admin)")

# Sidebar
st.sidebar.header("System Status")
try:
    if r.ping():
        st.sidebar.success("Redis: ONLINE")
except:
    st.sidebar.error("Redis: OFFLINE")

try:
    with engine.connect() as conn:
        st.sidebar.success("Database: ONLINE")
except:
    st.sidebar.error("Database: OFFLINE")

# Live Refresh
if st.sidebar.button("Refresh Data"):
    st.cache_data.clear()

st.sidebar.markdown("---")

# Metrics
col1, col2, col3 = st.columns(3)

with col1:
    try:
        user_count = pd.read_sql("SELECT COUNT(*) FROM users", engine).iloc[0, 0]
        st.metric("Total Cadets", user_count)
    except:
        st.metric("Total Cadets", "N/A")

with col2:
    try:
        sim_count = pd.read_sql("SELECT COUNT(*) FROM simulation_logs", engine).iloc[0, 0]
        st.metric("Total Simulations Run", sim_count)
    except:
         st.metric("Total Simulations Run", "N/A")

with col3:
    try:
        success_rate = pd.read_sql("SELECT count(*) FROM simulation_logs WHERE result='success'", engine).iloc[0,0]
        total = pd.read_sql("SELECT count(*) FROM simulation_logs", engine).iloc[0,0]
        rate = (success_rate / total * 100) if total > 0 else 0
        st.metric("Global Success Rate", f"{rate:.1f}%")
    except:
        st.metric("Global Success Rate", "N/A")

# Charts
c1, c2 = st.columns(2)

with c1:
    st.subheader("Stage Pass/Fail Rates")
    try:
        df_stages = pd.read_sql("""
            SELECT stage_id, result, count(*) as count 
            FROM simulation_logs 
            GROUP BY stage_id, result
        """, engine)
        if not df_stages.empty:
            fig = px.bar(df_stages, x="stage_id", y="count", color="result", barmode="group",
                         color_discrete_map={"success": "#00ff88", "failure": "#ff0055"})
            fig.update_layout(paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)", font_color="white")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No data available")
    except Exception as e:
        st.error(f"Error loading charts: {e}")

with c2:
    st.subheader("Simulations Over Time")
    try:
        df_time = pd.read_sql("""
            SELECT date_trunc('hour', timestamp) as time, count(*) as count 
            FROM simulation_logs 
            GROUP BY 1 
            ORDER BY 1 DESC LIMIT 24
        """, engine)
        if not df_time.empty:
            fig2 = px.line(df_time, x="time", y="count", markers=True)
            fig2.update_traces(line_color="#00f0ff")
            fig2.update_layout(paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)", font_color="white")
            st.plotly_chart(fig2, use_container_width=True)
        else:
            st.info("No data available")
    except:
        st.error("Error loading timeline")

# Recent Logs
st.subheader("Live Telemetry Logs")
try:
    df_logs = pd.read_sql("SELECT * FROM simulation_logs ORDER BY timestamp DESC LIMIT 10", engine)
    st.dataframe(df_logs)
except:
    st.text("No logs found.")
