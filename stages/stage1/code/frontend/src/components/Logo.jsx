import React from 'react'

export default function Logo({ size = 'md', className = '' }) {
  const sizes = {
    sm: { box: 'w-7 h-7', svg: 'w-4 h-4' },
    md: { box: 'w-9 h-9', svg: 'w-5 h-5' },
    lg: { box: 'w-14 h-14', svg: 'w-7 h-7' },
    xl: { box: 'w-20 h-20', svg: 'w-10 h-10' },
  }
  const s = sizes[size] || sizes.md

  return (
    <div className={`inline-flex items-center justify-center ${s.box} bg-gradient-to-br from-blue-500 to-rose-500 rounded-xl shadow-lg shadow-blue-500/20 ${className}`}>
      <svg className={`${s.svg} text-white`} fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M2.5 19.5L21 12 2.5 4.5l3 7.5-3 7.5zM7 12h14" />
      </svg>
    </div>
  )
}