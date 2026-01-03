import { useEffect } from 'react';
import { useAuth } from "react-oidc-context";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { setAuthToken } from './api';
import Dashboard from './components/Dashboard';
import Quiz from './components/Quiz';

function App() {
    const auth = useAuth();

    useEffect(() => {
        if (auth.isAuthenticated) {
            setAuthToken(auth.user!);
        } else {
            setAuthToken(null);
        }
    }, [auth.isAuthenticated, auth.user]);

    if (auth.isLoading) {
        return <div>Loading...</div>;
    }

    if (auth.error) {
        return <div>Oops... {auth.error.message}</div>;
    }

    if (!auth.isAuthenticated) {
        return (
            <div style={{ textAlign: 'center', marginTop: '50px' }}>
                <h1>Welcome to Apollo 11</h1>
                <p>Your journey begins here.</p>
                <button onClick={() => auth.signinRedirect()}>Log in to Liftoff</button>
            </div>
        );
    }

    return (
        <BrowserRouter>
            <div style={{ padding: '20px' }}>
                <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                    <h1>Apollo 11 Mission Control</h1>
                    <div>
                        <span>Welcome, {auth.user?.profile.preferred_username}</span>
                        <button onClick={() => auth.removeUser()} style={{ marginLeft: '10px' }}>Sign out</button>
                    </div>
                </header>
                <Routes>
                    <Route path="/" element={<Navigate to="/dashboard" />} />
                    <Route path="/dashboard" element={<Dashboard />} />
                    <Route path="/quiz/:stageId" element={<Quiz />} />
                </Routes>
            </div>
        </BrowserRouter>
    );
}

export default App;
