import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { useParams } from 'react-router-dom'

const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function BookingDetail() {
  const { id } = useParams()
  const [booking, setBooking] = useState(null)
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${BOOKING_URL}/api/bookings/${id}`, { headers: { Authorization: `Bearer ${token}` } })
      .then(res => setBooking(res.data))
      .catch(() => setBooking(null))
  }, [id])

  const handleCancel = async () => {
    if (!confirm('Cancel this booking?')) return
    try {
      await axios.delete(`${BOOKING_URL}/api/bookings/${id}`, { headers: { Authorization: `Bearer ${token}` } })
      alert('Booking cancelled')
      window.location.href = '/bookings'
    } catch (err) {
      alert(err.response?.data?.error || 'Cancel failed')
    }
  }

  if (!booking) return <p className="text-center py-10">Loading...</p>

  return (
    <div>
      <h1 className="text-3xl font-bold text-slate-800 mb-6">Booking {booking.bookingReference}</h1>
      <div className="bg-white rounded-xl p-6 shadow">
        <div className="grid grid-cols-2 gap-6 mb-6">
          <div>
            <p className="text-slate-500 text-sm">Flight ID</p>
            <p className="font-medium text-lg">{booking.flightId}</p>
          </div>
          <div>
            <p className="text-slate-500 text-sm">Status</p>
            <span className={`inline-block px-3 py-1 rounded-full text-sm ${booking.status === 'CONFIRMED' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
              {booking.status}
            </span>
          </div>
          <div>
            <p className="text-slate-500 text-sm">Created</p>
            <p className="font-medium">{new Date(booking.createdAt).toLocaleString()}</p>
          </div>
        </div>
        {booking.status === 'CONFIRMED' && (
          <button onClick={handleCancel} className="bg-rose-500 text-white px-6 py-3 rounded-lg font-semibold hover:bg-rose-600 transition">Cancel Booking</button>
        )}
      </div>
    </div>
  )
}