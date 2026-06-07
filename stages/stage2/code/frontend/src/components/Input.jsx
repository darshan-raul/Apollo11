import React, { useState } from 'react'

export default function Input({
  type = 'text',
  name,
  value,
  onChange,
  onBlur,
  label,
  error = '',
  hint = '',
  leftIcon = null,
  disabled = false,
  autoComplete,
  required = false,
  className = '',
  inputClassName = '',
}) {
  const [focused, setFocused] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const isPassword = type === 'password'
  const inputType = isPassword && showPassword ? 'text' : type
  const hasValue = value !== undefined && value !== null && String(value).length > 0
  const isFloating = focused || hasValue

  return (
    <div className={`relative ${className}`}>
      <div className="relative">
        {leftIcon && (
          <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none">
            {leftIcon}
          </div>
        )}
        <input
          type={inputType}
          name={name}
          value={value}
          onChange={onChange}
          onBlur={(e) => { setFocused(false); onBlur && onBlur(e) }}
          onFocus={() => setFocused(true)}
          disabled={disabled}
          autoComplete={autoComplete}
          required={required}
          placeholder=" "
          className={`
            peer w-full px-4 py-3 ${leftIcon ? 'pl-11' : ''} ${isPassword ? 'pr-11' : ''}
            bg-white border rounded-xl text-slate-800 placeholder-transparent
            focus:outline-none focus:ring-2 focus:ring-blue-500/20
            transition-all duration-200
            disabled:bg-slate-50 disabled:text-slate-400 disabled:cursor-not-allowed
            ${error
              ? 'border-rose-400 focus:border-rose-500 focus:ring-rose-500/20'
              : 'border-slate-200 focus:border-blue-500'
            }
            ${inputClassName}
          `}
        />
        <label
          className={`
            absolute ${leftIcon ? 'left-11' : 'left-4'}
            pointer-events-none transition-all duration-200 bg-white px-1
            ${isFloating
              ? 'top-0 -translate-y-1/2 text-xs font-medium'
              : 'top-1/2 -translate-y-1/2 text-sm'
            }
            ${focused
              ? error ? 'text-rose-500' : 'text-blue-600'
              : error ? 'text-rose-500' : 'text-slate-500'
            }
          `}
        >
          {label}
        </label>
        {isPassword && (
          <button
            type="button"
            onClick={() => setShowPassword(s => !s)}
            tabIndex={-1}
            className="absolute right-3 top-1/2 -translate-y-1/2 p-1 text-slate-400 hover:text-slate-600 transition-colors"
          >
            {showPassword ? (
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
              </svg>
            ) : (
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
              </svg>
            )}
          </button>
        )}
      </div>
      {(error || hint) && (
        <p className={`mt-1.5 text-xs ${error ? 'text-rose-600' : 'text-slate-500'}`}>
          {error || hint}
        </p>
      )}
    </div>
  )
}