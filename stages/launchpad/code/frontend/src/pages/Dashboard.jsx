import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'
import PageHeader from '../components/PageHeader'
import StatusBadge from '../components/StatusBadge'
import Button from '../components/Button'
import EmptyState from '../components/EmptyState'
import { DashboardSkeleton } from '../components/LoadingSkeleton'
import AnimatedNumber from '../components/AnimatedNumber'

const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'
const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

const StatCard = ({ icon, iconBg, iconColor, label, value, isNumber = false, delay = 0 }) => (
  <div
    className="bg-white rounded-2xl border border-slate-100 shadow-card p-6 hover:shadow-card-hover hover-lift transition-all duration-300 animate-fade-in-up"
    style={{ animationDelay: `${delay}ms` }}
  >
    <div className="flex items-center gap-3 mb-4">
      <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${iconBg}`}>
        <svg className={`w-5 h-5 ${iconColor}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
          {icon}
        </svg>
      </div>
      <p className="text-sm font-medium text-slate-500">{label}</p>
    </div>
    <p className="text-2xl font-bold text-slate-800">
      {isNumber ? <AnimatedNumber value={value} /> : value}
    </p>
  </div>
)

export default function Dashboard() {
  const [user, setUser] = useState(null)
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const token = localStorage.getItem('token')

  useEffect(() => {
    const headers = { Authorization: `Bearer ${token}` }
    Promise.all([
      axios.get(`${IDENTITY_URL}/api/users/me`, { headers }),
      axios.get(`${BOOKING_URL}/api/bookings`, { headers }).catch(() => ({ data: { bookings: [] } })),
    ])
      .then(([userRes, bookingsRes]) => {
        setUser(userRes.data)
        setBookings(bookingsRes.data?.bookings || [])
        setLoading(false)
      })
      .catch((err) => {
        setError(err.response?.data?.detail || 'Failed to load dashboard')
        setLoading(false)
      })
  }, [])

  if (loading) return <DashboardSkeleton />

  if (error) {
    return (
      <div className="bg-white rounded-2xl border border-rose-100 shadow-card p-8 text-center">
        <div className="w-14 h-14 bg-rose-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
          <svg className="w-7 h-7 text-rose-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
          </svg>
        </div>
        <h3 className="text-lg font-semibold text-slate-800 mb-1.5">{error}</h3>
        <p className="text-slate-500 text-sm mb-6">Please try reloading the page.</p>
        <Button variant="secondary" size="sm" onClick={() => window.location.reload()}>Reload</Button>
      </div>
    )
  }

  const upcoming = bookings.filter(b => b.status === 'CONFIRMED').slice(0, 3)
  const firstName = user.firstName || user.email.split('@')[0]
  const initials = (user.firstName?.[0] || user.email[0]).toUpperCase()

  return (
    <div>
      <div className="relative bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 rounded-2xl p-6 sm:p-8 mb-8 overflow-hidden animate-fade-in">
        <div className="absolute inset-0 pointer-events-none">
          <div className="absolute top-0 right-0 w-72 h-72 bg-blue-500/20 rounded-full blur-3xl" />
          <div className="absolute bottom-0 left-0 w-72 h-72 bg-rose-500/20 rounded-full blur-3xl" />
        </div>
        <div className="relative flex flex-col sm:flex-row sm:items-center gap-5">
          <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-rose-500 rounded-2xl flex items-center justify-center text-white text-2xl font-bold shadow-lg shadow-blue-500/30 flex-shrink-0">
            {initials}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-slate-400 text-sm font-medium">Welcome back</p>
            <h1 className="text-2xl sm:text-3xl font-bold text-white tracking-tight truncate">{firstName}</h1>
            <p className="text-slate-400 text-sm truncate mt-0.5">{user.email}</p>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <StatusBadge status={user.loyaltyTier} size="md" icon />
            <StatusBadge status={user.role} size="md" icon />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <StatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.563.563 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z" /></>}
          iconBg="bg-amber-50"
          iconColor="text-amber-600"
          label="Loyalty tier"
          value={user.loyaltyTier}
          delay={0}
        />
        <StatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" /></>}
          iconBg="bg-purple-50"
          iconColor="text-purple-600"
          label="Role"
          value={user.role}
          delay={80}
        />
        <StatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M16.5 6v.75m0 3v.75m0 3v.75m0 3V18m-9-5.25h5.25M7.5 15h3M3.375 5.25c-.621 0-1.125.504-1.125 1.125v3.026a2.999 2.999 0 010 5.198v3.026c0 .621.504 1.125 1.125 1.125h17.25c.621 0 1.125-.504 1.125-1.125v-3.026a2.999 2.999 0 010-5.198V6.375c0-.621-.504-1.125-1.125-1.125H3.375z" /></>}
          iconBg="bg-blue-50"
          iconColor="text-blue-600"
          label="Total bookings"
          value={bookings.length}
          isNumber
          delay={160}
        />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-10">
        <Link
          to="/search"
          className="group relative bg-white rounded-2xl border border-slate-100 shadow-card p-5 hover:shadow-card-hover hover-lift transition-all duration-300 overflow-hidden"
        >
          <div className="absolute -right-8 -top-8 w-32 h-32 bg-gradient-to-br from-blue-100 to-rose-100 rounded-full opacity-50 group-hover:scale-125 transition-transform duration-500" />
          <div className="relative">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center mb-3">
              <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
              </svg>
            </div>
            <h3 className="font-semibold text-slate-800">Search flights</h3>
            <p className="text-sm text-slate-500 mt-1">Find your next destination</p>
          </div>
        </Link>
        <Link
          to="/bookings"
          className="group relative bg-white rounded-2xl border border-slate-100 shadow-card p-5 hover:shadow-card-hover hover-lift transition-all duration-300 overflow-hidden"
        >
          <div className="absolute -right-8 -top-8 w-32 h-32 bg-gradient-to-br from-rose-100 to-amber-100 rounded-full opacity-50 group-hover:scale-125 transition-transform duration-500" />
          <div className="relative">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-rose-500 to-rose-600 flex items-center justify-center mb-3">
              <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 6v.75m0 3v.75m0 3v.75m0 3V18m-9-5.25h5.25M7.5 15h3M3.375 5.25c-.621 0-1.125.504-1.125 1.125v3.026a2.999 2.999 0 010 5.198v3.026c0 .621.504 1.125 1.125 1.125h17.25c.621 0 1.125-.504 1.125-1.125v-3.026a2.999 2.999 0 010-5.198V6.375c0-.621-.504-1.125-1.125-1.125H3.375z" />
              </svg>
            </div>
            <h3 className="font-semibold text-slate-800">My bookings</h3>
            <p className="text-sm text-slate-500 mt-1">View and manage your trips</p>
          </div>
        </Link>
      </div>

      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-slate-800">Upcoming bookings</h2>
        <Link to="/bookings" className="text-sm font-semibold text-blue-600 hover:text-blue-700 flex items-center gap-1 transition-colors group">
          View all
          <svg className="w-4 h-4 group-hover:translate-x-0.5 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
          </svg>
        </Link>
      </div>

      {upcoming.length === 0 ? (
        <EmptyState
          icon={
            <svg className="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5" />
            </svg>
          }
          title="No upcoming bookings"
          message="You don't have any confirmed bookings yet. Search for a flight to get started."
          action={
            <Link to="/search">
              <Button leftIcon={
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
                </svg>
              }>Search flights</Button>
            </Link>
          }
        />
      ) : (
        <div className="space-y-3">
          {upcoming.map((b, idx) => (
            <Link
              key={b.id}
              to={`/bookings/${b.id}`}
              className="group block bg-white rounded-2xl border border-slate-100 shadow-card hover:shadow-card-hover hover-lift transition-all duration-300 animate-fade-in-up"
              style={{ animationDelay: `${idx * 60}ms` }}
            >
              <div className="flex items-center gap-4 p-5">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-blue-50 to-rose-50 flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform">
                  <svg className="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 19.5L21 12 2.25 4.5l3 7.5-3 7.5zM7 12h14" />
                  </svg>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-slate-800 group-hover:text-blue-600 transition-colors">
                    {b.bookingReference || `Booking #${b.id.slice(0, 8)}`}
                  </p>
                  <p className="text-sm text-slate-500 mt-0.5">
                    {new Date(b.createdAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}
                  </p>
                </div>
                <StatusBadge status={b.status} size="md" icon />
                <svg className="w-5 h-5 text-slate-400 group-hover:text-blue-600 group-hover:translate-x-1 transition-all flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
                </svg>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}