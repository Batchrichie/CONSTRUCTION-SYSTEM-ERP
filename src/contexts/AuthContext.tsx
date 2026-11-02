import { createContext,useCallback,useContext,useEffect,useMemo,useState,type ReactNode } from 'react'
import type { Session,User } from '@supabase/supabase-js'
import { isSupabaseConfigured,supabase } from '../lib/supabase'
type Company={id:string;legal_name:string;display_name:string;base_currency:string}
type State={client:typeof supabase;user:User|null;company:Company|null;roleCode:string|null;loading:boolean;configurationMissing:boolean;refreshCompany:()=>Promise<void>;signOut:()=>Promise<void>}
const Context=createContext<State|null>(null)
export function AuthProvider({children}:{children:ReactNode}){
 const [session,setSession]=useState<Session|null>(null);const [company,setCompany]=useState<Company|null>(null);const [roleCode,setRoleCode]=useState<string|null>(null);const [loading,setLoading]=useState(true)
 useEffect(()=>{if(!supabase){setLoading(false);return}let active=true
  supabase.auth.getSession().then(({data})=>{if(active){setSession(data.session);setLoading(false)}})
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{setSession(next);if(!next){setCompany(null);setRoleCode(null)}})
  return()=>{active=false;subscription.unsubscribe()}
 },[])
 const refreshCompany=useCallback(async()=>{
  if(!supabase||!session?.user){setCompany(null);setRoleCode(null);return}
  const {data:m,error:me}=await supabase.from('company_memberships').select('company_id, roles(code)').eq('user_id',session.user.id).eq('status','active').limit(1).maybeSingle()
  if(me)throw me;if(!m){setCompany(null);setRoleCode(null);return}
  const {data:c,error:ce}=await supabase.from('companies').select('id,legal_name,display_name,base_currency').eq('id',m.company_id).single()
  if(ce)throw ce;setCompany(c as Company);setRoleCode((m.roles as unknown as {code?:string}|null)?.code??null)
 },[session?.user?.id])
 useEffect(()=>{if(!loading&&session?.user)refreshCompany().catch(()=>{setCompany(null);setRoleCode(null)})},[loading,session?.user?.id,refreshCompany])
 const value=useMemo<State>(()=>({client:supabase,user:session?.user??null,company,roleCode,loading,configurationMissing:!isSupabaseConfigured,refreshCompany,signOut:async()=>{if(supabase)await supabase.auth.signOut()}}),[session,company,roleCode,loading,refreshCompany])
 return <Context.Provider value={value}>{children}</Context.Provider>
}
export function useAuth(){const v=useContext(Context);if(!v)throw new Error('useAuth must be used within AuthProvider');return v}
