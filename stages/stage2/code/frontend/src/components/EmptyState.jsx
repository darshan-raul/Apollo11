import React from 'react'
import Button from './Button'

export default function EmptyState({ icon, title, message, action }) {
  return (
    <div className="bg-white rounded-2xl border border-slate-100 shadow-card p-10 text-center animate-fade-in">
      <div className="w-16 h-16 bg-gradient-to-br from-blue-50 to-rose-50 rounded-2xl flex items-center justify-center mx-auto mb-5">
        {icon || (
          <svg className="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9 5.25h.008v.008H12v-.008z" />
          </svg>
        )}
      </div>
      <h3 className="text-lg font-semibold text-slate-800 mb-1.5">{title}</h3>
      {message && <p className="text-slate-500 text-sm max-w-md mx-auto mb-6">{message}</p>}
      {action && <div className="flex justify-center">{action}</div>}
    </div>
  )
}