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

  if (!user) return (
    <div className="flex items-center justify-center py-20">
      <div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
    </div>
  )

  const upcoming = bookings.filter(b => b.status === 'CONFIRMED').slice(0, 3)

  return (
    <div className="animate-fade-in">
      <div className="relative bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 rounded-2xl p-8 mb-8 overflow-hidden">
        <div className="absolute inset-0">
          <div className="absolute top-0 right-0 w-64 h-64 bg-blue-500/10 rounded-full blur-3xl" />
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-rose-500/10 rounded-full blur-3xl" />
        </div>
        <div className="relative">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-rose-500 rounded-xl flex items-center justify-center text-white text-lg font-bold">
              {user.firstName?.[0] || user.email[0].toUpperCase()}
            </div>
            <div>
              <h1 className="text-2xl font-bold text-white">Welcome back, {user.firstName || user.email.split('@')[0]}</h1>
              <p className="text-slate-400 text-sm">{user.email}</p>
            </div>
          </div>
          <div className="flex items-center gap-2 mt-3">
            <span className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold ${
              user.loyaltyTier === 'PLATINUM' ? 'bg-amber-500/20 text-amber-300' :
              user.loyaltyTier === 'GOLD' ? 'bg-yellow-500/20 text-yellow-300' :
              'bg-blue-500/20 text-blue-300'
            }`}>
              {user.loyaltyTier}
            </span>
            <span className="inline-flex items-center px-3 py-1 bg-slate-700/50 text-slate-300 rounded-full text-xs font-medium">{user.role}</span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl p-6 shadow-card hover:shadow-card-hover hover-lift border border-slate-100">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
              </svg>
            </div>
            <p className="text-slate-500 text-sm font-medium">Loyalty Tier</p>
          </div>
          <p className="text-2xl font-bold text-slate-800">{user.loyaltyTier}</p>
        </div>

        <div className="bg-white rounded-xl p-6 shadow-card hover:shadow-card-hover hover-lift border border-slate-100">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 bg-rose-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
            </div>
            <p className="text-slate-500 text-sm font-medium">Role</p>
          </div>
          <p className="text-2xl font-bold text-slate-800">{user.role}</p>
        </div>

        <div className="bg-white rounded-xl p-6 shadow-card hover:shadow-card-hover hover-lift border border-slate-100">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
              </svg>
            </div>
            <p className="text-slate-500 text-sm font-medium">Total Bookings</p>
          </div>
          <p className="text-2xl font-bold text-slate-800">{bookings.length}</p>
        </div>
      </div>

      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-slate-800">Upcoming Bookings</h2>
        <Link to="/search" className="text-blue-600 hover:text-blue-700 text-sm font-medium flex items-center gap-1">
          Search flights
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </Link>
      </div>

      {upcoming.length === 0 ? (
        <div className="bg-white rounded-xl p-8 text-center shadow-card border border-slate-100">
          <div className="w-16 h-16 bg-slate-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
          </div>
          <p className="text-slate-500 mb-4">No upcoming bookings found.</p>
          <Link to="/search" className="inline-flex items-center gap-2 bg-gradient-to-r from-blue-600 to-rose-600 text-white px-6 py-3 rounded-xl font-semibold hover:opacity-90 transition-all">
            Search Flights
          </Link>
        </div>
      ) : (
        <div className="space-y-4 mb-8">
          {upcoming.map(b => (
            <Link key={b.id} to={`/bookings/${b.id}`} className="block bg-white rounded-xl p-5 shadow-card hover:shadow-card-hover hover-lift border border-slate-100 group">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-bold text-lg text-slate-800 group-hover:text-blue-600 transition-colors">{b.bookingReference}</p>
                  <p className="text-slate-500 text-sm">Flight: {b.flightId}</p>
                </div>
                <span className="inline-flex items-center px-3 py-1 bg-green-100 text-green-700 text-sm font-semibold rounded-full">{b.status}</span>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}