import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { useParams } from 'react-router-dom'

const BOOKING_API = 'http://localhost:8082'

export default function BookingDetail() {
  const { id } = useParams()
  const [booking, setBooking] = useState(null)
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${BOOKING_API}/api/bookings/${id}`, { headers: { Authorization: `Bearer ${token}` } })
      .then(res => setBooking(res.data))
      .catch(() => setBooking(null))
  }, [id])

  const handleCancel = async () => {
    if (!confirm('Cancel this booking?')) return
    try {
      await axios.delete(`${BOOKING_API}/api/bookings/${id}`, { headers: { Authorization: `Bearer ${token}` } })
      alert('Booking cancelled')
      window.location.href = '/bookings'
    } catch (err) {
      alert(err.response?.data?.error || 'Cancel failed')
    }
  }

  if (!booking) return <p>Loading...</p>

  return (
    <div>
      <h1 style={{ color: '#1a1a2e' }}>Booking {booking.bookingReference}</h1>
      <div style={{ backgroundColor: 'white', padding: '1.5rem', borderRadius: '8px', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}>
        <p><strong>Flight ID:</strong> {booking.flightId}</p>
        <p><strong>Status:</strong> {booking.status}</p>
        <p><strong>Created:</strong> {new Date(booking.createdAt).toLocaleString()}</p>
        {booking.status === 'CONFIRMED' && (
          <button onClick={handleCancel} style={{ backgroundColor: '#e94560', color: 'white', padding: '0.75rem 1.5rem', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '1rem', marginTop: '1rem' }}>Cancel Booking</button>
        )}
      </div>
    </div>
  )
}