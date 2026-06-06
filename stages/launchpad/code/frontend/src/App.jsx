import React, { useState } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Login from './pages/Login'
import Register from './pages/Register'
import Dashboard from './pages/Dashboard'
import Search from './pages/Search'
import Flights from './pages/Flights'
import Bookings from './pages/Bookings'
import BookingDetail from './pages/BookingDetail'

function App() {
  const [token, setToken] = useState(localStorage.getItem('token') || '')
  const [mobileOpen, setMobileOpen] = useState(false)

  const handleLogin = (newToken) => {
    localStorage.setItem('token', newToken)
    setToken(newToken)
  }

  const handleLogout = () => {
    localStorage.removeItem('token')
    setToken('')
  }

  return (
    <BrowserRouter>
      <div className="min-h-screen bg-slate-50">
        <nav className="sticky top-0 z-50 bg-slate-900/95 backdrop-blur-md border-b border-white/5">
          <div className="max-w-7xl mx-auto px-4 sm:px-6">
            <div className="flex items-center justify-between h-16">
              <a href="/" className="flex items-center gap-2">
                <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-rose-500 rounded-lg flex items-center justify-center">
                  <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 14l9-5-9-5-9 5 9 5z" />
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 14l6.16-3.422a12.083 12.083 0 01.665 6.479A11.952 11.952 0 0012 20.055a11.952 11.952 0 00-6.824-2.998 12.078 12.078 0 01.665-6.479L12 14z" />
                  </svg>
                </div>
                <span className="text-white font-semibold">Apollo Airlines</span>
              </a>

              <div className="hidden md:flex items-center gap-1">
                {token ? (
                  <>
                    <a href="/dashboard" className="px-4 py-2 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg text-sm font-medium transition-all">Dashboard</a>
                    <a href="/search" className="px-4 py-2 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg text-sm font-medium transition-all">Search</a>
                    <a href="/bookings" className="px-4 py-2 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg text-sm font-medium transition-all">Bookings</a>
                    <button onClick={handleLogout} className="ml-2 px-4 py-2 bg-rose-600 hover:bg-rose-500 text-white text-sm font-semibold rounded-lg transition-all">Logout</button>
                  </>
                ) : (
                  <>
                    <a href="/login" className="px-4 py-2 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg text-sm font-medium transition-all">Sign In</a>
                    <a href="/register" className="px-4 py-2 bg-gradient-to-r from-blue-600 to-rose-600 text-white text-sm font-semibold rounded-lg hover:opacity-90 transition-all">Register</a>
                  </>
                )}
              </div>

              <button className="md:hidden p-2 text-slate-300 hover:text-white" onClick={() => setMobileOpen(!mobileOpen)}>
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              </button>
            </div>

            {mobileOpen && (
              <div className="md:hidden pb-4 space-y-1">
                {token ? (
                  <>
                    <a href="/dashboard" className="block py-2 px-3 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg">Dashboard</a>
                    <a href="/search" className="block py-2 px-3 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg">Search</a>
                    <a href="/bookings" className="block py-2 px-3 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg">Bookings</a>
                    <button onClick={handleLogout} className="w-full mt-2 py-2 bg-rose-600 text-white font-semibold rounded-lg">Logout</button>
                  </>
                ) : (
                  <>
                    <a href="/login" className="block py-2 px-3 text-slate-300 hover:text-white hover:bg-white/5 rounded-lg">Sign In</a>
                    <a href="/register" className="block py-2 px-3 bg-gradient-to-r from-blue-600 to-rose-600 text-white font-semibold rounded-lg text-center mt-2">Register</a>
                  </>
                )}
              </div>
            )}
          </div>
        </nav>

        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
          <Routes>
            <Route path="/" element={token ? <Navigate to="/dashboard" /> : (
              <div className="relative bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 rounded-2xl overflow-hidden py-20">
                <div className="absolute inset-0">
                  <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/20 rounded-full blur-3xl" />
                  <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-rose-500/20 rounded-full blur-3xl" />
                </div>
                <div className="relative max-w-7xl mx-auto px-4 sm:px-6 text-center">
                  <h1 className="text-5xl sm:text-6xl font-bold text-white mb-6 tracking-tight">
                    Fly Beyond <span className="bg-gradient-to-r from-blue-400 to-rose-400 bg-clip-text text-transparent">Horizons</span>
                  </h1>
                  <p className="text-xl text-slate-400 mb-10 max-w-2xl mx-auto">Experience premium air travel with seamless booking and exceptional service across global destinations.</p>
                  <a href="/search" className="inline-flex items-center gap-2 bg-gradient-to-r from-blue-600 to-rose-600 text-white px-8 py-4 rounded-xl font-semibold hover:opacity-90 hover:-translate-y-0.5 transition-all shadow-lg shadow-blue-500/30">
                    Book Your Flight
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                    </svg>
                  </a>
                </div>
              </div>
            )} />
            <Route path="/login" element={<Login onLogin={handleLogin} />} />
            <Route path="/register" element={<Register />} />
            <Route path="/dashboard" element={token ? <Dashboard /> : <Navigate to="/login" />} />
            <Route path="/search" element={token ? <Search /> : <Navigate to="/login" />} />
            <Route path="/flights/:id" element={token ? <Flights /> : <Navigate to="/login" />} />
            <Route path="/bookings" element={token ? <Bookings /> : <Navigate to="/login" />} />
            <Route path="/bookings/:id" element={token ? <BookingDetail /> : <Navigate to="/login" />} />
          </Routes>
        </div>
      </div>
    </BrowserRouter>
  )
}

export default App