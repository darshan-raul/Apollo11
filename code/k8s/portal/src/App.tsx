import { BrowserRouter, Routes, Route, Navigate, Outlet } from "react-router-dom";
import { useAuth, AuthProvider } from "./context/AuthContext";
import { setAuthToken } from './api';
import { useEffect } from "react";
import Dashboard from './components/Dashboard';
import Quiz from './components/Quiz';
import LandingPage from './components/LandingPage';
import LoginPage from './components/LoginPage';
import Layout from './components/Layout';
import LoadingScreen from './components/LoadingScreen';

// Wrapper for protected routes
const ProtectedRoute = () => {
    const { isAuthenticated, isLoading } = useAuth();

    if (isLoading) {
        return <LoadingScreen message="Verifying Identity..." />;
    }

    if (!isAuthenticated) {
        return <Navigate to="/login" replace />;
    }

    return (
        <Layout>
            <Outlet />
        </Layout>
    );
};

const AppRoutes = () => {
    const { user, isAuthenticated } = useAuth();

    useEffect(() => {
        if (isAuthenticated && user) {
            setAuthToken(user);
        } else {
            setAuthToken(null);
        }
    }, [isAuthenticated, user]);

    return (
        <Routes>
            {/* Public Routes */}
            <Route path="/" element={<LandingPage />} />
            <Route path="/login" element={
                isAuthenticated ? <Navigate to="/dashboard" /> : <LoginPage />
            } />

            {/* Protected Routes */}
            <Route element={<ProtectedRoute />}>
                <Route path="/dashboard" element={<Dashboard />} />
                <Route path="/quiz/:stageId" element={<Quiz />} />
            </Route>

            {/* Catch all */}
            <Route path="*" element={<Navigate to="/" />} />
        </Routes>
    );
};

function App() {
    return (
        <AuthProvider>
            <BrowserRouter>
                <AppRoutes />
            </BrowserRouter>
        </AuthProvider>
    );
}

export default App;
