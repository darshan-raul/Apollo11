import { useEffect, useState } from 'react';
import { useAuth } from "react-oidc-context";
import { BrowserRouter, Routes, Route, Navigate, Outlet } from "react-router-dom";
import { setAuthToken } from './api';
import Dashboard from './components/Dashboard';
import Quiz from './components/Quiz';
import LandingPage from './components/LandingPage';
import LoginPage from './components/LoginPage';
import Layout from './components/Layout';
import LoadingScreen from './components/LoadingScreen';

// Wrapper for protected routes
const ProtectedRoute = () => {
    const auth = useAuth();

    if (auth.isLoading) {
        return <LoadingScreen message="Authenticating Commander..." />;
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
    const [tokenSet, setTokenSet] = useState(false);

    useEffect(() => {
        if (auth.isLoading) {
            return;
        }

        if (auth.isAuthenticated) {
            setAuthToken(auth.user!);
        } else {
            setAuthToken(null);
        }
        setTokenSet(true);
    }, [auth.isAuthenticated, auth.user, auth.isLoading]);

    if (auth.isLoading || !tokenSet) {
        return <LoadingScreen message="Initializing Control Systems..." />;
    }

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
