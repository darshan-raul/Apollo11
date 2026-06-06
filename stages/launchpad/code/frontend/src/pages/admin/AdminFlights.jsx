import React, { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import axios from 'axios'
import PageHeader from '../../components/PageHeader'
import StatusBadge from '../../components/StatusBadge'
import Button from '../../components/Button'
import ErrorCard from '../../components/ErrorCard'
import toast from 'react-hot-toast'

const FLIGHT_URL = import.meta.env.VITE_FLIGHT_URL || 'http://localhost:8081'

export default function AdminFlights() {
  const [flights, setFlights] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const navigate = useNavigate()
  const token = localStorage.getItem('token')
  const headers = { Authorization: `Bearer ${token}` }

  const fetchFlights = () => {
    setLoading(true)
    axios.get(`${FLIGHT_URL}/api/flights`, { headers })
      .then(r => setFlights(r.data.flights || []))
      .catch(() => setError('Failed to load flights'))
      .finally(() => setLoading(false))
  }

  useEffect(() => { fetchFlights() }, [])

  const handleDelete = async (id) => {
    if (!confirm('Delete this flight?')) return
    try {
      await axios.delete(`${FLIGHT_URL}/api/flights/${id}`, { headers })
      toast.success('Flight deleted')
      fetchFlights()
    } catch (err) {
      toast.error(err?.response?.data?.error || 'Delete failed')
    }
  }

  if (loading) return <div className="animate-pulse space-y-4"><div className="h-12 bg-slate-200 rounded-xl" /><div className="h-64 bg-slate-100 rounded-xl" /></div>
  if (error) return <ErrorCard message={error} onRetry={fetchFlights} />

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Manage Flights"
        subtitle={`${flights.length} flights in schedule`}
        breadcrumb={[{ label: 'Admin', to: '/admin' }, { label: 'Flights' }]}
        action={<Button onClick={() => navigate('/admin/flights/new')}>+ New Flight</Button>}
      />

      <div className="bg-white rounded-2xl border border-slate-100 shadow-card overflow-hidden">
        {flights.length === 0 ? (
          <div className="p-10 text-center text-slate-500">No flights found. Create your first flight.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider bg-slate-50">
                  <th className="px-6 py-3">Flight</th>
                  <th className="px-6 py-3">Route</th>
                  <th className="px-6 py-3">Departure</th>
                  <th className="px-6 py-3">Arrival</th>
                  <th className="px-6 py-3">Capacity</th>
                  <th className="px-6 py-3">Available</th>
                  <th className="px-6 py-3">Status</th>
                  <th className="px-6 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {flights.map((f, idx) => (
                  <tr key={f.id} className="hover:bg-slate-50 transition-colors animate-fade-in-up" style={{ animationDelay: `${idx * 20}ms` }}>
                    <td className="px-6 py-3.5 font-semibold text-slate-800">{f.flightNumber}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{f.origin} → {f.destination}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-500">{new Date(f.departureTime).toLocaleString()}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-500">{new Date(f.arrivalTime).toLocaleString()}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{f.totalCapacity}</td>
                    <td className="px-6 py-3.5 text-sm text-slate-600">{f.availableSeats ?? '—'}</td>
                    <td className="px-6 py-3.5"><StatusBadge status={f.status} size="sm" /></td>
                    <td className="px-6 py-3.5">
                      <div className="flex gap-2">
                        <button onClick={() => navigate(`/admin/flights/${f.id}`)} className="text-xs font-semibold text-blue-600 hover:text-blue-700 transition-colors">Edit</button>
                        <button onClick={() => handleDelete(f.id)} className="text-xs font-semibold text-rose-500 hover:text-rose-600 transition-colors">Delete</button>
                      </div>
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