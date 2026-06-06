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
    <div className="animate-fade-in">
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-slate-800">Search Flights</h1>
        <p className="text-slate-500 mt-1">Find your perfect flight across global destinations</p>
      </div>

      <div className="bg-white rounded-2xl p-6 shadow-card border border-slate-100 mb-8">
        <form onSubmit={handleSearch}>
          <div className="flex items-center gap-4 mb-4">
            <div className="flex-1">
              <label className="block text-sm font-semibold text-slate-700 mb-2">From</label>
              <select
                value={origin}
                onChange={e => setOrigin(e.target.value)}
                required
                className="w-full px-4 py-3 rounded-xl border border-slate-200 bg-slate-50 text-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all appearance-none cursor-pointer"
              >
                <option value="">Select origin</option>
                {airports.map(a => <option key={a} value={a}>{a}</option>)}
              </select>
            </div>

            <button
              type="button"
              onClick={swapAirports}
              className="mt-7 p-3 bg-slate-100 hover:bg-slate-200 rounded-xl transition-all"
            >
              <svg className="w-5 h-5 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
              </svg>
            </button>

            <div className="flex-1">
              <label className="block text-sm font-semibold text-slate-700 mb-2">To</label>
              <select
                value={destination}
                onChange={e => setDestination(e.target.value)}
                required
                className="w-full px-4 py-3 rounded-xl border border-slate-200 bg-slate-50 text-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all appearance-none cursor-pointer"
              >
                <option value="">Select destination</option>
                {airports.map(a => <option key={a} value={a}>{a}</option>)}
              </select>
            </div>

            <div className="flex-1">
              <label className="block text-sm font-semibold text-slate-700 mb-2">Date</label>
              <input
                type="date"
                value={date}
                onChange={e => setDate(e.target.value)}
                required
                className="w-full px-4 py-3 rounded-xl border border-slate-200 bg-slate-50 text-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all"
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full md:w-auto md:px-10 py-3 bg-gradient-to-r from-blue-600 to-rose-600 text-white font-semibold rounded-xl hover:opacity-90 disabled:opacity-50 transition-all shadow-lg shadow-blue-500/20 hover:-translate-y-0.5"
          >
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <svg className="animate-spin w-5 h-5" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Searching...
              </span>
            ) : (
              'Search Flights'
            )}
          </button>
        </form>
      </div>

      {error && (
        <div className="mb-4 px-4 py-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-600 text-center">
          {error}
        </div>
      )}

      {results.length === 0 && !loading && (
        <div className="text-center py-12 text-slate-400">
          <svg className="w-16 h-16 mx-auto mb-4 text-slate-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <p>Select origin, destination and date to search for flights</p>
        </div>
      )}

      {results.length > 0 && (
        <div className="space-y-4">
          {results.map(f => (
            <div key={f.id} className="bg-white rounded-xl p-5 shadow-card hover:shadow-card-hover hover-lift border border-slate-100 group">
              <div className="flex items-center justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-4 mb-2">
                    <div className="px-3 py-1 bg-slate-800 text-white rounded-lg font-bold text-sm">{f.flightNumber}</div>
                    <span className="text-2xl text-slate-400">{f.origin}</span>
                    <svg className="w-5 h-5 text-slate-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                    </svg>
                    <span className="text-2xl text-slate-400">{f.destination}</span>
                  </div>
                  <div className="flex items-center gap-4 text-sm text-slate-500">
                    <span className="flex items-center gap-1">
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      {f.duration} min
                    </span>
                    <span className="flex items-center gap-1">
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      {new Date(f.departureTime).toLocaleString()}
                    </span>
                    <span className="flex items-center gap-1">
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      {f.availableSeats} seats
                    </span>
                  </div>
                </div>
                <Link
                  to={`/flights/${f.id}`}
                  className="ml-4 px-6 py-3 bg-gradient-to-r from-blue-600 to-rose-600 text-white font-semibold rounded-xl hover:opacity-90 transition-all shadow-lg shadow-blue-500/20 group-hover:-translate-y-0.5"
                >
                  View Flight
                </Link>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}