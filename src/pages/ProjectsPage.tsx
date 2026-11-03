import { useMemo, useState, type FormEvent } from 'react'
import { Building2, MapPin, Plus, Search, Pencil, FolderKanban } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
import Modal from '../components/Modal'

type ProjectStatus = 'planning' | 'active' | 'on_hold' | 'completed' | 'cancelled'
type ProjectType = 'construction' | 'architectural_design' | 'engineering' | 'real_estate_development' | 'renovation' | 'other'
type Project = {
  id: string
  project_code: string
  name: string
  description: string | null
  project_type: ProjectType
  status: ProjectStatus
  location: string | null
  client_name: string | null
  customer_party_id: string | null
  planned_start_date: string | null
  planned_end_date: string | null
  actual_start_date: string | null
  actual_end_date: string | null
  currency_code: string
}
type Customer = { id: string; legal_name: string; trading_name: string | null }

const emptyForm = {
  project_code: '',
  name: '',
  description: '',
  project_type: 'construction' as ProjectType,
  status: 'planning' as ProjectStatus,
  location: '',
  client_name: '',
  customer_party_id: '',
  planned_start_date: '',
  planned_end_date: '',
  actual_start_date: '',
  actual_end_date: '',
  currency_code: 'GHS',
}
const projectTypes: ProjectType[] = ['construction', 'architectural_design', 'engineering', 'real_estate_development', 'renovation', 'other']
const projectStatuses: ProjectStatus[] = ['planning', 'active', 'on_hold', 'completed', 'cancelled']
const label = (value: string) => value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())

