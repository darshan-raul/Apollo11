import React, { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import axios from 'axios'
import toast from 'react-hot-toast'
import PageHeader from '../../components/PageHeader'
import Input from '../../components/Input'
import Button from '../../components/Button'

const FLIGHT_URL = import.meta.env.VITE_FLIGHT_URL || 'http://localhost:8081'

const EMPTY_FORM = {
  flightNumber: '',
  origin: '',
  destination: '',
  departureTime: '',
  arrivalTime: '',
  totalCapacity: '',
  status: 'SCHEDULED',
}

export default function AdminFlightForm() {
  const { id } = useParams()
  const isEdit = Boolean(id)
  const navigate = useNavigate()
  const [form, setForm] = useState(EMPTY_FORM)
  const [loading, setLoading] = useState(false)
  const [fetching, setFetching] = useState(isEdit)
  const token = localStorage.getItem('token')
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }

  useEffect(() => {
    if (isEdit) {
      axios.get(`${FLIGHT_URL}/api/flights/${id}`, { headers })
        .then(r => {
          const f = r.data.flight || r.data
          setForm({
            flightNumber: f.flightNumber || '',
            origin: f.origin || '',
            destination: f.destination || '',
            departureTime: f.departureTime ? f.departureTime.slice(0, 16) : '',
            arrivalTime: f.arrivalTime ? f.arrivalTime.slice(0, 16) : '',
            totalCapacity: f.totalCapacity || '',
            status: f.status || 'SCHEDULED',
          })
        })
        .catch(() => toast.error('Failed to load flight'))
        .finally(() => setFetching(false))
    }
  }, [id, isEdit])

  const set = (k) => (e) => setForm(f => ({ ...f, [k]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    const payload = {
      ...form,
      totalCapacity: parseInt(form.totalCapacity, 10),
    }
    try {
      if (isEdit) {
        await axios.put(`${FLIGHT_URL}/api/flights/${id}`, payload, { headers })
        toast.success('Flight updated successfully')
      } else {
        await axios.post(`${FLIGHT_URL}/api/flights`, payload, { headers })
        toast.success('Flight created successfully')
      }
      navigate('/admin/flights')
    } catch (err) {
      toast.error(err?.response?.data?.error || 'Operation failed')
    } finally {
      setLoading(false)
    }
  }

  if (fetching) {
    return (
      <div className="animate-fade-in">
        <div className="h-8 w-48 bg-slate-200 rounded animate-pulse mb-4" />
        <div className="h-4 w-64 bg-slate-100 rounded animate-pulse" />
      </div>
    )
  }

  return (
    <div className="animate-fade-in max-w-2xl">
      <PageHeader
        title={isEdit ? 'Edit Flight' : 'Create Flight'}
        subtitle={isEdit ? `Editing flight ${id?.slice(0, 8)}...` : 'Add a new flight to the schedule'}
        breadcrumb={[{ label: 'Admin', to: '/admin' }, { label: 'Flights', to: '/admin/flights' }, { label: isEdit ? 'Edit' : 'Create' }]}
      />

      <form onSubmit={handleSubmit} className="bg-white rounded-2xl border border-slate-100 shadow-card p-6 space-y-5">
        <div className="grid grid-cols-2 gap-4">
          <Input label="Flight Number" value={form.flightNumber} onChange={set('flightNumber')} placeholder="AA101" required />
          <Input label="Origin Airport" value={form.origin} onChange={set('origin')} placeholder="BOM" required maxLength={3} />
          <Input label="Destination Airport" value={form.destination} onChange={set('destination')} placeholder="DEL" required maxLength={3} />
          <Input label="Total Capacity" type="number" value={form.totalCapacity} onChange={set('totalCapacity')} placeholder="180" required min="1" />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">Departure</label>
            <input type="datetime-local" value={form.departureTime} onChange={set('departureTime')} required
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 bg-slate-50 text-slate-700 text-sm focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 transition-all" />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">Arrival</label>
            <input type="datetime-local" value={form.arrivalTime} onChange={set('arrivalTime')} required
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 bg-slate-50 text-slate-700 text-sm focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 transition-all" />
          </div>
        </div>
        {isEdit && (
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">Status</label>
            <select value={form.status} onChange={set('status')}
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 bg-slate-50 text-slate-700 text-sm focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100 transition-all">
              <option value="SCHEDULED">SCHEDULED</option>
              <option value="BOARDING">BOARDING</option>
              <option value="DEPARTED">DEPARTED</option>
              <option value="ARRIVED">ARRIVED</option>
              <option value="CANCELLED">CANCELLED</option>
              <option value="DELAYED">DELAYED</option>
            </select>
          </div>
        )}
        <div className="flex gap-3 pt-2">
          <Button type="submit" loading={loading}>{isEdit ? 'Update Flight' : 'Create Flight'}</Button>
          <Button variant="secondary" onClick={() => navigate('/admin/flights')}>Cancel</Button>
        </div>
      </form>
    </div>
  )
}