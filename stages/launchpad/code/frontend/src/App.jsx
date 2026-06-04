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
      <div style={{ fontFamily: 'Arial, sans-serif', minHeight: '100vh', backgroundColor: '#f5f5f5' }}>
        <nav style={{ backgroundColor: '#1a1a2e', color: 'white', padding: '1rem' }}>
          <div style={{ maxWidth: '1200px', margin: '0 auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: '1.5rem', fontWeight: 'bold' }}>Apollo Airlines</span>
            <div style={{ display: 'flex', gap: '1rem' }}>
              {token ? (
                <>
                  <a href="/dashboard" style={{ color: 'white', textDecoration: 'none' }}>Dashboard</a>
                  <a href="/search" style={{ color: 'white', textDecoration: 'none' }}>Search</a>
                  <a href="/bookings" style={{ color: 'white', textDecoration: 'none' }}>My Bookings</a>
                  <button onClick={handleLogout} style={{ backgroundColor: '#e94560', color: 'white', border: 'none', padding: '0.5rem 1rem', cursor: 'pointer' }}>Logout</button>
                </>
              ) : (
                <>
                  <a href="/login" style={{ color: 'white', textDecoration: 'none' }}>Login</a>
                  <a href="/register" style={{ color: 'white', textDecoration: 'none' }}>Register</a>
                </>
              )}
            </div>
          </div>
        </nav>
        <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '2rem 1rem' }}>
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