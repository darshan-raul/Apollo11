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
        <nav className="bg-slate-900 text-white">
          <div className="max-w-7xl mx-auto px-4">
            <div className="flex items-center justify-between h-16">
              <a href="/" className="text-xl font-bold">Apollo Airlines</a>
              <div className="hidden md:flex items-center space-x-6">
                {token ? (
                  <>
                    <a href="/dashboard" className="hover:text-slate-300">Dashboard</a>
                    <a href="/search" className="hover:text-slate-300">Search</a>
                    <a href="/bookings" className="hover:text-slate-300">My Bookings</a>
                    <button onClick={handleLogout} className="bg-rose-500 px-4 py-2 rounded hover:bg-rose-600">Logout</button>
                  </>
                ) : (
                  <>
                    <a href="/login" className="hover:text-slate-300">Login</a>
                    <a href="/register" className="hover:text-slate-300">Register</a>
                  </>
                )}
              </div>
              <button className="md:hidden" onClick={() => setMobileOpen(!mobileOpen)}>
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              </button>
            </div>
            {mobileOpen && (
              <div className="md:hidden pb-4 space-y-2">
                {token ? (
                  <>
                    <a href="/dashboard" className="block py-2 hover:text-slate-300">Dashboard</a>
                    <a href="/search" className="block py-2 hover:text-slate-300">Search</a>
                    <a href="/bookings" className="block py-2 hover:text-slate-300">My Bookings</a>
                    <button onClick={handleLogout} className="bg-rose-500 px-4 py-2 rounded w-full">Logout</button>
                  </>
                ) : (
                  <>
                    <a href="/login" className="block py-2 hover:text-slate-300">Login</a>
                    <a href="/register" className="block py-2 hover:text-slate-300">Register</a>
                  </>
                )}
              </div>
            )}
          </div>
        </nav>
        {!token && (
          <div className="bg-gradient-to-br from-slate-900 to-blue-900 text-white py-20">
            <div className="max-w-7xl mx-auto px-4 text-center">
              <h1 className="text-5xl font-bold mb-4">Fly Beyond Horizons</h1>
              <p className="text-xl text-slate-300 mb-8">Experience premium air travel with Apollo Airlines</p>
              <a href="/search" className="bg-rose-500 px-8 py-3 rounded-lg font-semibold hover:bg-rose-600 inline-block">Book Your Flight</a>
            </div>
          </div>
        )}
        <div className="max-w-7xl mx-auto px-4 py-8">
          <Routes>
            <Route path="/" element={token ? <Navigate to="/dashboard" /> : <Navigate to="/login" />} />
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