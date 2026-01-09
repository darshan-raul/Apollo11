
import React, { useState } from 'react';
import { useAuth } from "react-oidc-context";

const LoginPage: React.FC = () => {
    const auth = useAuth();
    const [isLoading, setIsLoading] = useState(false);

    const handleLogin = () => {
        setIsLoading(true);
        auth.signinRedirect().catch(() => setIsLoading(false));
    };

    return (
        <div style={{
            minHeight: '100vh',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'var(--bg-primary)',
            backgroundImage: 'radial-gradient(circle at 50% 50%, #151A23 0%, #0B0E14 100%)',
            padding: '1rem'
        }}>
            <div className="glass-panel fade-in" style={{
                width: '100%',
                maxWidth: '400px',
                padding: '3rem 2rem',
                textAlign: 'center',
                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)'
            }}>
                <div style={{ marginBottom: '2rem' }}>
                    <h1 style={{ fontSize: '2rem', marginBottom: '0.5rem' }}>Mission Control</h1>
                    <p style={{ color: 'var(--text-secondary)' }}>Identify yourself to proceed</p>
                </div>

                {/* Simulated Form Fields for Visuals - as Auth is OIDC Redirect */}
                <div style={{ textAlign: 'left', marginBottom: '1.5rem', opacity: 0.6, pointerEvents: 'none' }}>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>Username</label>
                    <input type="text" disabled placeholder="commander@apollo11.com" style={{
                        width: '100%',
                        padding: '0.75rem',
                        background: 'rgba(255,255,255,0.05)',
                        border: '1px solid rgba(255,255,255,0.1)',
                        borderRadius: 'var(--radius-sm)',
                        color: 'white'
                    }} />
                </div>
                <div style={{ textAlign: 'left', marginBottom: '2rem', opacity: 0.6, pointerEvents: 'none' }}>
                    <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>Password</label>
                    <input type="password" disabled placeholder="••••••••" style={{
                        width: '100%',
                        padding: '0.75rem',
                        background: 'rgba(255,255,255,0.05)',
                        border: '1px solid rgba(255,255,255,0.1)',
                        borderRadius: 'var(--radius-sm)',
                        color: 'white'
                    }} />
                </div>

                <button
                    className="btn btn-primary"
                    onClick={handleLogin}
                    disabled={isLoading}
                    style={{ width: '100%', justifyContent: 'center' }}
                >
                    {isLoading ? 'Connecting...' : 'Log in via SSO'}
                </button>

                <div style={{ marginTop: '2rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>
                    <a href="/" style={{ color: 'var(--text-secondary)' }}>Back to Home</a>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
