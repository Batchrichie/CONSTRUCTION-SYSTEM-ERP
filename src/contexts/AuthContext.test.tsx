import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { AuthProvider, useAuth } from './AuthContext'

const mocks = vi.hoisted(() => ({
  getSession: vi.fn(),
  onAuthStateChange: vi.fn(),
  signOut: vi.fn(),
  from: vi.fn(),
  membershipMaybeSingle: vi.fn(),
  companySingle: vi.fn(),
}))

vi.mock('../lib/supabase', () => ({
  isSupabaseConfigured: true,
  supabase: {
    auth: {
      getSession: mocks.getSession,
      onAuthStateChange: mocks.onAuthStateChange,
      signOut: mocks.signOut,
    },
    from: mocks.from,
  },
}))

function AuthStateProbe() {
  const { company, companyError, companyLoading, refreshCompany } = useAuth()

  return (
    <div>
      <span>{companyLoading ? 'company-loading' : 'company-idle'}</span>
      <span>{company?.display_name ?? 'no-company'}</span>
      {companyError && <p role="alert">{companyError}</p>}
      <button onClick={() => void refreshCompany().catch(() => undefined)}>Retry</button>
    </div>
  )
}

describe('AuthProvider company workspace loading', () => {
  beforeEach(() => {
    vi.clearAllMocks()

    mocks.getSession.mockResolvedValue({
      data: { session: { user: { id: 'user-1', email: 'owner@example.test' } } },
      error: null,
    })
    mocks.onAuthStateChange.mockReturnValue({
      data: { subscription: { unsubscribe: vi.fn() } },
    })

    const membershipQuery = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      limit: vi.fn().mockReturnThis(),
      maybeSingle: mocks.membershipMaybeSingle,
    }
    const companyQuery = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      single: mocks.companySingle,
    }

    mocks.from.mockImplementation((table: string) =>
      table === 'company_memberships' ? membershipQuery : companyQuery,
    )
  })

  it('does not treat a failed membership lookup as a missing company', async () => {
    mocks.membershipMaybeSingle
      .mockResolvedValueOnce({ data: null, error: new Error('permission denied') })
      .mockResolvedValueOnce({
        data: { company_id: 'company-1', roles: { code: 'owner' } },
        error: null,
      })
    mocks.companySingle.mockResolvedValue({
      data: {
        id: 'company-1',
        legal_name: 'Example Construction Ltd',
        display_name: 'Example Construction',
        base_currency: 'GHS',
      },
      error: null,
    })

    render(
      <AuthProvider>
        <AuthStateProbe />
      </AuthProvider>,
    )

    expect(await screen.findByRole('alert')).toHaveTextContent('permission denied')
    expect(screen.getByText('no-company')).toBeInTheDocument()
    expect(screen.queryByText('company-loading')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Retry' }))

    await waitFor(() => {
      expect(screen.getByText('Example Construction')).toBeInTheDocument()
    })
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('invalidates an outstanding company lookup when the user signs out', async () => {
    let authCallback: ((_event: string, session: null) => void) | undefined
    mocks.onAuthStateChange.mockImplementation((callback) => {
      authCallback = callback
      return { data: { subscription: { unsubscribe: vi.fn() } } }
    })

    let resolveMembership: ((value: unknown) => void) | undefined
    mocks.membershipMaybeSingle.mockImplementation(
      () => new Promise((resolve) => { resolveMembership = resolve }),
    )

    render(
      <AuthProvider>
        <AuthStateProbe />
      </AuthProvider>,
    )

    await waitFor(() => expect(mocks.membershipMaybeSingle).toHaveBeenCalled())
    authCallback?.('SIGNED_OUT', null)
    resolveMembership?.({ data: null, error: null })

    await waitFor(() => {
      expect(screen.getByText('company-idle')).toBeInTheDocument()
      expect(screen.getByText('no-company')).toBeInTheDocument()
    })
  })
})
