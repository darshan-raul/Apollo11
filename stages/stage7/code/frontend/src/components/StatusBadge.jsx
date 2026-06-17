import React from 'react'

const statusStyles = {
  CONFIRMED: 'bg-green-50 text-green-700 border-green-200',
  PENDING: 'bg-amber-50 text-amber-700 border-amber-200',
  CANCELLED: 'bg-rose-50 text-rose-700 border-rose-200',
  SCHEDULED: 'bg-blue-50 text-blue-700 border-blue-200',
  DELAYED: 'bg-amber-50 text-amber-700 border-amber-200',
  BOARDING: 'bg-purple-50 text-purple-700 border-purple-200',
  DEPARTED: 'bg-slate-100 text-slate-700 border-slate-200',
  ARRIVED: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  PLATINUM: 'bg-amber-50 text-amber-700 border-amber-200',
  GOLD: 'bg-yellow-50 text-yellow-700 border-yellow-200',
  STANDARD: 'bg-blue-50 text-blue-700 border-blue-200',
  ADMIN: 'bg-purple-50 text-purple-700 border-purple-200',
  PASSENGER: 'bg-slate-100 text-slate-700 border-slate-200',
}

const defaultStyle = 'bg-slate-100 text-slate-700 border-slate-200'

const sizes = {
  sm: 'px-2 py-0.5 text-xs',
  md: 'px-2.5 py-1 text-xs',
  lg: 'px-3 py-1 text-sm',
}

export default function StatusBadge({ status, size = 'md', icon = false, className = '' }) {
  const style = statusStyles[status] || defaultStyle
  const sz = sizes[size] || sizes.md

  return (
    <span className={`inline-flex items-center gap-1 font-semibold rounded-full border whitespace-nowrap ${style} ${sz} ${className}`}>
      {icon && (
        <span className="w-1.5 h-1.5 rounded-full bg-current opacity-75" />
      )}
      {status}
    </span>
  )
}