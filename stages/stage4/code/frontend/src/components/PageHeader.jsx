import React from 'react'

export default function PageHeader({ title, subtitle, action = null, breadcrumb = null }) {
  return (
    <div className="mb-8 animate-fade-in">
      {breadcrumb && (
        <nav className="flex items-center gap-1.5 text-sm text-slate-500 mb-3">
          {breadcrumb.map((item, idx) => (
            <React.Fragment key={idx}>
              {idx > 0 && <svg className="w-3.5 h-3.5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" /></svg>}
              {item.href ? (
                <a href={item.href} className="hover:text-blue-600 transition-colors">{item.label}</a>
              ) : (
                <span className="text-slate-700 font-medium">{item.label}</span>
              )}
            </React.Fragment>
          ))}
        </nav>
      )}
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-3xl sm:text-4xl font-bold text-slate-800 tracking-tight">{title}</h1>
          {subtitle && <p className="text-slate-500 mt-2 text-sm sm:text-base max-w-2xl">{subtitle}</p>}
        </div>
        {action && <div className="flex-shrink-0">{action}</div>}
      </div>
    </div>
  )
}