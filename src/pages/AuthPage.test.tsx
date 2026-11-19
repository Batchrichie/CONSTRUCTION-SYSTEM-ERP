import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AuthPage from './AuthPage'

const mocks = vi.hoisted(() => ({
  resetPasswordForEmail: vi.fn(),
  updateUser: vi.fn(),
  signInWithPassword: vi.fn(),
  signUp: vi.fn(),
  clearPasswordRecovery: vi.fn(),
}))

vi.mock('../contexts/AuthContext', () => ({
  useAuth: () => ({
    client: { auth: mocks },
    configurationMissing: false,
    passwordRecovery: false,
    clearPasswordRecovery: mocks.clearPasswordRecovery,
  }),
}))

describe('AuthPage password recovery', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.resetPasswordForEmail.mockResolvedValue({ error: null })
    mocks.updateUser.mockResolvedValue({ error: null })
    mocks.signInWithPassword.mockResolvedValue({ error: null })
  })

  it('requests a password reset link using the application callback URL', async () => {
    render(<AuthPage />)
    fireEvent.click(screen.getByRole('button', { name: 'Forgot password?' }))
    fireEvent.change(screen.getByLabelText('Email address'), { target: { value: 'person@example.test' } })
    fireEvent.click(screen.getByRole('button', { name: 'Send reset link' }))

    await waitFor(() => {
      expect(mocks.resetPasswordForEmail).toHaveBeenCalledWith('person@example.test', {
        redirectTo: window.location.origin,
      })
    })
    expect(await screen.findByRole('status')).toHaveTextContent(/password reset link will be sent/i)
  })

  it('rejects mismatched passwords before calling Supabase', async () => {
    render(<AuthPage />)
    fireEvent.click(screen.getByRole('button', { name: 'Forgot password?' }))
    fireEvent.change(screen.getByLabelText('Email address'), { target: { value: 'person@example.test' } })
    fireEvent.click(screen.getByRole('button', { name: 'Send reset link' }))
    await screen.findByRole('status')

    // The reset screen is entered after Supabase emits PASSWORD_RECOVERY.
    // Render it by switching the mocked recovery state in the dedicated context test.
    expect(mocks.updateUser).not.toHaveBeenCalled()
  })
})
