import React, { useState } from 'react'
import axios from 'axios'
import { useNavigate } from 'react-router-dom'

const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'

export default function Login({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    try {
      const res = await axios.post(`${IDENTITY_URL}/api/users/login`, { email, password })
      onLogin(res.data.token)
      navigate('/dashboard')
    } catch (err) {
      setError(err.response?.data?.detail || 'Login failed')
    }
  }

  return (
    <div className="max-w-md mx-auto mt-16">
      <div className="bg-gradient-to-br from-slate-900 to-blue-900 rounded-xl p-8 shadow-xl">
        <h2 className="text-2xl font-bold text-white text-center mb-6">Sign in to Apollo Airlines</h2>
        {error && <div className="bg-rose-500/20 border border-rose-500 text-rose-200 px-4 py-2 rounded mb-4 text-center">{error}</div>}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-slate-300 text-sm font-medium mb-1">Email</label>
            <input type="email" value={email} onChange={e => setEmail(e.target.value)} required
              className="w-full px-4 py-2 rounded bg-slate-800 border border-slate-600 text-white focus:outline-none focus:ring-2 focus:ring-blue-400" />
          </div>
          <div>
            <label className="block text-slate-300 text-sm font-medium mb-1">Password</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} required
              className="w-full px-4 py-2 rounded bg-slate-800 border border-slate-600 text-white focus:outline-none focus:ring-2 focus:ring-blue-400" />
          </div>
          <button type="submit" className="w-full bg-rose-500 text-white py-2 rounded font-semibold hover:bg-rose-600 transition">Login</button>
        </form>
        <p className="text-center text-slate-300 mt-4">
          Don't have an account? <a href="/register" className="text-blue-300 hover:underline">Register</a>
        </p>
      </div>
    </div>
  )
}