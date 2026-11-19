import { useEffect, useState, type FormEvent } from 'react'
import { HardHat, LockKeyhole, Mail } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'

type AuthMode = 'signin' | 'signup' | 'forgot' | 'reset'

export default function AuthPage() {
  const { client, configurationMissing, passwordRecovery, clearPasswordRecovery } = useAuth()
  const [mode, setMode] = useState<AuthMode>(passwordRecovery ? 'reset' : 'signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [name, setName] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (passwordRecovery) setMode('reset')
  }, [passwordRecovery])

  function changeMode(nextMode: AuthMode) {
    setMode(nextMode)
    setError('')
    setMessage('')
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!client) return
    setBusy(true)
    setError('')
    setMessage('')

    try {
      if (mode === 'signup') {
        const { data, error: authError } = await client.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { full_name: name.trim() } },
        })
        if (authError) throw authError
        setMessage(
          data.session
            ? 'Account created. Company setup will be the next step.'
            : 'Account created. Check your email to confirm your address, then sign in.',
        )
      } else if (mode === 'signin') {
        const { error: authError } = await client.auth.signInWithPassword({
          email: email.trim(),
          password,
        })
        if (authError) throw authError
      } else if (mode === 'forgot') {
        const { error: authError } = await client.auth.resetPasswordForEmail(email.trim(), {
          redirectTo: window.location.origin,
        })
        if (authError) throw authError
        setMessage('If an account exists for that email, a password reset link will be sent.')
      } else {
        if (password !== confirmPassword) {
          throw new Error('The passwords do not match.')
        }
        const { error: authError } = await client.auth.updateUser({ password })
        if (authError) throw authError
        clearPasswordRecovery()
        setPassword('')
        setConfirmPassword('')
        setMode('signin')
        setMessage('Your password has been updated. Sign in with your new password.')
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Authentication failed.')
    } finally {
      setBusy(false)
    }
  }

  const heading = {
    signin: 'Welcome back',
    signup: 'Create your account',
    forgot: 'Reset your password',
    reset: 'Choose a new password',
  }[mode]

  return (
    <main className="auth-screen">
      <section className="auth-card">
        <div className="auth-brand">
          <span><HardHat size={23} /></span>
          <div><strong>CONSTRUCT</strong><small>PROJECT ERP</small></div>
        </div>
        <p className="eyebrow">SECURE WORKSPACE</p>
        <h1>{heading}</h1>
        <p className="auth-intro">
          {mode === 'forgot'
            ? 'Enter your account email address and we will send you a password reset link.'
            : mode === 'reset'
              ? 'Enter and confirm your new password to regain access to your workspace.'
              : 'Sign in to manage your construction business operations.'}
        </p>
        {configurationMissing ? (
          <div className="form-alert error">
            Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in the local environment.
          </div>
        ) : (
          <form className="auth-form" onSubmit={submit}>
            {mode === 'signup' && (
              <label>Full name<input required value={name} onChange={(event) => setName(event.target.value)} /></label>
            )}
            {mode !== 'reset' && (
              <label>
                Email address
                <span className="input-with-icon">
                  <Mail size={15} />
                  <input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} />
                </span>
              </label>
            )}
            {(mode === 'signin' || mode === 'signup' || mode === 'reset') && (
              <label>
                {mode === 'reset' ? 'New password' : 'Password'}
                <span className="input-with-icon">
                  <LockKeyhole size={15} />
                  <input type="password" minLength={8} required value={password} onChange={(event) => setPassword(event.target.value)} />
                </span>
              </label>
            )}
            {mode === 'reset' && (
              <label>
                Confirm new password
                <span className="input-with-icon">
                  <LockKeyhole size={15} />
                  <input type="password" minLength={8} required value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} />
                </span>
              </label>
            )}
            {error && <div className="form-alert error" role="alert">{error}</div>}
            {message && <div className="form-alert success" role="status">{message}</div>}
            <button className="primary-button auth-submit" disabled={busy}>
              {busy
                ? 'Please wait…'
                : mode === 'signin'
                  ? 'Sign in'
                  : mode === 'signup'
                    ? 'Create account'
                    : mode === 'forgot'
                      ? 'Send reset link'
                      : 'Update password'}
            </button>
          </form>
        )}
        {mode === 'signin' && (
          <p className="auth-switch"><button type="button" onClick={() => changeMode('forgot')}>Forgot password?</button></p>
        )}
        {mode === 'forgot' && (
          <p className="auth-switch"><button type="button" onClick={() => changeMode('signin')}>Back to sign in</button></p>
        )}
        {mode === 'reset' && (
          <p className="auth-switch">Having trouble? Request another <button type="button" onClick={() => changeMode('forgot')}>reset link</button>.</p>
        )}
        {mode === 'signup' && (
          <p className="auth-switch">Already registered? <button type="button" onClick={() => changeMode('signin')}>Sign in</button></p>
        )}
        {mode === 'signin' && (
          <p className="auth-switch">New to the system? <button type="button" onClick={() => changeMode('signup')}>Create an account</button></p>
        )}
      </section>
    </main>
  )
}
