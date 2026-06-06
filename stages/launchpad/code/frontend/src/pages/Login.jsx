import React, { useState } from 'react'
import axios from 'axios'
import { useNavigate } from 'react-router-dom'

const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'

export default function Login({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [fieldErrors, setFieldErrors] = useState({})
  const navigate = useNavigate()

  const validateEmail = (val) => {
    if (!val) return 'Email is required'
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val)) return 'Please enter a valid email'
    return ''
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const emailErr = validateEmail(email)
    const passErr = !password ? 'Password is required' : ''
    if (emailErr || passErr) {
      setFieldErrors({ email: emailErr, password: passErr })
      return
    }
    try {
      const res = await axios.post(`${IDENTITY_URL}/api/users/login`, { email, password })
      onLogin(res.data.token)
      navigate('/dashboard')
    } catch (err) {
      setError(err.response?.data?.detail || 'Login failed')
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-900 relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-br from-blue-900/40 via-slate-900 to-rose-900/40" />
      <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-blue-500/10 rounded-full blur-3xl" />
      <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-rose-500/10 rounded-full blur-3xl" />

      <div className="relative w-full max-w-md mx-4">
        <div className="absolute inset-0 bg-gradient-to-r from-blue-500/20 to-rose-500/20 rounded-2xl blur-xl" />
        <div className="relative bg-slate-900/80 backdrop-blur-xl border border-white/10 rounded-2xl p-8 shadow-2xl">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-14 h-14 bg-gradient-to-br from-blue-500 to-rose-500 rounded-xl mb-4">
              <svg className="w-7 h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 14l9-5-9-5-9 5 9 5z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 14l6.16-3.422a12.083 12.083 0 01.665 6.479A11.952 11.952 0 0012 20.055a11.952 11.952 0 00-6.824-2.998 12.078 12.078 0 01.665-6.479L12 14z" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold text-white">Welcome Back</h2>
            <p className="text-slate-400 mt-1 text-sm">Sign in to your Apollo Airlines account</p>
          </div>

          {error && (
            <div className="mb-4 px-4 py-3 bg-rose-500/10 border border-rose-500/30 rounded-lg text-rose-400 text-sm text-center">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-5">
            <div className="relative">
              <input
                type="email"
                value={email}
                onChange={e => { setEmail(e.target.value); setError(''); setFieldErrors(p => ({...p, email: ''})); }}
                onBlur={() => { const err = validateEmail(email); setFieldErrors(p => ({...p, email: err})); }}
                placeholder=" "
                className={`peer w-full px-4 py-3 bg-slate-800/50 border rounded-lg text-white placeholder-transparent focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500 transition-all ${fieldErrors.email ? 'border-rose-500' : 'border-slate-700'}`}
              />
              <label className="absolute left-4 top-3 text-slate-400 text-sm transition-all duration-200 pointer-events-none peer-placeholder-shown:top-3 peer-placeholder-shown:text-base peer-focus:top-1 peer-focus:text-xs peer-focus:text-blue-400 bg-slate-800 px-1">Email</label>
              {fieldErrors.email && <p className="mt-1 text-xs text-rose-400">{fieldErrors.email}</p>}
            </div>

            <div className="relative">
              <input
                type="password"
                value={password}
                onChange={e => { setPassword(e.target.value); setError(''); setFieldErrors(p => ({...p, password: ''})); }}
                onBlur={() => { if (!password) setFieldErrors(p => ({...p, password: 'Password is required'})); }}
                placeholder=" "
                className={`peer w-full px-4 py-3 bg-slate-800/50 border rounded-lg text-white placeholder-transparent focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500 transition-all ${fieldErrors.password ? 'border-rose-500' : 'border-slate-700'}`}
              />
              <label className="absolute left-4 top-3 text-slate-400 text-sm transition-all duration-200 pointer-events-none peer-placeholder-shown:top-3 peer-placeholder-shown:text-base peer-focus:top-1 peer-focus:text-xs peer-focus:text-blue-400 bg-slate-800 px-1">Password</label>
              {fieldErrors.password && <p className="mt-1 text-xs text-rose-400">{fieldErrors.password}</p>}
            </div>

            <button
              type="submit"
              className="w-full py-3 bg-gradient-to-r from-blue-600 to-rose-600 text-white font-semibold rounded-lg shadow-lg shadow-blue-500/25 hover:shadow-xl hover:shadow-blue-500/30 hover:-translate-y-0.5 active:translate-y-0 transition-all duration-200"
            >
              Sign In
            </button>
          </form>

          <p className="text-center text-slate-400 mt-6 text-sm">
            Don't have an account?{' '}
            <a href="/register" className="text-blue-400 hover:text-blue-300 font-medium transition-colors">Register</a>
          </p>
        </div>
      </div>
    </div>
  )
}