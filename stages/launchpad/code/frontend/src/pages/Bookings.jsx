import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'

const BOOKING_API = 'http://localhost:8082'

export default function Bookings() {
  const [bookings, setBookings] = useState([])
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${BOOKING_API}/api/bookings`, { headers: { Authorization: `Bearer ${token}` } })
      .then(res => setBookings(res.data.bookings || []))
  }, [])

  return (
    <div>
      <h1 style={{ color: '#1a1a2e' }}>My Bookings</h1>
      {bookings.length === 0 ? <p>No bookings found.</p> : (
        <div style={{ display: 'grid', gap: '1rem' }}>
          {bookings.map(b => (
            <Link key={b.id} to={`/bookings/${b.id}`} style={{ backgroundColor: 'white', padding: '1rem', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)', textDecoration: 'none', color: 'inherit', display: 'block' }}>
              <p style={{ fontSize: '1.25rem', fontWeight: 'bold' }}>{b.bookingReference}</p>
              <p>Flight ID: {b.flightId}</p>
              <p>Status: <span style={{ color: b.status === 'CONFIRMED' ? 'green' : 'red' }}>{b.status}</span></p>
              <p>Created: {new Date(b.createdAt).toLocaleString()}</p>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}