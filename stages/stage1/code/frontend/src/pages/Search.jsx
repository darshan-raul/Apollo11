import React, { useState } from 'react'
import axios from 'axios'
import { Link } from 'react-router-dom'

const SEARCH_URL = import.meta.env.VITE_SEARCH_URL || 'http://localhost:8083'

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
      const res = await axios.get(`${SEARCH_URL}/api/search?origin=${origin}&destination=${destination}&date=${date}`)
      setResults(res.data.results || [])
    } catch (err) {
      setError('Search failed. Please try again.')
    }
    setLoading(false)
  }

  const swapAirports = () => {
    const temp = origin
    setOrigin(destination)
    setDestination(temp)
  }

  const airports = ['BOM', 'DEL', 'SIN', 'DXB', 'LHR', 'JFK']

  return (
    <div>
      <h1 className="text-3xl font-bold text-slate-800 mb-6">Search Flights</h1>
      <div className="bg-white rounded-xl p-6 shadow mb-8">
        <form onSubmit={handleSearch}>
          <div className="flex items-center gap-4 mb-4">
            <div className="flex-1">
              <label className="block text-sm font-medium text-slate-600 mb-1">From</label>
              <select value={origin} onChange={e => setOrigin(e.target.value)} required
                className="w-full px-4 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-400">
                <option value="">Select</option>
                {airports.map(a => <option key={a} value={a}>{a}</option>)}
              </select>
            </div>
            <button type="button" onClick={swapAirports} className="mt-6 p-2 hover:bg-slate-100 rounded-full">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7h12M8 17h12M4 12h16" />
              </svg>
            </button>
            <div className="flex-1">
              <label className="block text-sm font-medium text-slate-600 mb-1">To</label>
              <select value={destination} onChange={e => setDestination(e.target.value)} required
                className="w-full px-4 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-400">
                <option value="">Select</option>
                {airports.map(a => <option key={a} value={a}>{a}</option>)}
              </select>
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-slate-600 mb-1">Date</label>
              <input type="date" value={date} onChange={e => setDate(e.target.value)} required
                className="w-full px-4 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-400" />
            </div>
          </div>
          <button type="submit" disabled={loading}
            className="bg-rose-500 text-white px-8 py-2 rounded-lg font-semibold hover:bg-rose-600 disabled:opacity-50">
            {loading ? 'Searching...' : 'Search'}
          </button>
        </form>
      </div>
      {error && <p className="text-rose-500 mb-4">{error}</p>}
      {results.length === 0 && !loading && <p className="text-slate-500">No flights found.</p>}
      {results.length > 0 && (
        <div className="space-y-4">
          {results.map(f => (
            <div key={f.id} className="bg-white rounded-xl p-4 shadow flex items-center justify-between">
              <div>
                <p className="text-xl font-bold text-slate-800">{f.flightNumber}</p>
                <p className="text-slate-500">{f.origin} → {f.destination}</p>
                <p className="text-sm text-slate-400">{new Date(f.departureTime).toLocaleString()} · {f.duration} min · {f.availableSeats} seats</p>
              </div>
              <Link to={`/flights/${f.id}`} className="bg-slate-900 text-white px-6 py-2 rounded-lg hover:bg-slate-700">View</Link>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}