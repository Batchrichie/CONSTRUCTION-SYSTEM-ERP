import { useMemo, useState, type FormEvent } from 'react'
import { MapPin, Pencil, Plus, Search, Tags, ToggleLeft, ToggleRight } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
import Modal from '../components/Modal'

type Tab = 'codes' | 'centres'
type CostCategory = 'materials' | 'labour' | 'subcontractors' | 'equipment' | 'professional_fees' | 'transport' | 'permits_and_fees' | 'site_overheads' | 'other'
type CentreType = 'overhead' | 'department' | 'site' | 'shared'
type CostCode = { id: string; code: string; name: string; category: CostCategory; parent_cost_code_id: string | null; is_active: boolean }
type CostCentre = { id: string; code: string; name: string; centre_type: CentreType; branch_id: string | null; is_active: boolean }
type Branch = { id: string; code: string; name: string }

const categories: CostCategory[] = ['materials', 'labour', 'subcontractors', 'equipment', 'professional_fees', 'transport', 'permits_and_fees', 'site_overheads', 'other']
const centreTypes: CentreType[] = ['overhead', 'department', 'site', 'shared']
const label = (value: string) => value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
const blankCode = { code: '', name: '', category: 'materials' as CostCategory, parent_cost_code_id: '' }
const blankCentre = { code: '', name: '', centre_type: 'overhead' as CentreType, branch_id: '' }

