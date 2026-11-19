import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AuthPage from './AuthPage'

const mocks = vi.hoisted(() => ({
  resetPasswordForEmail: vi.fn(),
  updateUser: vi.fn(),
  signInWithPassword: vi.fn(),
  signUp: vi.fn(),
  clearPasswordRecovery: vi.fn(),
  passwordRecovery: false,
}))

vi.mock('../contexts/AuthContext', () => ({
  useAuth: () => ({
    client: { auth: mocks },
    configurationMissing: false,
    passwordRecovery: mocks.passwordRecovery,
    clearPasswordRecovery: mocks.clearPasswordRecovery,
  }),
}))

describe('AuthPage password recovery', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.passwordRecovery = false
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

  it('requires matching passwords before updating the account', async () => {
    mocks.passwordRecovery = true
    render(<AuthPage />)

    fireEvent.change(screen.getByLabelText('New password'), { target: { value: 'NewPassword123' } })
    fireEvent.change(screen.getByLabelText('Confirm new password'), { target: { value: 'DifferentPassword123' } })
    fireEvent.click(screen.getByRole('button', { name: 'Update password' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('The passwords do not match.')
    expect(mocks.updateUser).not.toHaveBeenCalled()

    fireEvent.change(screen.getByLabelText('Confirm new password'), { target: { value: 'NewPassword123' } })
    fireEvent.click(screen.getByRole('button', { name: 'Update password' }))

    await waitFor(() => {
      expect(mocks.updateUser).toHaveBeenCalledWith({ password: 'NewPassword123' })
    })
    expect(mocks.clearPasswordRecovery).toHaveBeenCalled()
    expect(await screen.findByRole('status')).toHaveTextContent(/password has been updated/i)
  })
})
