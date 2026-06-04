import React, { useEffect, useState } from 'react'
import axios from 'axios'

const API = 'http://localhost:8080'
const BOOKING_API = 'http://localhost:8082'

export default function Dashboard() {
  const [user, setUser] = useState(null)
  const [bookings, setBookings] = useState([])
  const token = localStorage.getItem('token')

  useEffect(() => {
    const headers = { Authorization: `Bearer ${token}` }
    axios.get(`${API}/api/users/me`, { headers }).then(res => setUser(res.data))
    axios.get(`${BOOKING_API}/api/bookings`, { headers }).then(res => setBookings(res.data.bookings || []))
  }, [])

  if (!user) return <div style={{ textAlign: 'center' }}>Loading...</div>

  const upcoming = bookings.filter(b => b.status === 'CONFIRMED').slice(0, 3)

  return (
    <div>
      <h1 style={{ color: '#1a1a2e' }}>Welcome, {user.firstName} {user.lastName}</h1>
      <div style={{ backgroundColor: 'white', padding: '1.5rem', borderRadius: '8px', marginBottom: '1rem', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}>
        <p><strong>Email:</strong> {user.email}</p>
        <p><strong>Loyalty Tier:</strong> {user.loyaltyTier}</p>
        <p><strong>Role:</strong> {user.role}</p>
      </div>
      <h2 style={{ color: '#1a1a2e' }}>Upcoming Bookings</h2>
      {upcoming.length === 0 ? <p>No upcoming bookings.</p> : (
        <div style={{ display: 'grid', gap: '1rem' }}>
          {upcoming.map(b => (
            <div key={b.id} style={{ backgroundColor: 'white', padding: '1rem', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
              <p><strong>Reference:</strong> {b.bookingReference}</p>
              <p><strong>Flight ID:</strong> {b.flightId}</p>
              <p><strong>Status:</strong> {b.status}</p>
            </div>
          ))}
        </div>
      )}
      <div style={{ marginTop: '1rem' }}>
        <a href="/search" style={{ backgroundColor: '#0f3460', color: 'white', padding: '0.75rem 1.5rem', textDecoration: 'none', borderRadius: '4px', display: 'inline-block' }}>Search Flights</a>
      </div>
    </div>
  )
}