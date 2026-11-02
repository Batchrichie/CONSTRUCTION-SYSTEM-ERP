import { useState, type FormEvent } from 'react'
import { Building2 } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
export default function CompanySetupPage(){
 const {client,user,refreshCompany,signOut}=useAuth()
 const [legal,setLegal]=useState('');const [display,setDisplay]=useState('');const [error,setError]=useState('');const [busy,setBusy]=useState(false)
 async function submit(e:FormEvent){e.preventDefault();if(!client)return;setBusy(true);setError('')
  try{const {error}=await client.rpc('create_company_for_current_user',{p_legal_name:legal.trim(),p_display_name:display.trim()||legal.trim()});if(error)throw error;await refreshCompany()}
  catch(c){setError(c instanceof Error?c.message:'Company setup failed.')}finally{setBusy(false)}}
 return <main className="auth-screen"><section className="auth-card"><div className="auth-brand"><span><Building2 size={22}/></span><div><strong>COMPANY SETUP</strong><small>WORKSPACE CONFIGURATION</small></div></div>
 <p className="eyebrow">GET STARTED</p><h1>Set up your company</h1><p className="auth-intro">This company will own your projects, commercial records and accounting data.</p>
 <form className="auth-form" onSubmit={submit}><label>Registered legal name<input required minLength={2} maxLength={200} value={legal} onChange={e=>setLegal(e.target.value)}/></label><label>Trading / display name<input value={display} onChange={e=>setDisplay(e.target.value)}/></label>{error&&<div className="form-alert error">{error}</div>}<button className="primary-button auth-submit" disabled={busy}>{busy?'Creating…':'Create company workspace'}</button></form>
 <p className="setup-user">Signed in as {user?.email} <button onClick={()=>void signOut()}>Sign out</button></p></section></main>
}