export default function ProjectCostSetupPage() {
  const { client, company, roleCode } = useAuth()
  const qc = useQueryClient()
  const [tab, setTab] = useState<Tab>('codes')
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [codeForm, setCodeForm] = useState(blankCode)
  const [centreForm, setCentreForm] = useState(blankCentre)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const canManage = ['owner', 'admin', 'project_manager', 'accountant'].includes(roleCode ?? '')

  const codesQ = useQuery({
    queryKey: ['project-cost-codes', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from('cost_codes')
        .select('id,code,name,category,parent_cost_code_id,is_active')
        .eq('company_id', company!.id)
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCode[]
    },
  })
  const centresQ = useQuery({
    queryKey: ['project-cost-centres', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from('cost_centres')
        .select('id,code,name,centre_type,branch_id,is_active')
        .eq('company_id', company!.id)
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCentre[]
    },
  })
  const branchesQ = useQuery({
    queryKey: ['project-cost-branches', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from('branches')
        .select('id,code,name')
        .eq('company_id', company!.id)
        .eq('is_active', true)
        .order('name')
      if (error) throw error
      return (data ?? []) as Branch[]
    },
  })

  const codes = codesQ.data ?? []
  const centres = centresQ.data ?? []
  const branches = branchesQ.data ?? []
  const filteredCodes = useMemo(() => codes.filter(item => [item.code, item.name, label(item.category)].some(value => value.toLowerCase().includes(search.trim().toLowerCase()))), [codes, search])
  const filteredCentres = useMemo(() => centres.filter(item => [item.code, item.name, label(item.centre_type), branches.find(branch => branch.id === item.branch_id)?.name ?? ''].some(value => value.toLowerCase().includes(search.trim().toLowerCase()))), [centres, branches, search])

  function openCreate() {
    setEditingId(null)
    setCodeForm(blankCode)
    setCentreForm(blankCentre)
    setError('')
    setShowForm(true)
  }
  function openEditCode(item: CostCode) {
    setEditingId(item.id)
    setCodeForm({ code: item.code, name: item.name, category: item.category, parent_cost_code_id: item.parent_cost_code_id ?? '' })
    setError('')
    setShowForm(true)
  }
  function openEditCentre(item: CostCentre) {
    setEditingId(item.id)
    setCentreForm({ code: item.code, name: item.name, centre_type: item.centre_type, branch_id: item.branch_id ?? '' })
    setError('')
    setShowForm(true)
  }

  async function save(event: FormEvent) {
    event.preventDefault()
    if (!client || !company) return
    setBusy(true)
    setError('')
    try {
      if (tab === 'codes') {
        const payload = {
          code: codeForm.code.trim().toUpperCase(),
          name: codeForm.name.trim(),
          category: codeForm.category,
          parent_cost_code_id: codeForm.parent_cost_code_id || null,
        }
        if (!payload.code || !payload.name) throw new Error('Enter both a cost code and its name.')
        if (editingId) {
          const { data, error } = await client.from('cost_codes').update(payload).eq('company_id', company.id).eq('id', editingId).select('id').maybeSingle()
          if (error) throw error
          if (!data) throw new Error('The cost code was not updated. Refresh the list and try again.')
        } else {
          const { error } = await client.from('cost_codes').insert({ ...payload, company_id: company.id })
          if (error) throw error
        }
        await qc.invalidateQueries({ queryKey: ['project-cost-codes', company.id] })
      } else {
        const payload = {
          code: centreForm.code.trim().toUpperCase(),
          name: centreForm.name.trim(),
          centre_type: centreForm.centre_type,
          branch_id: centreForm.branch_id || null,
        }
        if (!payload.code || !payload.name) throw new Error('Enter both a cost centre code and its name.')
        if (editingId) {
          const { data, error } = await client.from('cost_centres').update(payload).eq('company_id', company.id).eq('id', editingId).select('id').maybeSingle()
          if (error) throw error
          if (!data) throw new Error('The cost centre was not updated. Refresh the list and try again.')
        } else {
          const { error } = await client.from('cost_centres').insert({ ...payload, company_id: company.id })
          if (error) throw error
        }
        await qc.invalidateQueries({ queryKey: ['project-cost-centres', company.id] })
      }
      setShowForm(false)
      setEditingId(null)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save this record.')
    } finally {
      setBusy(false)
    }
  }

  async function toggleActive(kind: Tab, id: string, active: boolean) {
    if (!client || !company) return
    setError('')
    const table = kind === 'codes' ? 'cost_codes' : 'cost_centres'
    const { data, error } = await client.from(table).update({ is_active: !active }).eq('company_id', company.id).eq('id', id).select('id').maybeSingle()
    if (error) setError(error.message)
    else if (!data) setError('No record was changed. Refresh the list and try again.')
    else await qc.invalidateQueries({ queryKey: [kind === 'codes' ? 'project-cost-codes' : 'project-cost-centres', company.id] })
  }

  const loading = tab === 'codes' ? codesQ.isLoading : centresQ.isLoading
  const queryError = tab === 'codes' ? codesQ.error : centresQ.error
  const activeCount = tab === 'codes' ? codes.filter(item => item.is_active).length : centres.filter(item => item.is_active).length

  return (
    <div className="page-content">
      {showForm && (
        <Modal
          title={editingId ? (tab === 'codes' ? 'Edit cost code' : 'Edit cost centre') : (tab === 'codes' ? 'New cost code' : 'New cost centre')}
          description={tab === 'codes' ? 'Define a consistent cost classification for estimates, budgets and actual project costs.' : 'Create an overhead, department, site or shared cost centre.'}
          eyebrow="PROJECT COST CONTROLS"
          size="medium"
          onClose={() => setShowForm(false)}
          closeDisabled={busy}
        >
          <form className="data-form" onSubmit={save}>
            <label>Code<input required maxLength={40} value={tab === 'codes' ? codeForm.code : centreForm.code} onChange={event => tab === 'codes' ? setCodeForm({ ...codeForm, code: event.target.value }) : setCentreForm({ ...centreForm, code: event.target.value })} placeholder={tab === 'codes' ? 'MAT-001' : 'OH-001'} /></label>
            <label>Name<input required maxLength={160} value={tab === 'codes' ? codeForm.name : centreForm.name} onChange={event => tab === 'codes' ? setCodeForm({ ...codeForm, name: event.target.value }) : setCentreForm({ ...centreForm, name: event.target.value })} placeholder={tab === 'codes' ? 'Construction materials' : 'Head office overhead'} /></label>
            {tab === 'codes' ? (
              <>
                <label>Cost category<select value={codeForm.category} onChange={event => setCodeForm({ ...codeForm, category: event.target.value as CostCategory })}>{categories.map(value => <option key={value} value={value}>{label(value)}</option>)}</select></label>
                <label>Parent cost code<select value={codeForm.parent_cost_code_id} onChange={event => setCodeForm({ ...codeForm, parent_cost_code_id: event.target.value })}><option value="">No parent (top level)</option>{codes.filter(item => item.is_active && item.id !== editingId && item.parent_cost_code_id === null).map(item => <option key={item.id} value={item.id}>{item.code} — {item.name}</option>)}</select><small className="helper-text">Parent codes are limited to top-level entries to keep the hierarchy cycle-free.</small></label>
              </>
            ) : (
              <>
                <label>Cost centre type<select value={centreForm.centre_type} onChange={event => setCentreForm({ ...centreForm, centre_type: event.target.value as CentreType })}>{centreTypes.map(value => <option key={value} value={value}>{label(value)}</option>)}</select></label>
                <label>Branch (optional)<select value={centreForm.branch_id} onChange={event => setCentreForm({ ...centreForm, branch_id: event.target.value })}><option value="">Company-wide</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.code} — {branch.name}</option>)}</select></label>
              </>
            )}
            {error && <div className="form-alert error form-wide">{error}</div>}
            <div className="form-actions form-wide">
              <button type="button" className="outline-button" onClick={() => setShowForm(false)} disabled={busy}>Cancel</button>
              <button className="primary-button" disabled={busy}>{busy ? 'Saving…' : editingId ? 'Save changes' : 'Create record'}</button>
            </div>
          </form>
        </Modal>
      )}

      <div className="workspace-heading">
        <div><p className="eyebrow">PROJECT COST MANAGEMENT</p><h1>Cost Codes &amp; Centres</h1><p className="page-subtitle">Standardise how project costs and company overheads are classified.</p></div>
        {canManage && <button className="primary-button" onClick={openCreate}><Plus size={15} /> New {tab === 'codes' ? 'cost code' : 'cost centre'}</button>}
      </div>

      <div className="stat-strip">
        <div><span>{tab === 'codes' ? 'Total cost codes' : 'Total cost centres'}</span><strong>{tab === 'codes' ? codes.length : centres.length}</strong></div>
        <div><span>Active</span><strong>{activeCount}</strong></div>
        <div><span>Inactive</span><strong>{(tab === 'codes' ? codes.length : centres.length) - activeCount}</strong></div>
        <div><span>Company</span><strong>{company?.base_currency ?? 'GHS'}</strong></div>
      </div>

      <section className="data-panel">
        <div className="list-toolbar">
          <div className="filter-tabs">
            <button className={tab === 'codes' ? 'selected' : ''} onClick={() => { setTab('codes'); setSearch(''); setError('') }}><Tags size={13} /> Cost codes</button>
            <button className={tab === 'centres' ? 'selected' : ''} onClick={() => { setTab('centres'); setSearch(''); setError('') }}><MapPin size={13} /> Cost centres</button>
          </div>
          <div className="search-box"><Search size={15} /><input value={search} onChange={event => setSearch(event.target.value)} placeholder={tab === 'codes' ? 'Search cost codes…' : 'Search cost centres…'} /></div>
        </div>
        {error && !showForm && <div className="form-alert error">{error}</div>}
        {loading ? <div className="table-empty">Loading {tab === 'codes' ? 'cost codes' : 'cost centres'}…</div>
          : queryError ? <div className="table-empty error-text">{(queryError as Error).message}</div>
            : tab === 'codes' ? (
              filteredCodes.length === 0 ? <div className="table-empty"><Tags size={24} /><strong>No cost codes found</strong><span>Create cost codes such as materials, labour, equipment and professional fees.</span></div> :
                <div className="table-scroll"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Category</th><th>Parent</th><th>Status</th>{canManage && <th />}</tr></thead><tbody>
                  {filteredCodes.map(item => <tr key={item.id}><td><strong>{item.code}</strong></td><td>{item.name}</td><td>{label(item.category)}</td><td>{codes.find(parent => parent.id === item.parent_cost_code_id)?.code ?? '—'}</td><td><span className={item.is_active ? 'status-active' : 'status-inactive'}>{item.is_active ? 'Active' : 'Inactive'}</span></td>{canManage && <td><button className="text-button" onClick={() => openEditCode(item)}><Pencil size={12} /> Edit</button><button className="text-button" onClick={() => void toggleActive('codes', item.id, item.is_active)}>{item.is_active ? <ToggleLeft size={13} /> : <ToggleRight size={13} />}{item.is_active ? 'Deactivate' : 'Activate'}</button></td>}</tr>)}
                </tbody></table></div>
            ) : (
              filteredCentres.length === 0 ? <div className="table-empty"><MapPin size={24} /><strong>No cost centres found</strong><span>Create centres for head-office overheads, departments, sites or shared costs.</span></div> :
                <div className="table-scroll"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Type</th><th>Branch</th><th>Status</th>{canManage && <th />}</tr></thead><tbody>
                  {filteredCentres.map(item => <tr key={item.id}><td><strong>{item.code}</strong></td><td>{item.name}</td><td>{label(item.centre_type)}</td><td>{branches.find(branch => branch.id === item.branch_id)?.name ?? 'Company-wide'}</td><td><span className={item.is_active ? 'status-active' : 'status-inactive'}>{item.is_active ? 'Active' : 'Inactive'}</span></td>{canManage && <td><button className="text-button" onClick={() => openEditCentre(item)}><Pencil size={12} /> Edit</button><button className="text-button" onClick={() => void toggleActive('centres', item.id, item.is_active)}>{item.is_active ? <ToggleLeft size={13} /> : <ToggleRight size={13} />}{item.is_active ? 'Deactivate' : 'Activate'}</button></td>}</tr>)}
                </tbody></table></div>
            )}
      </section>
      <p className="page-footnote">Company-scoped setup. Records are deactivated rather than deleted so existing budgets and posted cost allocations retain their references.</p>
    </div>
  )
}
