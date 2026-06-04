import React, { useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'

const SEARCH_API = 'http://localhost:8083'

export default function Search() {
  const [origin, setOrigin] = useState('')
  const [destination, setDestination] = useState('')
  const [date, setDate] = useState('')
  const [results, setResults] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleSearch = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    try {
      const res = await axios.get(`${SEARCH_API}/api/search?origin=${origin}&destination=${destination}&date=${date}`)
      setResults(res.data.results || [])
    } catch (err) {
      setError('Search failed. Please try again.')
    }
    setLoading(false)
  }

  const airports = ['BOM', 'DEL', 'SIN', 'DXB', 'LHR', 'JFK']

  return (
    <div>
      <h1 style={{ color: '#1a1a2e' }}>Search Flights</h1>
      <form onSubmit={handleSearch} style={{ backgroundColor: 'white', padding: '1.5rem', borderRadius: '8px', marginBottom: '2rem', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '1rem', marginBottom: '1rem' }}>
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 'bold' }}>From</label>
            <select value={origin} onChange={e => setOrigin(e.target.value)} required style={{ width: '100%', padding: '0.5rem', borderRadius: '4px', border: '1px solid #ccc' }}>
              <option value="">Select</option>
              {airports.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
          </div>
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 'bold' }}>To</label>
            <select value={destination} onChange={e => setDestination(e.target.value)} required style={{ width: '100%', padding: '0.5rem', borderRadius: '4px', border: '1px solid #ccc' }}>
              <option value="">Select</option>
              {airports.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
          </div>
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 'bold' }}>Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)} required style={{ width: '100%', padding: '0.5rem', borderRadius: '4px', border: '1px solid #ccc' }} />
          </div>
        </div>
        <button type="submit" disabled={loading} style={{ backgroundColor: '#e94560', color: 'white', padding: '0.75rem 2rem', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '1rem' }}>{loading ? 'Searching...' : 'Search'}</button>
      </form>
      {error && <p style={{ color: 'red' }}>{error}</p>}
      {results.length === 0 && !loading && <p>No flights found.</p>}
      {results.length > 0 && (
        <div style={{ display: 'grid', gap: '1rem' }}>
          {results.map(f => (
            <div key={f.id} style={{ backgroundColor: 'white', padding: '1rem', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <p style={{ fontSize: '1.25rem', fontWeight: 'bold' }}>{f.flightNumber}</p>
                <p>{f.origin} → {f.destination}</p>
                <p>Departure: {new Date(f.departureTime).toLocaleString()}</p>
                <p>Duration: {f.duration} min | Seats: {f.availableSeats}</p>
              </div>
              <Link to={`/flights/${f.id}`} style={{ backgroundColor: '#1a1a2e', color: 'white', padding: '0.5rem 1rem', textDecoration: 'none', borderRadius: '4px' }}>View</Link>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}