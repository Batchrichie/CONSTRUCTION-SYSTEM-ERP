import { useMemo,useState,type FormEvent } from 'react'
import { Building2,Plus,Search,Users } from 'lucide-react'
import { useQuery,useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
type Party={id:string;party_code:string;legal_name:string;trading_name:string|null;is_customer:boolean;is_supplier:boolean;email:string|null;phone:string|null;city:string|null;status:'active'|'inactive'}
const blank={party_code:'',legal_name:'',trading_name:'',is_customer:true,is_supplier:false,email:'',phone:'',tax_identifier:'',registration_number:'',city:'',region:'',address_line_1:'',credit_terms_days:'0',payment_terms_days:'0'}
export default function PartiesPage(){
 const {client,company}=useAuth();const qc=useQueryClient()
 const [search,setSearch]=useState('');const [filter,setFilter]=useState<'all'|'customers'|'suppliers'>('all')
 const [show,setShow]=useState(false);const [form,setForm]=useState(blank);const [error,setError]=useState('');const [busy,setBusy]=useState(false)
 const query=useQuery({queryKey:['business-parties',company?.id],enabled:Boolean(client&&company),queryFn:async()=>{
  const {data,error}=await client!.from('business_parties').select('id,party_code,legal_name,trading_name,is_customer,is_supplier,email,phone,city,status').eq('company_id',company!.id).order('legal_name')
  if(error)throw error;return (data??[]) as Party[]
 }})
 const parties=query.data??[]
 const filtered=useMemo(()=>parties.filter(p=>{
  const match=filter==='all'||(filter==='customers'?p.is_customer:p.is_supplier);const q=search.toLowerCase()
  return match&&[p.party_code,p.legal_name,p.trading_name??'',p.email??'',p.phone??''].some(v=>v.toLowerCase().includes(q))
 }),[parties,filter,search])
 async function save(e:FormEvent){e.preventDefault();if(!client||!company)return;setBusy(true);setError('')
  try{const {error}=await client.from('business_parties').insert({
   company_id:company.id,party_code:form.party_code.trim(),legal_name:form.legal_name.trim(),trading_name:form.trading_name.trim()||null,
   is_customer:form.is_customer,is_supplier:form.is_supplier,email:form.email.trim()||null,phone:form.phone.trim()||null,
   tax_identifier:form.tax_identifier.trim()||null,registration_number:form.registration_number.trim()||null,
   city:form.city.trim()||null,region:form.region.trim()||null,address_line_1:form.address_line_1.trim()||null,
   credit_terms_days:Number(form.credit_terms_days),payment_terms_days:Number(form.payment_terms_days)
  });if(error)throw error;await qc.invalidateQueries({queryKey:['business-parties',company.id]});setForm(blank);setShow(false)}
  catch(c){setError(c instanceof Error?c.message:'Could not save business party.')}finally{setBusy(false)}}
 return <div className="page-content">
  <div className="workspace-heading"><div><p className="eyebrow">COMMERCIAL REGISTER</p><h1>Customers & Suppliers</h1><p className="page-subtitle">Maintain customer and supplier details in one company-wide register.</p></div><button className="primary-button" onClick={()=>setShow(v=>!v)}><Plus size={15}/> Add party</button></div>
  <div className="stat-strip"><div><span>Total parties</span><strong>{parties.length}</strong></div><div><span>Customers</span><strong>{parties.filter(p=>p.is_customer).length}</strong></div><div><span>Suppliers</span><strong>{parties.filter(p=>p.is_supplier).length}</strong></div><div><span>Active records</span><strong>{parties.filter(p=>p.status==='active').length}</strong></div></div>
  {show&&<section className="form-panel"><div className="panel-heading"><div><h2>New business party</h2><p>A party can be a customer, supplier, or both.</p></div></div><form className="data-form" onSubmit={save}>
   <label>Party code<input required maxLength={40} value={form.party_code} onChange={e=>setForm({...form,party_code:e.target.value})} placeholder="CUS-0001 / SUP-0001"/></label>
   <label>Legal name<input required minLength={2} maxLength={200} value={form.legal_name} onChange={e=>setForm({...form,legal_name:e.target.value})}/></label>
   <label>Trading name<input value={form.trading_name} onChange={e=>setForm({...form,trading_name:e.target.value})}/></label>
   <label>Email<input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label>
   <label>Phone<input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label>
   <label>Tax identification number<input value={form.tax_identifier} onChange={e=>setForm({...form,tax_identifier:e.target.value})}/></label>
   <label>Registration number<input value={form.registration_number} onChange={e=>setForm({...form,registration_number:e.target.value})}/></label>
   <label>City<input value={form.city} onChange={e=>setForm({...form,city:e.target.value})}/></label>
   <label>Region<input value={form.region} onChange={e=>setForm({...form,region:e.target.value})}/></label>
   <label>Address<input value={form.address_line_1} onChange={e=>setForm({...form,address_line_1:e.target.value})}/></label>
   <label>Credit terms (days)<input type="number" min="0" max="365" value={form.credit_terms_days} onChange={e=>setForm({...form,credit_terms_days:e.target.value})}/></label>
   <label>Payment terms (days)<input type="number" min="0" max="365" value={form.payment_terms_days} onChange={e=>setForm({...form,payment_terms_days:e.target.value})}/></label>
   <div className="checkbox-row"><label><input type="checkbox" checked={form.is_customer} onChange={e=>setForm({...form,is_customer:e.target.checked})}/> Customer</label><label><input type="checkbox" checked={form.is_supplier} onChange={e=>setForm({...form,is_supplier:e.target.checked})}/> Supplier</label></div>
   {error&&<div className="form-alert error form-wide">{error}</div>}<div className="form-actions form-wide"><button type="button" className="outline-button" onClick={()=>setShow(false)}>Cancel</button><button className="primary-button" disabled={busy||(!form.is_customer&&!form.is_supplier)}>{busy?'Saving…':'Save business party'}</button></div>
  </form></section>}
  <section className="data-panel"><div className="list-toolbar"><div className="filter-tabs"><button className={filter==='all'?'selected':''} onClick={()=>setFilter('all')}>All parties</button><button className={filter==='customers'?'selected':''} onClick={()=>setFilter('customers')}>Customers</button><button className={filter==='suppliers'?'selected':''} onClick={()=>setFilter('suppliers')}>Suppliers</button></div><div className="search-box"><Search size={15}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search name, code, email…"/></div></div>
   {query.isLoading?<div className="table-empty">Loading business parties…</div>:query.error?<div className="table-empty error-text">{(query.error as Error).message}</div>:filtered.length===0?<div className="table-empty"><Users size={25}/><strong>No business parties found</strong><span>Create a customer or supplier to start using the register.</span></div>:
   <div className="table-scroll"><table className="data-table"><thead><tr><th>Party</th><th>Code</th><th>Contact</th><th>Type</th><th>Location</th><th>Status</th></tr></thead><tbody>{filtered.map(p=><tr key={p.id}><td><strong>{p.trading_name||p.legal_name}</strong><small>{p.legal_name}</small></td><td>{p.party_code}</td><td>{p.email||'—'}<small>{p.phone||'—'}</small></td><td><div className="tag-list">{p.is_customer&&<span>Customer</span>}{p.is_supplier&&<span>Supplier</span>}</div></td><td>{p.city||'—'}</td><td><span className={p.status==='active'?'status-active':'status-inactive'}>{p.status}</span></td></tr>)}</tbody></table></div>}
  </section><p className="page-footnote"><Building2 size={14}/> Company-scoped records. Access is controlled by assigned roles and database policies.</p>
 </div>
}
