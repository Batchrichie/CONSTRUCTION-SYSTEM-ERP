import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import Modal from './Modal'

describe('Modal', () => {
  afterEach(() => { document.body.innerHTML = '' })

  it('renders an accessible dialog and closes on Escape', () => {
    const onClose = vi.fn()
    render(<Modal title="Create record" description="Enter details" onClose={onClose}><button>Save</button></Modal>)
    expect(screen.getByRole('dialog', { name: 'Create record' })).toBeInTheDocument()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('does not close from Escape while a save is in progress', () => {
    const onClose = vi.fn()
    render(<Modal title="Saving" onClose={onClose} closeDisabled><button>Save</button></Modal>)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onClose).not.toHaveBeenCalled()
  })

  it('closes when the backdrop is clicked', () => {
    const onClose = vi.fn()
    const { container } = render(<Modal title="Create record" onClose={onClose}><button>Save</button></Modal>)
    fireEvent.mouseDown(container.querySelector('.modal-backdrop')!)
    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
