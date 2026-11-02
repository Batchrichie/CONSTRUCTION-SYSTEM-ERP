import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import Modal from './Modal'

describe('Modal', () => {
  afterEach(() => cleanup())

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
    render(<Modal title="Create record" onClose={onClose}><button>Save</button></Modal>)
    const backdrop = screen.getByRole('dialog').parentElement
    expect(backdrop).not.toBeNull()
    fireEvent.mouseDown(backdrop!)
    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
