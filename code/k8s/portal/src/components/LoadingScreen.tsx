import React from 'react';

const LoadingScreen: React.FC<{ message?: string }> = ({ message = "Initializing Mission Control..." }) => {
    return (
        <div style={{
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
            alignItems: 'center',
            height: '100vh',
            background: 'radial-gradient(circle at center, #1b2735 0%, #090a0f 100%)',
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-family)'
        }}>
            <div style={{
                width: '60px',
                height: '60px',
                border: '4px solid rgba(59, 130, 246, 0.3)',
                borderTop: '4px solid var(--accent-primary)',
                borderRadius: '50%',
                animation: 'spin 1s linear infinite',
                marginBottom: '1.5rem'
            }}></div>
            <h2 style={{
                fontSize: '1.5rem',
                fontWeight: 600,
                letterSpacing: '0.05em',
                background: 'linear-gradient(to right, #fff, #94a3b8)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                marginBottom: '0.5rem'
            }}>
                APOLLO 11
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', letterSpacing: '0.05em' }}>
                {message.toUpperCase()}
            </p>
            <style>{`
                @keyframes spin {
                    0% { transform: rotate(0deg); }
                    100% { transform: rotate(360deg); }
                }
            `}</style>
        </div>
    );
};

export default LoadingScreen;
