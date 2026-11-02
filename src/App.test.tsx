import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { describe, expect, it } from 'vitest'
import App from './App'

function renderApp(initialEntry = '/') {
  const queryClient = new QueryClient()
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[initialEntry]}><App /></MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('ERP application routes', () => {
  it('renders the overview dashboard at the root route', () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Good morning' })).toBeInTheDocument()
    expect(screen.getAllByText('Development workspace').length).toBeGreaterThan(0)
  })

  it('renders the planned accounting module at its route', () => {
    renderApp('/accounting')
    expect(screen.getByRole('heading', { name: 'Accounting' })).toBeInTheDocument()
    expect(screen.getByText('Planned module')).toBeInTheDocument()
    expect(screen.getByText('Double-entry journals and general ledger')).toBeInTheDocument()
  })

  it('shows a not-found page for an unknown route', () => {
    renderApp('/this-route-does-not-exist')
    expect(screen.getByRole('heading', { name: 'This page is unavailable' })).toBeInTheDocument()
  })
})
