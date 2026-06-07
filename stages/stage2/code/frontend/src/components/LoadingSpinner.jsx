import React from 'react'

const sizes = {
  sm: 'w-4 h-4 border-2',
  md: 'w-6 h-6 border-2',
  lg: 'w-10 h-10 border-[3px]',
  xl: 'w-16 h-16 border-4',
}

export default function LoadingSpinner({ size = 'md', className = '', text = null }) {
  const s = sizes[size] || sizes.md
  return (
    <div className={`flex flex-col items-center justify-center gap-3 ${className}`}>
      <div className={`${s} border-blue-500 border-t-transparent rounded-full animate-spin`} />
      {text && <p className="text-sm text-slate-500">{text}</p>}
    </div>
  )
}