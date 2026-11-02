import { render, screen } from '@testing-library/react'
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { describe, expect, it } from 'vitest'
import App from './App'

describe('ERP application shell', () => {
  it('renders the workspace and foundation notice', () => {
    const queryClient = new QueryClient()
    render(
      <QueryClientProvider client={queryClient}>
        <BrowserRouter><App /></BrowserRouter>
      </QueryClientProvider>,
    )
    expect(screen.getByRole('heading', { name: 'Good morning' })).toBeInTheDocument()
    expect(screen.getByText('Foundation stage')).toBeInTheDocument()
  })
})
