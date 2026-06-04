import React, { useEffect, useState } from 'react'
import axios from 'axios'
import { useParams } from 'react-router-dom'

const FLIGHT_API = 'http://localhost:8081'
const BOOKING_API = 'http://localhost:8082'

export default function Flights() {
  const { id } = useParams()
  const [flight, setFlight] = useState(null)
  const [error, setError] = useState('')
  const token = localStorage.getItem('token')

  useEffect(() => {
    axios.get(`${FLIGHT_API}/api/flights/${id}`).then(res => setFlight(res.data)).catch(() => setError('Flight not found'))
  }, [id])

  const handleBook = async () => {
    try {
      await axios.post(`${BOOKING_API}/api/bookings`, { flightId: id }, { headers: { Authorization: `Bearer ${token}` } })
      alert('Booking confirmed!')
      window.location.href = '/bookings'
    } catch (err) {
      alert(err.response?.data?.error || 'Booking failed')
    }
  }

  if (error) return <p style={{ color: 'red' }}>{error}</p>
  if (!flight) return <p>Loading...</p>

  return (
    <div>
      <h1 style={{ color: '#1a1a2e' }}>Flight {flight.flightNumber}</h1>
      <div style={{ backgroundColor: 'white', padding: '1.5rem', borderRadius: '8px', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}>
        <p><strong>Route:</strong> {flight.origin} → {flight.destination}</p>
        <p><strong>Departure:</strong> {new Date(flight.departureTime).toLocaleString()}</p>
        <p><strong>Arrival:</strong> {new Date(flight.arrivalTime).toLocaleString()}</p>
        <p><strong>Status:</strong> {flight.status}</p>
        <p><strong>Available Seats:</strong> {flight.availableSeats}</p>
        <button onClick={handleBook} style={{ backgroundColor: '#e94560', color: 'white', padding: '0.75rem 2rem', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '1rem', marginTop: '1rem' }}>Book Now</button>
      </div>
    </div>
  )
}