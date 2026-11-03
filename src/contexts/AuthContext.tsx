import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '../lib/supabase'

type Company = {
  id: string
  legal_name: string
  display_name: string
  base_currency: string
}

type State = {
  client: typeof supabase
  user: User | null
  company: Company | null
  roleCode: string | null
  loading: boolean
  companyLoading: boolean
  companyError: string | null
  configurationMissing: boolean
  refreshCompany: () => Promise<void>
  signOut: () => Promise<void>
}

const Context = createContext<State | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [company, setCompany] = useState<Company | null>(null)
  const [roleCode, setRoleCode] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [companyLoading, setCompanyLoading] = useState(false)
  const [companyError, setCompanyError] = useState<string | null>(null)
  const authEventVersion = useRef(0)
  const companyRequestVersion = useRef(0)
  const activeUserId = useRef<string | null>(null)

  useEffect(() => {
    if (!supabase) {
      setLoading(false)
      return
    }

    let active = true

    // Subscribe before reading the stored session so an auth event cannot be
    // overwritten by a slower initial getSession() response.
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      authEventVersion.current += 1
      const nextUserId = nextSession?.user.id ?? null
      const userChanged = nextUserId !== activeUserId.current
      activeUserId.current = nextUserId
      setSession(nextSession)

      if (userChanged && nextSession) {
        setCompany(null)
        setRoleCode(null)
        setCompanyError(null)
        setCompanyLoading(true)
      }

      if (!nextSession) {
        companyRequestVersion.current += 1
        setCompany(null)
        setRoleCode(null)
        setCompanyError(null)
        setCompanyLoading(false)
      }
    })

    const initialAuthEventVersion = authEventVersion.current

    void supabase.auth
      .getSession()
      .then(({ data, error }) => {
        if (!active || authEventVersion.current !== initialAuthEventVersion) return
        if (error) {
          activeUserId.current = null
          setSession(null)
          return
        }
        activeUserId.current = data.session?.user.id ?? null
        setSession(data.session)
        setCompanyLoading(Boolean(data.session))
      })
      .catch(() => {
        if (active && authEventVersion.current === initialAuthEventVersion) {
          activeUserId.current = null
          setSession(null)
        }
      })
      .finally(() => {
        if (active) setLoading(false)
      })

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [])

  const userId = session?.user?.id ?? null

  const refreshCompany = useCallback(async () => {
    const requestVersion = ++companyRequestVersion.current

    if (!supabase || !userId) {
      setCompany(null)
      setRoleCode(null)
      setCompanyError(null)
      setCompanyLoading(false)
      return
    }

    setCompanyLoading(true)
    setCompanyError(null)

    try {
      const { data: membership, error: membershipError } = await supabase
        .from('company_memberships')
        .select('company_id, roles(code)')
        .eq('user_id', userId)
        .eq('status', 'active')
        .limit(1)
        .maybeSingle()

      if (membershipError) throw membershipError

      if (!membership) {
        if (requestVersion === companyRequestVersion.current) {
          setCompany(null)
          setRoleCode(null)
        }
        return
      }

      const { data: companyData, error: companyErrorResult } = await supabase
        .from('companies')
        .select('id,legal_name,display_name,base_currency')
        .eq('id', membership.company_id)
        .single()

      if (companyErrorResult) throw companyErrorResult

      if (requestVersion === companyRequestVersion.current) {
        setCompany(companyData as Company)
        setRoleCode((membership.roles as unknown as { code?: string } | null)?.code ?? null)
      }
    } catch (error) {
      if (requestVersion === companyRequestVersion.current) {
        setCompany(null)
        setRoleCode(null)
        setCompanyError(
          error instanceof Error ? error.message : 'Unable to load the company workspace.',
        )
      }
      throw error
    } finally {
      if (requestVersion === companyRequestVersion.current) {
        setCompanyLoading(false)
      }
    }
  }, [userId])

  useEffect(() => {
    if (loading) return

    if (!userId) {
      companyRequestVersion.current += 1
      setCompany(null)
      setRoleCode(null)
      setCompanyError(null)
      setCompanyLoading(false)
      return
    }

    void refreshCompany().catch(() => undefined)
  }, [loading, userId, refreshCompany])

  const value = useMemo<State>(
    () => ({
      client: supabase,
      user: session?.user ?? null,
      company,
      roleCode,
      loading,
      companyLoading,
      companyError,
      configurationMissing: !isSupabaseConfigured,
      refreshCompany,
      signOut: async () => {
        if (supabase) await supabase.auth.signOut()
      },
    }),
    [session, company, roleCode, loading, companyLoading, companyError, refreshCompany],
  )

  return <Context.Provider value={value}>{children}</Context.Provider>
}

// This context module intentionally exports its hook alongside the provider.
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const value = useContext(Context)
  if (!value) throw new Error('useAuth must be used within AuthProvider')
  return value
}
