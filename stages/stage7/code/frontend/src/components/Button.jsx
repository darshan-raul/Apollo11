import React from 'react'

const variants = {
  primary:
    'bg-gradient-to-r from-blue-600 to-rose-600 text-white shadow-lg shadow-blue-500/25 hover:shadow-xl hover:shadow-blue-500/30 hover:-translate-y-0.5 active:translate-y-0',
  secondary:
    'bg-white text-slate-700 border border-slate-200 hover:bg-slate-50 hover:border-slate-300 shadow-sm hover:shadow-md',
  ghost:
    'bg-transparent text-slate-700 hover:bg-slate-100',
  danger:
    'bg-white text-rose-600 border border-rose-200 hover:bg-rose-50 hover:border-rose-300',
  outline:
    'bg-transparent text-blue-600 border border-blue-200 hover:bg-blue-50 hover:border-blue-300',
}

const sizes = {
  sm: 'px-3 py-1.5 text-sm',
  md: 'px-5 py-2.5 text-sm',
  lg: 'px-6 py-3 text-base',
  xl: 'px-8 py-4 text-base',
}

export default function Button({
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  loading = false,
  disabled = false,
  type = 'button',
  leftIcon = null,
  rightIcon = null,
  className = '',
  children,
  ...props
}) {
  const v = variants[variant] || variants.primary
  const sz = sizes[size] || sizes.md

  return (
    <button
      type={type}
      disabled={disabled || loading}
      className={`
        inline-flex items-center justify-center gap-2 font-semibold rounded-xl
        transition-all duration-200
        focus:outline-none focus:ring-2 focus:ring-blue-500/30
        disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0
        ${v}
        ${sz}
        ${fullWidth ? 'w-full' : ''}
        ${className}
      `}
      {...props}
    >
      {loading && (
        <svg className="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      )}
      {!loading && leftIcon && <span className="flex-shrink-0">{leftIcon}</span>}
      <span>{children}</span>
      {!loading && rightIcon && <span className="flex-shrink-0">{rightIcon}</span>}
    </button>
  )
}