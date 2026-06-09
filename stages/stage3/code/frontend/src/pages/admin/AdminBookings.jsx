import React, { useEffect, useState } from 'react'
import axios from 'axios'
import PageHeader from '../../components/PageHeader'
import StatusBadge from '../../components/StatusBadge'
import Button from '../../components/Button'
import ErrorCard from '../../components/ErrorCard'
import toast from 'react-hot-toast'

const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function AdminBookings() {
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const token = localStorage.getItem('token')
  const headers = { Authorization: `Bearer ${token}` }

  const fetchBookings = () => {
    setLoading(true)
    axios.get(`${BOOKING_URL}/api/admin/bookings`, { headers })
      .then(r => setBookings(r.data.bookings || []))
      .catch(() => setError('Failed to load bookings'))
      .finally(() => setLoading(false))
  }

  useEffect(() => { fetchBookings() }, [])

  const handleCancel = async (id) => {
    if (!confirm('Cancel this booking?')) return
    try {
      await axios.delete(`${BOOKING_URL}/api/bookings/${id}`, { headers })
      toast.success('Booking cancelled')
      fetchBookings()
    } catch (err) {
      toast.error(err?.response?.data?.error || 'Cancel failed')
    }
  }

  if (loading) return <div className="animate-pulse space-y-4"><div className="h-12 bg-slate-200 rounded-xl" /><div className="h-64 bg-slate-100 rounded-xl" /></div>
  if (error) return <ErrorCard message={error} onRetry={fetchBookings} />

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="All Bookings"
        subtitle={`${bookings.length} total reservations`}
        breadcrumb={[{ label: 'Admin', to: '/admin' }, { label: 'Bookings' }]}
      />

      <div className="bg-white rounded-2xl border border-slate-100 shadow-card overflow-hidden">
        {bookings.length === 0 ? (
          <div className="p-10 text-center text-slate-500">No bookings found.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider bg-slate-50">
                  <th className="px-6 py-3">Reference</th>
                  <th className="px-6 py-3">User</th>
                  <th className="px-6 py-3">Flight ID</th>
                  <th className="px-6 py-3">Seat</th>
                  <th className="px-6 py-3">Status</th>
                  <th className="px-6 py-3">Booked</th>
                  <th className="px-6 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {bookings.map((b, idx) => (
                  <tr key={b.id} className="hover:bg-slate-50 transition-colors animate-fade-in-up" style={{ animationDelay: `${idx * 20}ms` }}>
                    <td className="px-6 py-3.5 font-medium text-slate-800 text-sm">{b.bookingReference}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{b.userEmail || b.userId}</td>
                    <td className="px-6 py-3.5 text-xs text-slate-500 font-mono">{b.flightId?.slice(0, 8)}...</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{b.seatNumber || '—'}</td>
                    <td className="px-6 py-3.5"><StatusBadge status={b.status} size="sm" /></td>
                    <td className="px-6 py-3.5 text-sm text-slate-500">{new Date(b.createdAt).toLocaleDateString()}</td>
                    <td className="px-6 py-3.5">
                      {b.status === 'CONFIRMED' && (
                        <button onClick={() => handleCancel(b.id)} className="text-xs font-semibold text-rose-500 hover:text-rose-600 transition-colors">Cancel</button>
                      )}
                    </td>
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