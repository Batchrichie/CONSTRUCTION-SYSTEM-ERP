import { useState, type FormEvent } from 'react'
import { HardHat, LockKeyhole, Mail } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
export default function AuthPage(){
 const {client,configurationMissing}=useAuth()
 const [mode,setMode]=useState<'signin'|'signup'>('signin')
 const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [name,setName]=useState('')
 const [message,setMessage]=useState('');const [error,setError]=useState('');const [busy,setBusy]=useState(false)
 async function submit(e:FormEvent){e.preventDefault();if(!client)return;setBusy(true);setError('');setMessage('')
  try{if(mode==='signup'){const {data,error}=await client.auth.signUp({email:email.trim(),password,options:{data:{full_name:name.trim()}}});if(error)throw error;setMessage(data.session?'Account created. Company setup will be the next step.':'Account created. Confirm your email, then sign in.')}
  else{const {error}=await client.auth.signInWithPassword({email:email.trim(),password});if(error)throw error}}
  catch(c){setError(c instanceof Error?c.message:'Authentication failed.')}finally{setBusy(false)}}
 return <main className="auth-screen"><section className="auth-card">
  <div className="auth-brand"><span><HardHat size={23}/></span><div><strong>CONSTRUCT</strong><small>PROJECT ERP</small></div></div>
  <p className="eyebrow">SECURE WORKSPACE</p><h1>{mode==='signin'?'Welcome back':'Create your account'}</h1><p className="auth-intro">Sign in to manage your construction business operations.</p>
  {configurationMissing?<div className="form-alert error">Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in the local environment.</div>:
  <form className="auth-form" onSubmit={submit}>
   {mode==='signup'&&<label>Full name<input required value={name} onChange={e=>setName(e.target.value)}/></label>}
   <label>Email address<span className="input-with-icon"><Mail size={15}/><input type="email" required value={email} onChange={e=>setEmail(e.target.value)}/></span></label>
   <label>Password<span className="input-with-icon"><LockKeyhole size={15}/><input type="password" minLength={8} required value={password} onChange={e=>setPassword(e.target.value)}/></span></label>
   {error&&<div className="form-alert error">{error}</div>}{message&&<div className="form-alert success">{message}</div>}
   <button className="primary-button auth-submit" disabled={busy}>{busy?'Please wait…':mode==='signin'?'Sign in':'Create account'}</button>
  </form>}
  <p className="auth-switch">{mode==='signin'?'New to the system?':'Already registered?'} <button onClick={()=>{setMode(mode==='signin'?'signup':'signin');setError('');setMessage('')}}>{mode==='signin'?'Create an account':'Sign in'}</button></p>
 </section></main>
}
