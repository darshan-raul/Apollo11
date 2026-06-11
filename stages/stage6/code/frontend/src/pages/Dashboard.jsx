import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'

const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'
const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function Dashboard() {
  const [user, setUser] = useState(null)
  const [bookings, setBookings] = useState([])
  const token = localStorage.getItem('token')

  useEffect(() => {
    const headers = { Authorization: `Bearer ${token}` }
    axios.get(`${IDENTITY_URL}/api/users/me`, { headers }).then(res => setUser(res.data))
    axios.get(`${BOOKING_URL}/api/bookings`, { headers }).then(res => setBookings(res.data.bookings || [])).catch(() => {})
  }, [])

  if (!user) return <div className="text-center py-10">Loading...</div>

  const upcoming = bookings.filter(b => b.status === 'CONFIRMED').slice(0, 3)

  return (
    <div>
      <div className="bg-gradient-to-r from-slate-900 to-blue-900 rounded-xl p-8 text-white mb-8">
        <h1 className="text-3xl font-bold mb-2">Welcome back, {user.firstName} {user.lastName}</h1>
        <p className="text-slate-300">{user.email}</p>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl p-6 shadow">
          <p className="text-slate-500 text-sm">Loyalty Tier</p>
          <p className="text-2xl font-bold text-slate-800">{user.loyaltyTier}</p>
        </div>
        <div className="bg-white rounded-xl p-6 shadow">
          <p className="text-slate-500 text-sm">Role</p>
          <p className="text-2xl font-bold text-slate-800">{user.role}</p>
        </div>
        <div className="bg-white rounded-xl p-6 shadow">
          <p className="text-slate-500 text-sm">Total Bookings</p>
          <p className="text-2xl font-bold text-slate-800">{bookings.length}</p>
        </div>
      </div>
      <h2 className="text-2xl font-bold text-slate-800 mb-4">Upcoming Bookings</h2>
      {upcoming.length === 0 ? (
        <p className="text-slate-500">No upcoming bookings.</p>
      ) : (
        <div className="space-y-4 mb-6">
          {upcoming.map(b => (
            <Link key={b.id} to={`/bookings/${b.id}`} className="block bg-white rounded-xl p-4 shadow hover:shadow-md transition">
              <p className="font-bold text-lg">{b.bookingReference}</p>
              <p className="text-slate-500">Flight: {b.flightId}</p>
              <span className="inline-block mt-2 px-2 py-1 bg-green-100 text-green-700 text-sm rounded">{b.status}</span>
            </Link>
          ))}
        </div>
      )}
      <Link to="/search" className="inline-block bg-rose-500 text-white px-6 py-3 rounded-lg font-semibold hover:bg-rose-600 transition">Search Flights</Link>
    </div>
  )
}