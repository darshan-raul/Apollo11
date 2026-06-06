import React, { useState, useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate, Link, useLocation } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import Login from './pages/Login'
import Register from './pages/Register'
import Dashboard from './pages/Dashboard'
import Search from './pages/Search'
import Flights from './pages/Flights'
import Bookings from './pages/Bookings'
import BookingDetail from './pages/BookingDetail'
import AdminDashboard from './pages/admin/AdminDashboard'
import AdminFlights from './pages/admin/AdminFlights'
import AdminFlightForm from './pages/admin/AdminFlightForm'
import AdminBookings from './pages/admin/AdminBookings'
import ProtectedRoute from './components/ProtectedRoute'
import Logo from './components/Logo'

function decodeJWT(token) {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')))
    return payload
  } catch {
    return null
  }
}

function NavLink({ to, children }) {
  const location = useLocation()
  const isActive = location.pathname === to
  return (
    <Link
      to={to}
      className={`px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 ${isActive
        ? 'text-white bg-white/10'
        : 'text-slate-300 hover:text-white hover:bg-white/5'
      }`}
    >
      {children}
    </Link>
  )
}

function Navbar({ user, mobileOpen, setMobileOpen, handleLogout }) {
  return (
    <nav className="sticky top-0 z-50 bg-slate-900/95 backdrop-blur-md border-b border-white/5">
      <div className="max-w-7xl mx-auto px-4 sm:px-6">
        <div className="flex items-center justify-between h-16">
          <Link to="/" className="flex items-center gap-2.5 group">
            <Logo size="sm" className="group-hover:scale-105 transition-transform" />
            <span className="text-white font-semibold tracking-tight">Apollo Airlines</span>
          </Link>

          <div className="hidden md:flex items-center gap-1">
            {user ? (
              <>
                <NavLink to="/dashboard">Dashboard</NavLink>
                <NavLink to="/search">Search</NavLink>
                <NavLink to="/bookings">Bookings</NavLink>
                {user.role === 'ADMIN' && <NavLink to="/admin">Admin</NavLink>}
                <button
                  onClick={handleLogout}
                  className="ml-3 inline-flex items-center gap-1.5 px-4 py-2 bg-rose-600 hover:bg-rose-500 text-white text-sm font-semibold rounded-lg transition-all duration-200 shadow-lg shadow-rose-500/20"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9" />
                  </svg>
                  Logout
                </button>
              </>
            ) : (
              <>
                <NavLink to="/login">Sign In</NavLink>
                <Link
                  to="/register"
                  className="ml-2 px-4 py-2 bg-gradient-to-r from-blue-600 to-rose-600 text-white text-sm font-semibold rounded-lg hover:opacity-90 hover:-translate-y-0.5 transition-all duration-200 shadow-lg shadow-blue-500/20"
                >
                  Register
                </Link>
              </>
            )}
          </div>

          <button
            className="md:hidden p-2 text-slate-300 hover:text-white rounded-lg hover:bg-white/5 transition-colors"
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-label="Toggle menu"
          >
            {mobileOpen ? (
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            ) : (
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            )}
          </button>
        </div>

        {mobileOpen && (
          <div className="md:hidden pb-4 pt-2 space-y-1 border-t border-white/5 animate-fade-in">
            {user ? (
              <>
                <NavLink to="/dashboard"><span className="block py-2">Dashboard</span></NavLink>
                <NavLink to="/search"><span className="block py-2">Search</span></NavLink>
                <NavLink to="/bookings"><span className="block py-2">Bookings</span></NavLink>
                {user.role === 'ADMIN' && <NavLink to="/admin"><span className="block py-2">Admin</span></NavLink>}
                <button onClick={handleLogout} className="w-full mt-3 py-2.5 bg-rose-600 text-white font-semibold rounded-lg">Logout</button>
              </>
            ) : (
              <>
                <NavLink to="/login"><span className="block py-2">Sign In</span></NavLink>
                <Link to="/register" className="block mt-3 py-2.5 bg-gradient-to-r from-blue-600 to-rose-600 text-white font-semibold rounded-lg text-center">Register</Link>
              </>
            )}
          </div>
        )}
      </div>
    </nav>
  )
}