export default function ProjectsPage() {
  const { client, company, roleCode, user } = useAuth()
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | ProjectStatus>('all')
  const [editing, setEditing] = useState<Project | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState(emptyForm)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const canManage = ['owner', 'admin', 'project_manager'].includes(roleCode ?? '')

  const projectsQ = useQuery({
    queryKey: ['projects', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from('projects')
        .select('id,project_code,name,description,project_type,status,location,client_name,customer_party_id,planned_start_date,planned_end_date,actual_start_date,actual_end_date,currency_code')
        .eq('company_id', company!.id)
        .order('updated_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Project[]
    },
  })
  const customersQ = useQuery({
    queryKey: ['project-customers', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from('business_parties')
        .select('id,legal_name,trading_name')
        .eq('company_id', company!.id)
        .eq('is_customer', true)
        .eq('status', 'active')
        .order('legal_name')
      if (error) throw error
      return (data ?? []) as Customer[]
    },
  })
  const projects = projectsQ.data ?? []
  const customers = customersQ.data ?? []
  const filtered = useMemo(() => projects.filter(project => {
    const matchesStatus = statusFilter === 'all' || project.status === statusFilter
    const query = search.trim().toLowerCase()
    const matchesSearch = !query || [
      project.project_code, project.name, project.client_name ?? '',
      project.location ?? '', label(project.project_type),
    ].some(value => value.toLowerCase().includes(query))
    return matchesStatus && matchesSearch
  }), [projects, search, statusFilter])

  function openCreate() {
    setEditing(null)
    setForm({ ...emptyForm, currency_code: company?.base_currency || 'GHS' })
    setError('')
    setShowForm(true)
  }
  function openEdit(project: Project) {
    setEditing(project)
    setForm({
      project_code: project.project_code,
      name: project.name,
      description: project.description ?? '',
      project_type: project.project_type,
      status: project.status,
      location: project.location ?? '',
      client_name: project.client_name ?? '',
      customer_party_id: project.customer_party_id ?? '',
      planned_start_date: project.planned_start_date ?? '',
      planned_end_date: project.planned_end_date ?? '',
      actual_start_date: project.actual_start_date ?? '',
      actual_end_date: project.actual_end_date ?? '',
      currency_code: project.currency_code || company?.base_currency || 'GHS',
    })
    setError('')
    setShowForm(true)
  }

  async function save(event: FormEvent) {
    event.preventDefault()
    if (!client || !company || !user) return
    if (form.planned_start_date && form.planned_end_date && form.planned_end_date < form.planned_start_date) {
      setError('The planned end date cannot be earlier than the planned start date.')
      return
    }
    if (form.actual_start_date && form.actual_end_date && form.actual_end_date < form.actual_start_date) {
      setError('The actual end date cannot be earlier than the actual start date.')
      return
    }
    setBusy(true)
    setError('')
    const payload = {
      name: form.name.trim(),
      description: form.description.trim() || null,
      project_type: form.project_type,
      status: form.status,
      location: form.location.trim() || null,
      client_name: form.client_name.trim() || null,
      customer_party_id: form.customer_party_id || null,
      planned_start_date: form.planned_start_date || null,
      planned_end_date: form.planned_end_date || null,
      actual_start_date: form.actual_start_date || null,
      actual_end_date: form.actual_end_date || null,
      currency_code: form.currency_code.trim().toUpperCase(),
    }
    try {
      if (editing) {
        const { data, error } = await client
          .from('projects')
          .update(payload)
          .eq('id', editing.id)
          .eq('company_id', company.id)
          .select('id')
          .maybeSingle()
        if (error) throw error
        if (!data) {
          throw new Error('Project was not updated. It may have been removed or you may no longer have permission to edit it. Refresh the register and try again.')
        }
      } else {
        const { error } = await client
          .from('projects')
          .insert({ ...payload, company_id: company.id, created_by: user.id })
        if (error) throw error
      }
      await qc.invalidateQueries({ queryKey: ['projects', company.id] })
      setShowForm(false)
      setEditing(null)
      setForm(emptyForm)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save project.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page-content">
      {showForm && (
        <Modal
          title={editing ? 'Edit project' : 'Create project'}
          description={editing ? 'Update the project register details and lifecycle status.' : 'Register a construction, design or development project.'}
          eyebrow="PROJECT MANAGEMENT"
          size="large"
          onClose={() => setShowForm(false)}
          closeDisabled={busy}
        >
          <form className="data-form" onSubmit={save}>
            <label>Project code<input value={editing ? form.project_code : 'Generated automatically on save'} readOnly /></label>
            <label>Project name<input required minLength={2} maxLength={200} value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} placeholder="Office complex construction" /></label>
            <label>Project type<select value={form.project_type} onChange={event => setForm({ ...form, project_type: event.target.value as ProjectType })}>{projectTypes.map(type => <option key={type} value={type}>{label(type)}</option>)}</select></label>
            <label>Lifecycle status<select value={form.status} onChange={event => setForm({ ...form, status: event.target.value as ProjectStatus })}>{projectStatuses.map(status => <option key={status} value={status}>{label(status)}</option>)}</select></label>
            <label>Customer<select value={form.customer_party_id} onChange={event => setForm({ ...form, customer_party_id: event.target.value, client_name: customers.find(customer => customer.id === event.target.value)?.trading_name || customers.find(customer => customer.id === event.target.value)?.legal_name || '' })}><option value="">Not linked to a customer</option>{customers.map(customer => <option key={customer.id} value={customer.id}>{customer.trading_name || customer.legal_name}</option>)}</select></label>
            <label>Client name (if not registered)<input value={form.client_name} onChange={event => setForm({ ...form, client_name: event.target.value })} /></label>
            <label>Location / site<input value={form.location} onChange={event => setForm({ ...form, location: event.target.value })} placeholder="Project site location" /></label>
            <label>Reporting currency<input required minLength={3} maxLength={3} value={form.currency_code} onChange={event => setForm({ ...form, currency_code: event.target.value.toUpperCase() })} /></label>
            <label>Planned start<input type="date" value={form.planned_start_date} onChange={event => setForm({ ...form, planned_start_date: event.target.value })} /></label>
            <label>Planned completion<input type="date" min={form.planned_start_date || undefined} value={form.planned_end_date} onChange={event => setForm({ ...form, planned_end_date: event.target.value })} /></label>
            <label>Actual start<input type="date" value={form.actual_start_date} onChange={event => setForm({ ...form, actual_start_date: event.target.value })} /></label>
            <label>Actual completion<input type="date" min={form.actual_start_date || undefined} value={form.actual_end_date} onChange={event => setForm({ ...form, actual_end_date: event.target.value })} /></label>
            <label className="form-wide">Project description<textarea rows={3} value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} /></label>
            {error && <div className="form-alert error form-wide">{error}</div>}
            {customersQ.error && <div className="form-alert error form-wide">{(customersQ.error as Error).message}</div>}
            <div className="form-actions form-wide">
              <button type="button" className="outline-button" onClick={() => setShowForm(false)} disabled={busy}>Cancel</button>
              <button className="primary-button" disabled={busy}>{busy ? 'Saving…' : editing ? 'Save project changes' : 'Create project'}</button>
            </div>
          </form>
        </Modal>
      )}

      <div className="workspace-heading">
        <div>
          <p className="eyebrow">PROJECT MANAGEMENT</p>
          <h1>Projects</h1>
          <p className="page-subtitle">Register and track construction, architectural design and development projects.</p>
        </div>
        {canManage && <button className="primary-button" onClick={openCreate}><Plus size={15} /> New project</button>}
      </div>

      <div className="stat-strip">
        <div><span>Total projects</span><strong>{projects.length}</strong></div>
        <div><span>Active</span><strong>{projects.filter(project => project.status === 'active').length}</strong></div>
        <div><span>Planning</span><strong>{projects.filter(project => project.status === 'planning').length}</strong></div>
        <div><span>Completed</span><strong>{projects.filter(project => project.status === 'completed').length}</strong></div>
      </div>

      <section className="data-panel">
        <div className="list-toolbar">
          <div className="filter-tabs">
            <button className={statusFilter === 'all' ? 'selected' : ''} onClick={() => setStatusFilter('all')}>All projects</button>
            {(['planning', 'active', 'on_hold', 'completed'] as ProjectStatus[]).map(status => (
              <button key={status} className={statusFilter === status ? 'selected' : ''} onClick={() => setStatusFilter(status)}>{label(status)}</button>
            ))}
          </div>
          <div className="search-box"><Search size={15} /><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Search projects…" /></div>
        </div>
        {projectsQ.isLoading ? <div className="table-empty">Loading projects…</div>
          : projectsQ.error ? <div className="table-empty error-text">{(projectsQ.error as Error).message}</div>
            : filtered.length === 0 ? (
              <div className="table-empty"><FolderKanban size={25} /><strong>No projects found</strong><span>{projects.length === 0 ? 'Create your first project to start tracking budgets and costs.' : 'Try changing the search or status filter.'}</span></div>
            ) : (
              <div className="table-scroll">
                <table className="data-table">
                  <thead><tr><th>Project</th><th>Customer / client</th><th>Type</th><th>Timeline</th><th>Status</th>{canManage && <th />}</tr></thead>
                  <tbody>{filtered.map(project => (
                    <tr key={project.id}>
                      <td><strong>{project.project_code}</strong><small>{project.name}</small>{project.location && <small><MapPin size={11} /> {project.location}</small>}</td>
                      <td>{project.client_name || customers.find(customer => customer.id === project.customer_party_id)?.trading_name || customers.find(customer => customer.id === project.customer_party_id)?.legal_name || '—'}</td>
                      <td>{label(project.project_type)}</td>
                      <td>{project.planned_start_date || '—'} <span aria-hidden="true">→</span> {project.planned_end_date || '—'}</td>
                      <td><span className={project.status === 'active' || project.status === 'completed' ? 'status-active' : 'status-inactive'}>{label(project.status)}</span></td>
                      {canManage && <td><button className="text-button" onClick={() => openEdit(project)}><Pencil size={13} /> Edit</button></td>}
                    </tr>
                  ))}</tbody>
                </table>
              </div>
            )}
      </section>
      <p className="page-footnote"><Building2 size={14} /> Company-scoped project records. Database permissions remain the final access control.</p>
    </div>
  )
}
