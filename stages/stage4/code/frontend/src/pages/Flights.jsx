import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { useParams } from 'react-router-dom'

const FLIGHT_URL = import.meta.env.VITE_FLIGHT_URL || 'http://localhost:8081'
const BOOKING_URL = import.meta.env.VITE_BOOKING_URL || 'http://localhost:8082'

export default function Flights() {
  const { id } = useParams()
  const [flight, setFlight] = useState(null)
  const [error, setError] = useState('')
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${FLIGHT_URL}/api/flights/${id}`).then(res => setFlight(res.data)).catch(() => setError('Flight not found'))
  }, [id])

  const handleBook = async () => {
    try {
      await axios.post(`${BOOKING_URL}/api/bookings`, { flightId: id }, { headers: { Authorization: `Bearer ${token}` } })
      alert('Booking confirmed!')
      window.location.href = '/bookings'
    } catch (err) {
      alert(err.response?.data?.error || 'Booking failed')
    }
  }

  if (error) return <p className="text-rose-500">{error}</p>
  if (!flight) return <p className="text-center py-10">Loading...</p>

  const statusColor = flight.status === 'SCHEDULED' ? 'bg-blue-100 text-blue-700' : flight.status === 'DELAYED' ? 'bg-yellow-100 text-yellow-700' : 'bg-green-100 text-green-700'

  return (
    <div>
      <h1 className="text-3xl font-bold text-slate-800 mb-6">Flight {flight.flightNumber}</h1>
      <div className="bg-white rounded-xl p-6 shadow">
        <div className="flex items-center gap-4 mb-6">
          <div className="text-center">
            <p className="text-2xl font-bold">{flight.origin}</p>
            <p className="text-slate-500">{new Date(flight.departureTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
          </div>
          <div className="flex-1 border-t-2 border-dashed border-slate-300 relative">
            <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 bg-slate-100 px-3 py-1 text-sm text-slate-500">{flight.duration} min</div>
          </div>
          <div className="text-center">
            <p className="text-2xl font-bold">{flight.destination}</p>
            <p className="text-slate-500">{new Date(flight.arrivalTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4 mb-6">
          <div>
            <p className="text-slate-500 text-sm">Departure</p>
            <p className="font-medium">{new Date(flight.departureTime).toLocaleDateString()}</p>
          </div>
          <div>
            <p className="text-slate-500 text-sm">Arrival</p>
            <p className="font-medium">{new Date(flight.arrivalTime).toLocaleDateString()}</p>
          </div>
          <div>
            <p className="text-slate-500 text-sm">Status</p>
            <span className={`inline-block px-2 py-1 rounded text-sm ${statusColor}`}>{flight.status}</span>
          </div>
          <div>
            <p className="text-slate-500 text-sm">Available Seats</p>
            <p className="font-medium">{flight.availableSeats}</p>
          </div>
        </div>
        <button onClick={handleBook} className="bg-rose-500 text-white px-8 py-3 rounded-lg font-semibold hover:bg-rose-600 transition">Book Now</button>
      </div>
    </div>
  )
}