function App() {
  const [user, setUser] = useState(() => {
    const token = localStorage.getItem('token') || ''
    return token ? decodeJWT(token) : null
  })
  const [mobileOpen, setMobileOpen] = useState(false)

  const handleLogin = (newToken) => {
    localStorage.setItem('token', newToken)
    const payload = decodeJWT(newToken)
    setUser(payload)
  }

  const handleLogout = () => {
    localStorage.removeItem('token')
    setUser(null)
  }

  return (
    <BrowserRouter>
      <Toaster
        position="top-right"
        toastOptions={{
          duration: 3500,
          style: {
            borderRadius: '12px',
            background: '#fff',
            color: '#1e293b',
            boxShadow: '0 10px 30px -5px rgba(0,0,0,0.15), 0 4px 6px -2px rgba(0,0,0,0.05)',
            border: '1px solid #e2e8f0',
            padding: '12px 16px',
            fontSize: '14px',
            fontWeight: '500',
          },
          success: { iconTheme: { primary: '#3b82f6', secondary: '#fff' } },
          error: { iconTheme: { primary: '#f43f5e', secondary: '#fff' } },
        }}
      />
      <div className="min-h-screen bg-slate-50 flex flex-col">
        <Navbar user={user} mobileOpen={mobileOpen} setMobileOpen={setMobileOpen} handleLogout={handleLogout} />

        <main className="flex-1 max-w-7xl mx-auto w-full px-4 sm:px-6 py-6 sm:py-10">
          <Routes>
            <Route path="/" element={user ? <Navigate to="/dashboard" /> : (
              <div className="relative bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 rounded-2xl overflow-hidden py-16 sm:py-24 animate-fade-in">
                <div className="absolute inset-0 pointer-events-none">
                  <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/20 rounded-full blur-3xl animate-pulse" />
                  <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-rose-500/20 rounded-full blur-3xl animate-pulse" />
                </div>
                <div className="relative max-w-4xl mx-auto px-4 sm:px-6 text-center">
                  <div className="inline-flex mb-6 animate-scale-in">
                    <Logo size="xl" />
                  </div>
                  <h1 className="text-4xl sm:text-6xl font-bold text-white mb-6 tracking-tight animate-fade-in-up">
                    Fly Beyond <span className="bg-gradient-to-r from-blue-400 to-rose-400 bg-clip-text text-transparent">Horizons</span>
                  </h1>
                  <p className="text-lg sm:text-xl text-slate-400 mb-10 max-w-2xl mx-auto animate-fade-in-up" style={{ animationDelay: '100ms' }}>
                    Experience premium air travel with seamless booking and exceptional service across global destinations.
                  </p>
                  <Link
                    to="/login"
                    className="inline-flex items-center gap-2 bg-gradient-to-r from-blue-600 to-rose-600 text-white px-8 py-4 rounded-xl font-semibold hover:opacity-90 hover:-translate-y-0.5 transition-all duration-200 shadow-lg shadow-blue-500/30 animate-fade-in-up"
                    style={{ animationDelay: '200ms' }}
                  >
                    Get started
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
                    </svg>
                  </Link>
                </div>
              </div>
            )} />
            <Route path="/login" element={<Login onLogin={handleLogin} />} />
            <Route path="/register" element={<Register />} />
            <Route path="/dashboard" element={<ProtectedRoute user={user}><Dashboard /></ProtectedRoute>} />
            <Route path="/search" element={<ProtectedRoute user={user}><Search /></ProtectedRoute>} />
            <Route path="/flights/:id" element={<ProtectedRoute user={user}><Flights /></ProtectedRoute>} />
            <Route path="/bookings" element={<ProtectedRoute user={user}><Bookings /></ProtectedRoute>} />
            <Route path="/bookings/:id" element={<ProtectedRoute user={user}><BookingDetail /></ProtectedRoute>} />
            <Route path="/admin" element={<ProtectedRoute user={user} requiredRole="ADMIN"><AdminDashboard /></ProtectedRoute>} />
            <Route path="/admin/flights" element={<ProtectedRoute user={user} requiredRole="ADMIN"><AdminFlights /></ProtectedRoute>} />
            <Route path="/admin/flights/new" element={<ProtectedRoute user={user} requiredRole="ADMIN"><AdminFlightForm /></ProtectedRoute>} />
            <Route path="/admin/flights/:id" element={<ProtectedRoute user={user} requiredRole="ADMIN"><AdminFlightForm /></ProtectedRoute>} />
            <Route path="/admin/bookings" element={<ProtectedRoute user={user} requiredRole="ADMIN"><AdminBookings /></ProtectedRoute>} />
          </Routes>
        </main>

        <footer className="border-t border-slate-200 bg-white mt-auto">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 flex flex-col sm:flex-row items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <Logo size="sm" />
              <span className="text-sm font-semibold text-slate-700">Apollo Airlines</span>
            </div>
            <p className="text-xs text-slate-500">© {new Date().getFullYear()} Apollo Airlines. All rights reserved.</p>
          </div>
        </footer>
      </div>
    </BrowserRouter>
  )
}

export default App