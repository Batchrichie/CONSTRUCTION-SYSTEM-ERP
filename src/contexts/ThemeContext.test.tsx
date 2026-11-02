import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it } from 'vitest'
import { ThemeProvider, useTheme } from './ThemeContext'
import ThemeToggle from '../components/ThemeToggle'

function ThemeProbe() {
  const { theme } = useTheme()
  return <span data-testid="current-theme">{theme}</span>
}

describe('theme preference', () => {
  beforeEach(() => {
    window.localStorage.clear()
    document.documentElement.removeAttribute('data-theme')
  })

  it('defaults to light mode', () => {
    render(<ThemeProvider><ThemeProbe /><ThemeToggle /></ThemeProvider>)
    expect(screen.getByTestId('current-theme')).toHaveTextContent('light')
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
  })

  it('switches to dark mode and persists the choice', () => {
    render(<ThemeProvider><ThemeProbe /><ThemeToggle /></ThemeProvider>)
    fireEvent.click(screen.getByRole('button', { name: 'Use dark mode' }))
    expect(screen.getByTestId('current-theme')).toHaveTextContent('dark')
    expect(document.documentElement).toHaveAttribute('data-theme', 'dark')
    expect(window.localStorage.getItem('construction-erp-theme')).toBe('dark')
  })

  it('restores a saved dark preference', () => {
    window.localStorage.setItem('construction-erp-theme', 'dark')
    render(<ThemeProvider><ThemeProbe /><ThemeToggle /></ThemeProvider>)
    expect(screen.getByTestId('current-theme')).toHaveTextContent('dark')
  })
})
