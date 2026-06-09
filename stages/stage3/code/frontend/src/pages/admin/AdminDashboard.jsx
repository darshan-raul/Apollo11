import React, { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import axios from 'axios'
import PageHeader from '../../components/PageHeader'
import AdminStatCard from '../../components/AdminStatCard'
import StatusBadge from '../../components/StatusBadge'
import Button from '../../components/Button'
import { DashboardSkeleton } from '../../components/LoadingSkeleton'
import ErrorCard from '../../components/ErrorCard'
import toast from 'react-hot-toast'

const FLIGHT_URL = import.meta.env.VITE_FLIGHT_URL || 'http://localhost:8081'
const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'
const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function AdminDashboard() {
  const [stats, setStats] = useState({ flights: 0, users: 0, bookings: 0 })
  const [recentBookings, setRecentBookings] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const token = localStorage.getItem('token')
  const headers = { Authorization: `Bearer ${token}` }

  useEffect(() => {
    Promise.all([
      axios.get(`${FLIGHT_URL}/api/flights`).catch(() => ({ data: { flights: [] } })),
      axios.get(`${IDENTITY_URL}/api/admin/users`, { headers }).catch(() => ({ data: { users: [] } })),
      axios.get(`${BOOKING_URL}/api/admin/bookings`, { headers }).catch(() => ({ data: { bookings: [] } })),
    ])
      .then(([flightRes, userRes, bookingRes]) => {
        const flights = flightRes.data?.flights || []
        const users = userRes.data?.users || []
        const bookings = bookingRes.data?.bookings || []
        setStats({ flights: flights.length, users: users.length, bookings: bookings.length })
        setRecentBookings(bookings.slice(0, 8))
        setLoading(false)
      })
      .catch(() => {
        setError('Failed to load admin dashboard')
        setLoading(false)
      })
  }, [])

  if (loading) return <DashboardSkeleton />

  if (error) return <ErrorCard message={error} onRetry={() => window.location.reload()} />

  const adminLinks = [
    {
      to: '/admin/flights',
      icon: <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 19.5L21 12 2.25 4.5l3 7.5-3 7.5zM7 12h14" />,
      label: 'Manage Flights',
      desc: 'Create and update flight schedules',
      bg: 'from-blue-500 to-blue-600',
    },
    {
      to: '/admin/bookings',
      icon: <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 6v.75m0 3v.75m0 3v.75m0 3V18m-9-5.25h5.25M7.5 15h3M3.375 5.25c-.621 0-1.125.504-1.125 1.125v3.026a2.999 2.999 0 010 5.198v3.026c0 .621.504 1.125 1.125 1.125h17.25c.621 0 1.125-.504 1.125-1.125v-3.026a2.999 2.999 0 010-5.198V6.375c0-.621-.504-1.125-1.125-1.125H3.375z" />,
      label: 'All Bookings',
      desc: 'View and manage all reservations',
      bg: 'from-rose-500 to-rose-600',
    },
  ]

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Admin Dashboard"
        subtitle="Overview of Apollo Airlines operations"
        breadcrumb={[{ label: 'Admin' }, { label: 'Dashboard' }]}
      />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <AdminStatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 19.5L21 12 2.25 4.5l3 7.5-3 7.5zM7 12h14" /></>}
          iconBg="bg-blue-50"
          iconColor="text-blue-600"
          label="Total flights"
          value={stats.flights}
          isNumber
          delay={0}
        />
        <AdminStatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" /></>}
          iconBg="bg-purple-50"
          iconColor="text-purple-600"
          label="Registered users"
          value={stats.users}
          isNumber
          delay={80}
        />
        <AdminStatCard
          icon={<><path strokeLinecap="round" strokeLinejoin="round" d="M16.5 6v.75m0 3v.75m0 3v.75m0 3V18m-9-5.25h5.25M7.5 15h3M3.375 5.25c-.621 0-1.125.504-1.125 1.125v3.026a2.999 2.999 0 010 5.198v3.026c0 .621.504 1.125 1.125 1.125h17.25c.621 0 1.125-.504 1.125-1.125v-3.026a2.999 2.999 0 010-5.198V6.375c0-.621-.504-1.125-1.125-1.125H3.375z" /></>}
          iconBg="bg-amber-50"
          iconColor="text-amber-600"
          label="Total bookings"
          value={stats.bookings}
          isNumber
          delay={160}
        />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-10">
        {adminLinks.map(({ to, icon, label, desc, bg }) => (
          <Link
            key={to}
            to={to}
            className="group relative bg-white rounded-2xl border border-slate-100 shadow-card p-5 hover:shadow-card-hover hover-lift transition-all duration-300 overflow-hidden"
          >
            <div className={`absolute -right-6 -bottom-6 w-32 h-32 bg-gradient-to-br ${bg} opacity-10 rounded-full group-hover:scale-150 transition-transform duration-500`} />
            <div className="relative flex items-center gap-4">
              <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${bg} flex items-center justify-center shadow-lg flex-shrink-0`}>
                <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>{icon}</svg>
              </div>
              <div>
                <h3 className="font-semibold text-slate-800 text-base">{label}</h3>
                <p className="text-sm text-slate-500 mt-0.5">{desc}</p>
              </div>
              <svg className="w-5 h-5 text-slate-400 ml-auto group-hover:translate-x-1 group-hover:text-blue-600 transition-all" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
              </svg>
            </div>
          </Link>
        ))}
      </div>

      <div className="bg-white rounded-2xl border border-slate-100 shadow-card overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
          <h2 className="font-semibold text-slate-800">Recent bookings</h2>
          <Link to="/admin/bookings" className="text-sm font-semibold text-blue-600 hover:text-blue-700 transition-colors">View all</Link>
        </div>
        {recentBookings.length === 0 ? (
          <div className="p-8 text-center text-slate-500">No bookings yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider bg-slate-50">
                  <th className="px-6 py-3">Reference</th>
                  <th className="px-6 py-3">User</th>
                  <th className="px-6 py-3">Flight ID</th>
                  <th className="px-6 py-3">Status</th>
                  <th className="px-6 py-3">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {recentBookings.map((b, idx) => (
                  <tr key={b.id} className="hover:bg-slate-50 transition-colors animate-fade-in-up" style={{ animationDelay: `${idx * 30}ms` }}>
                    <td className="px-6 py-3.5 font-medium text-slate-800 text-sm">{b.bookingReference}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{b.userEmail || b.userId}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-500 font-mono">{b.flightId?.slice(0, 8)}...</td>
                    <td className="px-6 py-3.5"><StatusBadge status={b.status} size="sm" /></td>
                    <td className="px-6 py-3.5 text-sm text-slate-500">{new Date(b.createdAt).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}