"""
Apollo 11 Astronaut Onboarding Admin Dashboard
Streamlit application for monitoring and analytics
"""
import os
import sys
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import streamlit as st
from datetime import datetime, timedelta
import psycopg2
from sqlalchemy import create_engine, text
import redis
import requests
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://apollo11:apollo11@postgres:5432/apollo11")
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")
CORE_API_URL = os.getenv("CORE_API_URL", "http://core-api:8080")

# Page configuration
st.set_page_config(
    page_title="Apollo 11 Admin Dashboard",
    page_icon="🚀",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
<style>
    .main-header {
        background: linear-gradient(90deg, #1e3c72 0%, #2a5298 100%);
        padding: 1rem;
        border-radius: 10px;
        color: white;
        text-align: center;
        margin-bottom: 2rem;
    }
    .metric-card {
        background: white;
        padding: 1rem;
        border-radius: 10px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        border-left: 4px solid #1e3c72;
    }
    .success-metric {
        border-left-color: #28a745;
    }
    .warning-metric {
        border-left-color: #ffc107;
    }
    .danger-metric {
        border-left-color: #dc3545;
    }
    .info-metric {
        border-left-color: #17a2b8;
    }
</style>
""", unsafe_allow_html=True)

# Database connection
@st.cache_resource
def get_database_connection():
    """Get database connection"""
    try:
        engine = create_engine(DATABASE_URL)
        return engine
    except Exception as e:
        st.error(f"Failed to connect to database: {e}")
        return None

# Redis connection
@st.cache_resource
def get_redis_connection():
    """Get Redis connection"""
    try:
        r = redis.from_url(REDIS_URL)
        r.ping()
        return r
    except Exception as e:
        st.error(f"Failed to connect to Redis: {e}")
        return None

# Database queries
def get_user_stats(engine):
    """Get user statistics"""
    query = """
    SELECT 
        COUNT(*) as total_users,
        COUNT(CASE WHEN is_active THEN 1 END) as active_users,
        COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as new_users_week,
        COUNT(CASE WHEN created_at >= NOW() - INTERVAL '30 days' THEN 1 END) as new_users_month
    FROM users
    """
    return pd.read_sql(query, engine)

def get_stage_progress_stats(engine):
    """Get stage progress statistics"""
    query = """
    SELECT 
        s.id as stage_id,
        s.name as stage_name,
        COUNT(sp.id) as total_attempts,
        COUNT(CASE WHEN sp.status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN sp.status = 'failed' THEN 1 END) as failed,
        COUNT(CASE WHEN sp.status = 'in_progress' THEN 1 END) as in_progress,
        COUNT(CASE WHEN sp.status = 'available' THEN 1 END) as available,
        COUNT(CASE WHEN sp.status = 'locked' THEN 1 END) as locked,
        ROUND(
            COUNT(CASE WHEN sp.status = 'completed' THEN 1 END) * 100.0 / 
            NULLIF(COUNT(sp.id), 0), 2
        ) as completion_rate
    FROM stages s
    LEFT JOIN stage_progress sp ON s.id = sp.stage_id
    GROUP BY s.id, s.name
    ORDER BY s.id
    """
    return pd.read_sql(query, engine)

def get_user_progress_details(engine):
    """Get detailed user progress"""
    query = """
    SELECT 
        u.id as user_id,
        u.username,
        u.full_name,
        u.created_at as user_created,
        COUNT(sp.id) as total_stages,
        COUNT(CASE WHEN sp.status = 'completed' THEN 1 END) as completed_stages,
        COUNT(CASE WHEN sp.status = 'in_progress' THEN 1 END) as in_progress_stages,
        COUNT(CASE WHEN sp.status = 'failed' THEN 1 END) as failed_stages,
        SUM(sp.attempts) as total_attempts,
        MAX(sp.updated_at) as last_activity,
        ROUND(
            COUNT(CASE WHEN sp.status = 'completed' THEN 1 END) * 100.0 / 
            NULLIF(COUNT(sp.id), 0), 2
        ) as completion_percentage
    FROM users u
    LEFT JOIN stage_progress sp ON u.id = sp.user_id
    WHERE u.is_active = true
    GROUP BY u.id, u.username, u.full_name, u.created_at
    ORDER BY completion_percentage DESC, last_activity DESC
    """
    return pd.read_sql(query, engine)

def get_simulation_logs(engine, days=7):
    """Get simulation logs for the last N days"""
    query = """
    SELECT 
        sl.*,
        u.username,
        u.full_name,
        s.name as stage_name
    FROM simulation_logs sl
    JOIN users u ON sl.user_id = u.id
    JOIN stages s ON sl.stage_id = s.id
    WHERE sl.timestamp >= NOW() - INTERVAL '%s days'
    ORDER BY sl.timestamp DESC
    """ % days
    return pd.read_sql(query, engine)

def get_daily_activity(engine, days=30):
    """Get daily activity statistics"""
    query = """
    SELECT 
        DATE(sl.timestamp) as date,
        COUNT(*) as total_simulations,
        COUNT(CASE WHEN sl.result = 'success' THEN 1 END) as successful_simulations,
        COUNT(CASE WHEN sl.result = 'failure' THEN 1 END) as failed_simulations,
        COUNT(DISTINCT sl.user_id) as active_users
    FROM simulation_logs sl
    WHERE sl.timestamp >= NOW() - INTERVAL '%s days'
    GROUP BY DATE(sl.timestamp)
    ORDER BY date
    """ % days
    return pd.read_sql(query, engine)

# Main dashboard
def main():
    # Header
    st.markdown("""
    <div class="main-header">
        <h1>🚀 Apollo 11 Astronaut Onboarding Admin Dashboard</h1>
        <p>Real-time monitoring and analytics for the astronaut training program</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Get database connection
    engine = get_database_connection()
    if not engine:
        st.error("Cannot connect to database. Please check your connection.")
        return
    
    # Sidebar
    st.sidebar.title("📊 Dashboard Controls")
    
    # Time range selector
    time_range = st.sidebar.selectbox(
        "Select Time Range",
        ["Last 7 days", "Last 30 days", "Last 90 days", "All time"],
        index=1
    )
    
    days_map = {
        "Last 7 days": 7,
        "Last 30 days": 30,
        "Last 90 days": 90,
        "All time": 365
    }
    selected_days = days_map[time_range]
    
    # Refresh button
    if st.sidebar.button("🔄 Refresh Data"):
        st.cache_data.clear()
        st.rerun()
    
    # System status
    st.sidebar.markdown("### 🔧 System Status")
    
    # Check Redis connection
    redis_conn = get_redis_connection()
    if redis_conn:
        st.sidebar.success("✅ Redis Connected")
    else:
        st.sidebar.error("❌ Redis Disconnected")
    
    # Check Core API
    try:
        response = requests.get(f"{CORE_API_URL}/health", timeout=5)
        if response.status_code == 200:
            st.sidebar.success("✅ Core API Connected")
        else:
            st.sidebar.error("❌ Core API Error")
    except:
        st.sidebar.error("❌ Core API Disconnected")
    
    # Main content
    tab1, tab2, tab3, tab4 = st.tabs(["📈 Overview", "👥 Users", "🎯 Stages", "📊 Analytics"])
    
    with tab1:
        show_overview_tab(engine, selected_days)
    
    with tab2:
        show_users_tab(engine)
    
    with tab3:
        show_stages_tab(engine)
    
    with tab4:
        show_analytics_tab(engine, selected_days)

def show_overview_tab(engine, days):
    """Show overview tab"""
    st.header("📈 System Overview")
    
    # Get user stats
    user_stats = get_user_stats(engine)
    
    # Key metrics
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric(
            label="Total Users",
            value=int(user_stats['total_users'].iloc[0]),
            delta=int(user_stats['new_users_week'].iloc[0])
        )
    
    with col2:
        st.metric(
            label="Active Users",
            value=int(user_stats['active_users'].iloc[0]),
            delta=f"+{int(user_stats['new_users_month'].iloc[0])} this month"
        )
    
    with col3:
        # Get simulation stats
        sim_stats = get_simulation_logs(engine, days)
        total_sims = len(sim_stats)
        success_rate = (sim_stats['result'] == 'success').mean() * 100 if total_sims > 0 else 0
        
        st.metric(
            label="Success Rate",
            value=f"{success_rate:.1f}%",
            delta=f"{total_sims} simulations"
        )
    
    with col4:
        # Get stage completion stats
        stage_stats = get_stage_progress_stats(engine)
        avg_completion = stage_stats['completion_rate'].mean()
        
        st.metric(
            label="Avg Completion",
            value=f"{avg_completion:.1f}%",
            delta="across all stages"
        )
    
    # Charts
    col1, col2 = st.columns(2)
    
    with col1:
        # Daily activity chart
        daily_activity = get_daily_activity(engine, days)
        
        if not daily_activity.empty:
            fig = go.Figure()
            fig.add_trace(go.Scatter(
                x=daily_activity['date'],
                y=daily_activity['total_simulations'],
                mode='lines+markers',
                name='Total Simulations',
                line=dict(color='#1f77b4')
            ))
            fig.add_trace(go.Scatter(
                x=daily_activity['date'],
                y=daily_activity['successful_simulations'],
                mode='lines+markers',
                name='Successful',
                line=dict(color='#2ca02c')
            ))
            
            fig.update_layout(
                title="Daily Simulation Activity",
                xaxis_title="Date",
                yaxis_title="Number of Simulations",
                hovermode='x unified'
            )
            
            st.plotly_chart(fig, use_container_width=True)
    
    with col2:
        # Stage completion rates
        stage_stats = get_stage_progress_stats(engine)
        
        if not stage_stats.empty:
            fig = px.bar(
                stage_stats,
                x='stage_name',
                y='completion_rate',
                title="Stage Completion Rates",
                color='completion_rate',
                color_continuous_scale='Viridis'
            )
            fig.update_layout(
                xaxis_title="Stage",
                yaxis_title="Completion Rate (%)",
                xaxis_tickangle=-45
            )
            st.plotly_chart(fig, use_container_width=True)

def show_users_tab(engine):
    """Show users tab"""
    st.header("👥 User Management")
    
    # Get user progress details
    user_progress = get_user_progress_details(engine)
    
    if not user_progress.empty:
        # User statistics
        col1, col2, col3 = st.columns(3)
        
        with col1:
            avg_completion = user_progress['completion_percentage'].mean()
            st.metric("Average Completion", f"{avg_completion:.1f}%")
        
        with col2:
            total_attempts = user_progress['total_attempts'].sum()
            st.metric("Total Attempts", f"{total_attempts:,}")
        
        with col3:
            active_users = len(user_progress[user_progress['last_activity'].notna()])
            st.metric("Active Users", active_users)
        
        # User progress table
        st.subheader("User Progress Details")
        
        # Format the dataframe for display
        display_df = user_progress.copy()
        display_df['user_created'] = pd.to_datetime(display_df['user_created']).dt.strftime('%Y-%m-%d')
        display_df['last_activity'] = pd.to_datetime(display_df['last_activity']).dt.strftime('%Y-%m-%d %H:%M')
        display_df['completion_percentage'] = display_df['completion_percentage'].round(1)
        
        # Rename columns for better display
        display_df = display_df.rename(columns={
            'user_id': 'ID',
            'username': 'Username',
            'full_name': 'Full Name',
            'user_created': 'Joined',
            'total_stages': 'Total Stages',
            'completed_stages': 'Completed',
            'in_progress_stages': 'In Progress',
            'failed_stages': 'Failed',
            'total_attempts': 'Total Attempts',
            'last_activity': 'Last Activity',
            'completion_percentage': 'Completion %'
        })
        
        st.dataframe(
            display_df,
            use_container_width=True,
            hide_index=True
        )
        
        # User progress chart
        st.subheader("User Completion Distribution")
        
        fig = px.histogram(
            user_progress,
            x='completion_percentage',
            nbins=20,
            title="Distribution of User Completion Rates",
            labels={'completion_percentage': 'Completion Percentage (%)', 'count': 'Number of Users'}
        )
        st.plotly_chart(fig, use_container_width=True)
    
    else:
        st.info("No user data available.")

def show_stages_tab(engine):
    """Show stages tab"""
    st.header("🎯 Stage Analytics")
    
    # Get stage progress stats
    stage_stats = get_stage_progress_stats(engine)
    
    if not stage_stats.empty:
        # Stage overview
        col1, col2, col3, col4 = st.columns(4)
        
        with col1:
            total_attempts = stage_stats['total_attempts'].sum()
            st.metric("Total Attempts", f"{total_attempts:,}")
        
        with col2:
            total_completed = stage_stats['completed'].sum()
            st.metric("Total Completed", f"{total_completed:,}")
        
        with col3:
            total_failed = stage_stats['failed'].sum()
            st.metric("Total Failed", f"{total_failed:,}")
        
        with col4:
            avg_completion = stage_stats['completion_rate'].mean()
            st.metric("Avg Completion Rate", f"{avg_completion:.1f}%")
        
        # Stage details table
        st.subheader("Stage Performance Details")
        
        # Format dataframe
        display_df = stage_stats.copy()
        display_df['completion_rate'] = display_df['completion_rate'].round(1)
        
        # Rename columns
        display_df = display_df.rename(columns={
            'stage_id': 'Stage ID',
            'stage_name': 'Stage Name',
            'total_attempts': 'Total Attempts',
            'completed': 'Completed',
            'failed': 'Failed',
            'in_progress': 'In Progress',
            'available': 'Available',
            'locked': 'Locked',
            'completion_rate': 'Completion Rate (%)'
        })
        
        st.dataframe(
            display_df,
            use_container_width=True,
            hide_index=True
        )
        
        # Stage completion chart
        st.subheader("Stage Completion Analysis")
        
        col1, col2 = st.columns(2)
        
        with col1:
            # Completion rate by stage
            fig = px.bar(
                stage_stats,
                x='stage_name',
                y='completion_rate',
                title="Completion Rate by Stage",
                color='completion_rate',
                color_continuous_scale='RdYlGn'
            )
            fig.update_layout(
                xaxis_title="Stage",
                yaxis_title="Completion Rate (%)",
                xaxis_tickangle=-45
            )
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            # Attempts vs completions
            fig = go.Figure()
            fig.add_trace(go.Bar(
                name='Total Attempts',
                x=stage_stats['stage_name'],
                y=stage_stats['total_attempts'],
                marker_color='lightblue'
            ))
            fig.add_trace(go.Bar(
                name='Completed',
                x=stage_stats['stage_name'],
                y=stage_stats['completed'],
                marker_color='green'
            ))
            fig.add_trace(go.Bar(
                name='Failed',
                x=stage_stats['stage_name'],
                y=stage_stats['failed'],
                marker_color='red'
            ))
            
            fig.update_layout(
                title="Attempts vs Completions by Stage",
                xaxis_title="Stage",
                yaxis_title="Count",
                barmode='group',
                xaxis_tickangle=-45
            )
            st.plotly_chart(fig, use_container_width=True)
    
    else:
        st.info("No stage data available.")

def show_analytics_tab(engine, days):
    """Show analytics tab"""
    st.header("📊 Advanced Analytics")
    
    # Get simulation logs
    sim_logs = get_simulation_logs(engine, days)
    
    if not sim_logs.empty:
        # Simulation trends
        st.subheader("Simulation Trends")
        
        # Convert timestamp to datetime
        sim_logs['date'] = pd.to_datetime(sim_logs['timestamp']).dt.date
        sim_logs['hour'] = pd.to_datetime(sim_logs['timestamp']).dt.hour
        
        col1, col2 = st.columns(2)
        
        with col1:
            # Daily simulation trends
            daily_trends = sim_logs.groupby(['date', 'result']).size().unstack(fill_value=0)
            
            fig = go.Figure()
            if 'success' in daily_trends.columns:
                fig.add_trace(go.Scatter(
                    x=daily_trends.index,
                    y=daily_trends['success'],
                    mode='lines+markers',
                    name='Successful',
                    line=dict(color='green')
                ))
            if 'failure' in daily_trends.columns:
                fig.add_trace(go.Scatter(
                    x=daily_trends.index,
                    y=daily_trends['failure'],
                    mode='lines+markers',
                    name='Failed',
                    line=dict(color='red')
                ))
            
            fig.update_layout(
                title="Daily Simulation Results",
                xaxis_title="Date",
                yaxis_title="Number of Simulations"
            )
            st.plotly_chart(fig, use_container_width=True)
        
        with col2:
            # Hourly activity
            hourly_activity = sim_logs.groupby('hour').size()
            
            fig = px.bar(
                x=hourly_activity.index,
                y=hourly_activity.values,
                title="Activity by Hour of Day",
                labels={'x': 'Hour', 'y': 'Number of Simulations'}
            )
            st.plotly_chart(fig, use_container_width=True)
        
        # Stage performance analysis
        st.subheader("Stage Performance Analysis")
        
        stage_performance = sim_logs.groupby(['stage_name', 'result']).size().unstack(fill_value=0)
        stage_performance['success_rate'] = (stage_performance.get('success', 0) / 
                                           (stage_performance.get('success', 0) + stage_performance.get('failure', 0)) * 100)
        
        fig = px.bar(
            x=stage_performance.index,
            y=stage_performance['success_rate'],
            title="Success Rate by Stage",
            labels={'x': 'Stage', 'y': 'Success Rate (%)'}
        )
        fig.update_layout(xaxis_tickangle=-45)
        st.plotly_chart(fig, use_container_width=True)
        
        # Recent activity
        st.subheader("Recent Activity")
        
        recent_activity = sim_logs.head(20)[['timestamp', 'username', 'stage_name', 'result', 'message']]
        recent_activity['timestamp'] = pd.to_datetime(recent_activity['timestamp']).dt.strftime('%Y-%m-%d %H:%M:%S')
        
        st.dataframe(
            recent_activity,
            use_container_width=True,
            hide_index=True
        )
    
    else:
        st.info("No simulation data available for the selected time range.")

if __name__ == "__main__":
    main()
