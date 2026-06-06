import React from 'react'
import Logo from './Logo'

export default function AuthCard({ title, subtitle, children, footer }) {
  return (
    <div className="w-full max-w-md mx-auto animate-fade-in">
      <div className="bg-white rounded-2xl border border-slate-100 shadow-card p-8 sm:p-10">
        <div className="text-center mb-8">
          <div className="inline-flex mb-5">
            <Logo size="lg" />
          </div>
          <h1 className="text-2xl sm:text-3xl font-bold text-slate-800 tracking-tight">
            {title}
          </h1>
          {subtitle && (
            <p className="text-slate-500 mt-2 text-sm sm:text-base">{subtitle}</p>
          )}
        </div>
        {children}
        {footer && (
          <div className="mt-6 pt-6 border-t border-slate-100 text-center text-sm text-slate-600">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}