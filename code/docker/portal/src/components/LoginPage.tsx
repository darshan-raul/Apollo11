import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';

const LoginPage: React.FC = () => {
    const { login } = useAuth();
    const navigate = useNavigate();
    const [isLoading, setIsLoading] = useState(false);
    const [username, setUsername] = useState('commander@apollo11.com');
    const [password, setPassword] = useState('password');

    const handleLogin = (e: React.FormEvent) => {
        e.preventDefault();
        setIsLoading(true);
        // Simulate network delay
        setTimeout(() => {
            login(username);
            setIsLoading(false);
            navigate('/dashboard');
        }, 800);
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

                <form onSubmit={handleLogin}>
                    <div style={{ textAlign: 'left', marginBottom: '1.5rem' }}>
                        <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>Username</label>
                        <input
                            type="text"
                            value={username}
                            onChange={(e) => setUsername(e.target.value)}
                            style={{
                                width: '100%',
                                padding: '0.75rem',
                                background: 'rgba(255,255,255,0.05)',
                                border: '1px solid rgba(255,255,255,0.1)',
                                borderRadius: 'var(--radius-sm)',
                                color: 'white'
                            }}
                        />
                    </div>
                    <div style={{ textAlign: 'left', marginBottom: '2rem' }}>
                        <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>Password</label>
                        <input
                            type="password"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            style={{
                                width: '100%',
                                padding: '0.75rem',
                                background: 'rgba(255,255,255,0.05)',
                                border: '1px solid rgba(255,255,255,0.1)',
                                borderRadius: 'var(--radius-sm)',
                                color: 'white'
                            }}
                        />
                    </div>

                    <button
                        type="submit"
                        className="btn btn-primary"
                        disabled={isLoading}
                        style={{ width: '100%', justifyContent: 'center' }}
                    >
                        {isLoading ? 'Connecting...' : 'Log in'}
                    </button>
                </form>

                <div style={{ marginTop: '2rem', fontSize: '0.875rem', color: 'var(--text-secondary)' }}>
                    <a href="/" style={{ color: 'var(--text-secondary)' }}>Back to Home</a>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
