
import React, { ReactNode } from 'react';
import { useAuth } from "../context/AuthContext";
import { Link } from "react-router-dom";

interface LayoutProps {
    children: ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
    const { user, logout } = useAuth();

    return (
        <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
            <header style={{
                background: 'var(--bg-secondary)',
                borderBottom: '1px solid rgba(255, 255, 255, 0.05)',
                padding: '1rem 0'
            }}>
                <div className="container" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Link to="/dashboard" style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text-primary)' }}>
                        Apollo<span style={{ color: 'var(--accent-primary)' }}>11</span> <span style={{ opacity: 0.5, fontWeight: 400 }}>Mission Control</span>
                    </Link>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                        <div className="desktop-only" style={{ textAlign: 'right' }}>
                            <span style={{ display: 'block', fontSize: '0.875rem', fontWeight: 600 }}>
                                {user?.username || "Commander"}
                            </span>
                        </div>
                        <button
                            className="btn btn-secondary"
                            onClick={() => logout()}
                            style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}
                        >
                            Sign Out
                        </button>
                    </div>
                </div>
            </header>

            <main className="container" style={{ flex: 1, padding: '2rem var(--spacing-sm)' }}>
                {children}
            </main>
        </div>
    );
};

export default Layout;
