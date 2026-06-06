import React from 'react'
import { Navigate } from 'react-router-dom'
import toast from 'react-hot-toast'

export default function ProtectedRoute({ user, children, requiredRole = null }) {
  if (!user) {
    return <Navigate to="/login" replace />
  }
  if (requiredRole && user.role !== requiredRole) {
    toast.error('You do not have permission to access that page.')
    return <Navigate to="/dashboard" replace />
  }
  return children
}