import { useEffect, useRef, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'

type ModalProps = {
  title: string
  description?: string
  eyebrow?: string
  children: ReactNode
  footer?: ReactNode
  onClose: () => void
  size?: 'medium' | 'large'
  closeDisabled?: boolean
}

export default function Modal({ title, description, eyebrow, children, footer, onClose, size = 'medium', closeDisabled = false }: ModalProps) {
  const panelRef = useRef<HTMLDivElement>(null)
  const previousFocus = useRef<HTMLElement | null>(null)

  useEffect(() => {
    previousFocus.current = document.activeElement as HTMLElement | null
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const frame = window.requestAnimationFrame(() => {
      const target = panelRef.current?.querySelector<HTMLElement>('input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled])')
      target?.focus()
    })
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !closeDisabled) onClose()
      if (event.key !== 'Tab' || !panelRef.current) return
      const nodes = Array.from(panelRef.current.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'))
      if (!nodes.length) return
      const first = nodes[0], last = nodes[nodes.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => {
      window.cancelAnimationFrame(frame)
      document.removeEventListener('keydown', onKeyDown)
      document.body.style.overflow = previousOverflow
      previousFocus.current?.focus()
    }
  }, [closeDisabled, onClose])

  return createPortal(
    <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget && !closeDisabled) onClose() }}>
      <div ref={panelRef} className={`modal-panel modal-${size}`} role="dialog" aria-modal="true" aria-labelledby="modal-title" aria-describedby={description ? 'modal-description' : undefined}>
        <header className="modal-header">
          <div className="modal-heading-copy">
            {eyebrow && <span className="modal-eyebrow">{eyebrow}</span>}
            <h2 id="modal-title">{title}</h2>
            {description && <p id="modal-description">{description}</p>}
          </div>
          <button type="button" className="modal-close" onClick={onClose} disabled={closeDisabled} aria-label="Close dialog"><X size={18}/></button>
        </header>
        <div className="modal-body">{children}</div>
        {footer && <footer className="modal-footer">{footer}</footer>}
      </div>
    </div>,
    document.body
  )
}
