import React from 'react'
import AnimatedNumber from './AnimatedNumber'

export default function AdminStatCard({ icon, iconBg, iconColor, label, value, isNumber = false, delay = 0, subtitle = null }) {
  return (
    <div
      className="bg-white rounded-2xl border border-slate-100 shadow-card p-6 hover:shadow-card-hover hover-lift transition-all duration-300 animate-fade-in-up"
      style={{ animationDelay: `${delay}ms` }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className={`w-11 h-11 rounded-xl flex items-center justify-center ${iconBg}`}>
            <svg className={`w-5 h-5 ${iconColor}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.8}>
              {icon}
            </svg>
          </div>
          <div>
            <p className="text-sm font-medium text-slate-500">{label}</p>
            {subtitle && <p className="text-xs text-slate-400 mt-0.5">{subtitle}</p>}
          </div>
        </div>
        <p className="text-3xl font-bold text-slate-800 flex-shrink-0">
          {isNumber ? <AnimatedNumber value={value} /> : value}
        </p>
      </div>
    </div>
  )
}