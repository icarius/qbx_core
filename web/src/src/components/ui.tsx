import type { ButtonHTMLAttributes, ReactNode } from 'react'
import './ui.css'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'ghost' | 'danger' | 'success'
  size?: 'sm' | 'md'
}

export function Button({ variant = 'ghost', size = 'md', className = '', ...rest }: ButtonProps) {
  return <button className={`btn btn-${variant} btn-${size} ${className}`} {...rest} />
}

export function StatBar({ label, value, tone }: { label: string; value: number; tone?: 'fuel' | 'engine' | 'body' }) {
  const pct = Math.max(0, Math.min(100, value))
  return (
    <div className="statbar">
      <div className="statbar-head">
        <span>{label}</span>
        <span>{Math.round(pct)}%</span>
      </div>
      <div className="statbar-track">
        <div className={`statbar-fill statbar-${tone ?? 'fuel'}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

export function Modal({ title, onClose, children, footer }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="modal-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-head">
          <h3>{title}</h3>
          <button className="icon-btn" onClick={onClose} aria-label="Close">
            ✕
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  )
}

export function EmptyState({ label }: { label: string }) {
  return (
    <div className="empty-state">
      <div className="empty-icon">🚗</div>
      <p>{label}</p>
    </div>
  )
}
