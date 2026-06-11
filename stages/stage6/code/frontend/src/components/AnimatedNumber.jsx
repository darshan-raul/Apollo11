import React, { useEffect, useState } from 'react'

export function useCountUp(target, duration = 1200) {
  const [value, setValue] = useState(0)
  useEffect(() => {
    if (target === 0) { setValue(0); return }
    let startTime = null
    let frame
    const step = (timestamp) => {
      if (!startTime) startTime = timestamp
      const progress = Math.min((timestamp - startTime) / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      setValue(Math.floor(eased * target))
      if (progress < 1) frame = requestAnimationFrame(step)
      else setValue(target)
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [target, duration])
  return value
}

export default function AnimatedNumber({ value, duration = 1200, className = '' }) {
  const n = useCountUp(value, duration)
  return <span className={className}>{n.toLocaleString()}</span>
}