
import React from 'react';
import { useAuth } from "react-oidc-context";
// We will assume the image is in the public folder or reachable via relative path. 
// Based on current location: codebase/portal/apollobanner.png. 
// Vite public assets usually go in 'public' dir or imported. 
// If it's in root 'code/portal/', we might need to move it or import it if configured.
// For now, let's assume we can import it if it's in src or ../
// Let's rely on standard Vite asset handling, best to put images in `src/assets` or `public`.
// Checking file listing: apollobanner.png is in code/portal/ (root of vite project).
// In Vite, files in project root are not automatically served as static assets unless in public.
// I will need to move these images to a better location later, or import them relatively if possible.
// For this component, I'll assume they will be moved to `src/assets` or linked correctly.
// I will handle the "move" step in the next tool call.

const LandingPage: React.FC = () => {
    const auth = useAuth();

    return (
        <div className="landing-page" style={{
            minHeight: '100vh',
            background: 'var(--bg-primary)',
            display: 'flex',
            flexDirection: 'column'
        }}>
            {/* Header / Nav */}
            <nav className="glass-panel" style={{
                position: 'fixed',
                top: 0,
                width: '100%',
                zIndex: 100,
                padding: '1rem 0',
                borderBottom: '1px solid rgba(255,255,255,0.05)'
            }}>
                <div className="container" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div className="logo" style={{ fontSize: '1.5rem', fontWeight: 700, letterSpacing: '-0.5px' }}>
                        Apollo<span style={{ color: 'var(--accent-primary)' }}>11</span>
                    </div>
                    {/* Placeholder for Login if we want it in nav, but request says "login page" */}
                </div>
            </nav>

            {/* Hero Section */}
            <main style={{ flex: 1, paddingTop: '80px', display: 'flex', alignItems: 'center', position: 'relative' }}>
                <div className="background-glow" style={{
                    position: 'absolute',
                    top: '20%',
                    right: '10%',
                    width: '400px',
                    height: '400px',
                    background: 'var(--accent-primary)',
                    filter: 'blur(150px)',
                    opacity: 0.15,
                    borderRadius: '50%',
                    zIndex: 0
                }}></div>

                <div className="container" style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '4rem', zIndex: 1, position: 'relative' }}>

                    {/* Text Content */}
                    <div className="hero-content fade-in" style={{ flex: '1 1 500px', minWidth: '300px' }}>
                        <h1 style={{ marginBottom: '1.5rem', fontSize: 'clamp(2.5rem, 5vw, 4.5rem)' }}>
                            Launch Your <br />
                            <span style={{
                                background: 'var(--accent-gradient)',
                                WebkitBackgroundClip: 'text',
                                WebkitTextFillColor: 'transparent'
                            }}>Kubernetes Journey</span>
                        </h1>
                        <p style={{
                            fontSize: '1.25rem',
                            color: 'var(--text-secondary)',
                            marginBottom: '2.5rem',
                            maxWidth: '600px',
                            lineHeight: 1.6
                        }}>
                            Master container orchestration with hands-on missions.
                            From local pods to production-grade clusters, Apollo 11 is your mission control.
                        </p>
                        <div className="actions">
                            <button
                                className="btn btn-primary"
                                onClick={() => auth.signinRedirect()}
                                style={{ minWidth: '160px' }}
                            >
                                Start Mission
                            </button>
                            <button
                                className="btn btn-secondary"
                                style={{ marginLeft: '1rem' }}
                            >
                                Learn More
                            </button>
                        </div>
                    </div>

                    {/* Image / Visual */}
                    <div className="hero-image fade-in" style={{ flex: '1 1 400px', display: 'flex', justifyContent: 'center' }}>
                        <div className="image-wrapper" style={{
                            position: 'relative',
                            borderRadius: '24px',
                            overflow: 'hidden',
                            boxShadow: '0 20px 50px rgba(0,0,0,0.5)',
                            border: '1px solid rgba(255,255,255,0.1)'
                        }}>
                            {/* We will place the banner here. Assuming path. */}
                            <img
                                src="/apollobanner.png"
                                alt="Apollo 11 Dashboard Preview"
                                style={{ width: '100%', height: 'auto', display: 'block', maxWidth: '600px' }}
                            />
                            <div className="overlay" style={{
                                position: 'absolute',
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: '50%',
                                background: 'linear-gradient(to top, rgba(11,14,20, 0.8), transparent)'
                            }}></div>
                        </div>
                    </div>
                </div>
            </main>

            {/* Footer */}
            <footer style={{
                borderTop: '1px solid rgba(255,255,255,0.05)',
                padding: '2rem 0',
                marginTop: 'auto'
            }}>
                <div className="container" style={{ textAlign: 'center', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>
                    &copy; {new Date().getFullYear()} Apollo 11 Project. Open source Kubernetes learning platform.
                </div>
            </footer>
        </div>
    );
};

export default LandingPage;
