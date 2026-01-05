import { useEffect } from 'react';
import { useAuth } from "react-oidc-context";
import { BrowserRouter, Routes, Route, Navigate, Outlet } from "react-router-dom";
import { setAuthToken } from './api';
import Dashboard from './components/Dashboard';
import Quiz from './components/Quiz';
import LandingPage from './components/LandingPage';
import LoginPage from './components/LoginPage';
import Layout from './components/Layout';

// Wrapper for protected routes
const ProtectedRoute = () => {
    const auth = useAuth();

    if (auth.isLoading) {
        return <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>Loading Mission Control...</div>;
    }

    if (auth.error) {
        return <div>Oops... {auth.error.message}</div>;
    }

    if (!auth.isAuthenticated) {
        return <Navigate to="/" replace />;
    }

    return (
        <Layout>
            <Outlet />
        </Layout>
    );
};

function App() {
    const auth = useAuth();

    useEffect(() => {
        if (auth.isAuthenticated) {
            setAuthToken(auth.user!);
        } else {
            setAuthToken(null);
        }
    }, [auth.isAuthenticated, auth.user]);

    return (
        <BrowserRouter>
            <Routes>
                {/* Public Routes */}
                <Route path="/" element={
                    auth.isAuthenticated ? <Navigate to="/dashboard" /> : <LandingPage />
                } />
                <Route path="/login" element={
                    auth.isAuthenticated ? <Navigate to="/dashboard" /> : <LoginPage />
                } />

                {/* Protected Routes */}
                <Route element={<ProtectedRoute />}>
                    <Route path="/dashboard" element={<Dashboard />} />
                    <Route path="/quiz/:stageId" element={<Quiz />} />
                </Route>

                {/* Catch all */}
                <Route path="*" element={<Navigate to="/" />} />
            </Routes>
        </BrowserRouter>
    );
}

export default App;
