import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'

const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function Bookings() {
  const [bookings, setBookings] = useState([])
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${BOOKING_URL}/api/bookings`, { headers: { Authorization: `Bearer ${token}` } })
      .then(res => setBookings(res.data.bookings || []))
  }, [])

  return (
    <div>
      <h1 className="text-3xl font-bold text-slate-800 mb-6">My Bookings</h1>
      {bookings.length === 0 ? (
        <p className="text-slate-500">No bookings found.</p>
      ) : (
        <div className="space-y-4">
          {bookings.map(b => (
            <Link key={b.id} to={`/bookings/${b.id}`} className="block bg-white rounded-xl p-4 shadow hover:shadow-md transition">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xl font-bold text-slate-800">{b.bookingReference}</p>
                  <p className="text-slate-500">Flight: {b.flightId}</p>
                  <p className="text-sm text-slate-400">{new Date(b.createdAt).toLocaleDateString()}</p>
                </div>
                <span className={`px-3 py-1 rounded-full text-sm ${b.status === 'CONFIRMED' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                  {b.status}
                </span>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}