import React, { useState } from 'react'
import axios from 'axios'
import { Link, useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import AuthCard from '../components/AuthCard'
import Input from '../components/Input'
import Button from '../components/Button'

const IDENTITY_URL = import.meta.env.VITE_IDENTITY_URL || 'http://localhost:8080'

export default function Login({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [fieldErrors, setFieldErrors] = useState({})
  const [loading, setLoading] = useState(false)
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
    setLoading(true)
    try {
      const res = await axios.post(`${IDENTITY_URL}/api/users/login`, { email, password })
      onLogin(res.data.token)
      toast.success('Welcome back!')
      setTimeout(() => navigate('/dashboard'), 250)
    } catch (err) {
      const msg = err.response?.data?.detail || 'Login failed. Please try again.'
      toast.error(msg)
      setLoading(false)
    }
  }

  return (
    <div className="py-8 sm:py-12">
      <AuthCard
        title="Welcome back"
        subtitle="Sign in to your Apollo Airlines account"
        footer={
          <span>
            Don't have an account?{' '}
            <Link to="/register" className="font-semibold text-blue-600 hover:text-blue-700 transition-colors">
              Create one
            </Link>
          </span>
        }
      >
        <form onSubmit={handleSubmit} className="space-y-5">
          <Input
            type="email"
            name="email"
            label="Email address"
            value={email}
            onChange={(e) => { setEmail(e.target.value); setFieldErrors(p => ({ ...p, email: '' })) }}
            onBlur={() => setFieldErrors(p => ({ ...p, email: validateEmail(email) }))}
            error={fieldErrors.email}
            autoComplete="email"
            leftIcon={
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75" />
              </svg>
            }
          />

          <Input
            type="password"
            name="password"
            label="Password"
            value={password}
            onChange={(e) => { setPassword(e.target.value); setFieldErrors(p => ({ ...p, password: '' })) }}
            onBlur={() => setFieldErrors(p => ({ ...p, password: password ? '' : 'Password is required' }))}
            error={fieldErrors.password}
            autoComplete="current-password"
            leftIcon={
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
              </svg>
            }
          />

          <div className="pt-1">
            <Button type="submit" fullWidth size="lg" loading={loading}>
              {loading ? 'Signing in...' : 'Sign in'}
            </Button>
          </div>
        </form>
      </AuthCard>
    </div>
  )
}