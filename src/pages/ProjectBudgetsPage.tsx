import { useMemo, useState, type FormEvent } from 'react'
import { CheckCircle2, ClipboardList, Copy, Plus, Search, Send, XCircle } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
import Modal from '../components/Modal'
import { isPositiveAmount, sumUnits, unitsToNumber } from '../lib/decimalAmount'

type BudgetStatus = 'draft' | 'submitted' | 'approved' | 'rejected'
type Project = { id: string; project_code: string; name: string; status: string; currency_code: string }
type CostCode = { id: string; code: string; name: string; category: string; is_active: boolean }
type Budget = {
  id: string
  project_id: string
  revision_number: number
  status: BudgetStatus
  currency_code: string
  notes: string | null
  submitted_at: string | null
  decided_at: string | null
  rejection_reason: string | null
  created_at: string
}
type BudgetLine = { id?: string; cost_code_id: string; budget_amount: number | string; approved_amount?: number | string; notes: string | null }
type History = { id: string; from_status: string | null; to_status: string; note: string | null; changed_at: string }

const label = (value: string) => value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
const money = (amount: number, currency: string) => new Intl.NumberFormat('en-GH', {
  style: 'currency', currency: currency || 'GHS', minimumFractionDigits: 2, maximumFractionDigits: 2,
}).format(Number(amount || 0))
const blankLine = (): BudgetLine => ({ cost_code_id: '', budget_amount: '', notes: '' })
const isPositiveBudgetAmount = (value: string | number) => {
  const amount = String(value).trim()
  return /^(?:0|[1-9]\d*)(?:\.\d{1,4})?$/.test(amount) && Number.isFinite(Number(amount)) && Number(amount) > 0
}

export default function ProjectBudgetsPage() {
  const { client, company, roleCode } = useAuth()
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | BudgetStatus>('all')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [showEditor, setShowEditor] = useState(false)
  const [showReject, setShowReject] = useState(false)
  const [rejectNote, setRejectNote] = useState('')
  const [form, setForm] = useState({ project_id: '', notes: '', lines: [blankLine()] as BudgetLine[] })
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const canManage = ['owner', 'admin', 'project_manager', 'accountant'].includes(roleCode ?? '')
  const canApprove = ['owner', 'admin'].includes(roleCode ?? '')

  const projectsQ = useQuery({
    queryKey: ['budget-projects', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!.from('projects')
        .select('id,project_code,name,status,currency_code')
        .eq('company_id', company!.id)
        .neq('status', 'cancelled')
        .order('project_code')
      if (error) throw error
      return (data ?? []) as Project[]
    },
  })
  const codesQ = useQuery({
    queryKey: ['budget-cost-codes', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!.from('cost_codes')
        .select('id,code,name,category,is_active')
        .eq('company_id', company!.id)
        .eq('is_active', true)
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCode[]
    },
  })
  const budgetsQ = useQuery({
    queryKey: ['project-budget-versions', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!.from('project_budget_versions')
        .select('id,project_id,revision_number,status,currency_code,notes,submitted_at,decided_at,rejection_reason,created_at')
        .eq('company_id', company!.id)
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Budget[]
    },
  })
  const selected = budgetsQ.data?.find(item => item.id === selectedId) ?? null
  const linesQ = useQuery({
    queryKey: ['project-budget-lines', company?.id, selectedId],
    enabled: Boolean(client && company && selectedId),
    queryFn: async () => {
      const { data, error } = await client!.from('project_budgets')
        .select('id,cost_code_id,budget_amount,approved_amount,notes')
        .eq('company_id', company!.id)
        .eq('budget_version_id', selectedId!)
        .order('created_at')
      if (error) throw error
      return (data ?? []) as BudgetLine[]
    },
  })
  const historyQ = useQuery({
    queryKey: ['project-budget-history', company?.id, selectedId],
    enabled: Boolean(client && company && selectedId),
    queryFn: async () => {
      const { data, error } = await client!.from('project_budget_history')
        .select('id,from_status,to_status,note,changed_at')
        .eq('company_id', company!.id)
        .eq('budget_version_id', selectedId!)
        .order('changed_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as History[]
    },
  })

  const projects = projectsQ.data ?? []
  const codes = codesQ.data ?? []
  const budgets = budgetsQ.data ?? []
  const filtered = useMemo(() => budgets.filter(item => {
    const project = projects.find(candidate => candidate.id === item.project_id)
    const matchesStatus = statusFilter === 'all' || item.status === statusFilter
    const query = search.trim().toLowerCase()
    const matchesSearch = !query || [
      project?.project_code ?? '', project?.name ?? '', 'rev ' + item.revision_number,
      item.status, item.notes ?? '',
    ].some(value => value.toLowerCase().includes(query))
    return matchesStatus && matchesSearch
  }), [budgets, projects, search, statusFilter])

  const totals = useMemo(() => ({
    draft: budgets.filter(item => item.status === 'draft').length,
    submitted: budgets.filter(item => item.status === 'submitted').length,
    approved: budgets.filter(item => item.status === 'approved').length,
  }), [budgets])

  function openCreate() {
    setEditingId(null)
    setForm({
      project_id: projects[0]?.id ?? '',
      notes: '',
      lines: [{ ...blankLine(), cost_code_id: codes[0]?.id ?? '' }],
    })
    setError('')
    setSelectedId(null)
    setShowEditor(true)
  }

  async function openEdit(item: Budget) {
    if (!client || !company) return
    setBusy(true)
    setError('')
    try {
      const { data, error } = await client.from('project_budgets')
        .select('cost_code_id,budget_amount,notes')
        .eq('company_id', company.id)
        .eq('budget_version_id', item.id)
        .order('created_at')
      if (error) throw error
      setEditingId(item.id)
      setForm({
        project_id: item.project_id,
        notes: item.notes ?? '',
        lines: (data ?? []).map(line => ({
          cost_code_id: line.cost_code_id,
          budget_amount: String(line.budget_amount),
          notes: line.notes ?? '',
        })),
      })
      setSelectedId(null)
      setShowEditor(true)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load this budget.')
    } finally {
      setBusy(false)
    }
  }

  function updateLine(index: number, patch: Partial<BudgetLine>) {
    setForm(current => ({
      ...current,
      lines: current.lines.map((line, lineIndex) => lineIndex === index ? { ...line, ...patch } : line),
    }))
  }

  async function saveDraft(event: FormEvent) {
    event.preventDefault()
    if (!client || !company) return
    if (!form.project_id) { setError('Select a project first.'); return }
    if (form.lines.length === 0 || form.lines.some(line => !line.cost_code_id || !isPositiveBudgetAmount(line.budget_amount))) {
      setError('Every budget line must have a cost code and a positive amount.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const { data, error } = await client.rpc('save_project_budget_draft', {
        p_company_id: company.id,
        p_project_id: form.project_id,
        p_budget_version_id: editingId,
        p_notes: form.notes.trim() || null,
        p_lines: form.lines.map(line => ({
          cost_code_id: line.cost_code_id,
          budget_amount: String(line.budget_amount).trim(),
          notes: line.notes?.trim() || null,
        })),
      })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['project-budget-versions', company.id] })
      await qc.invalidateQueries({ queryKey: ['project-budget-lines', company.id] })
      setShowEditor(false)
      setSelectedId(data as string)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save this budget.')
    } finally {
      setBusy(false)
    }
  }

  async function transition(item: Budget, nextStatus: 'submitted' | 'approved' | 'rejected', note?: string) {
    if (!client || !company) return
    setBusy(true)
    setError('')
    try {
      const { error } = await client.rpc('transition_project_budget', {
        p_company_id: company.id,
        p_budget_version_id: item.id,
        p_new_status: nextStatus,
        p_note: note ?? null,
      })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['project-budget-versions', company.id] })
      await qc.invalidateQueries({ queryKey: ['project-budget-lines', company.id, item.id] })
      await qc.invalidateQueries({ queryKey: ['project-budget-history', company.id, item.id] })
      setShowReject(false)
      setRejectNote('')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The budget status could not be changed.')
    } finally {
      setBusy(false)
    }
  }

  async function createRevision(item: Budget) {
    if (!client || !company) return
    setBusy(true)
    setError('')
    try {
      const { data, error } = await client.rpc('create_project_budget_revision', {
        p_company_id: company.id,
        p_project_id: item.project_id,
        p_source_budget_version_id: item.id,
      })
      if (error) throw error
      await qc.invalidateQueries({ queryKey: ['project-budget-versions', company.id] })
      setSelectedId(data as string)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not create a new revision.')
    } finally {
      setBusy(false)
    }
  }

  const selectedLines = linesQ.data ?? []
  const budgetTotal = unitsToNumber(sumUnits(selectedLines.map(line => line.budget_amount)))
  const approvedTotal = unitsToNumber(sumUnits(selectedLines.map(line => line.approved_amount)))

  return (
    <div className="page-content">
      {showEditor && (
        <Modal
          title={editingId ? 'Edit draft budget' : 'Prepare project budget'}
          description="Set the cost-code allowances for this project. Only draft revisions can be changed."
          eyebrow="PROJECT COST MANAGEMENT"
          size="large"
          onClose={() => setShowEditor(false)}
          closeDisabled={busy}
        >
          <form className="data-form" onSubmit={saveDraft}>
            <label className="form-wide">Project
              <select required value={form.project_id} disabled={Boolean(editingId)} onChange={event => setForm({ ...form, project_id: event.target.value })}>
                <option value="">Select project</option>
                {projects.map(project => <option key={project.id} value={project.id}>{project.project_code} · {project.name}</option>)}
              </select>
            </label>
            <label className="form-wide">Budget notes
              <textarea rows={2} maxLength={2000} value={form.notes} onChange={event => setForm({ ...form, notes: event.target.value })} placeholder="Scope assumptions, exclusions or budget basis…" />
            </label>
            <div className="form-wide">
              <div className="list-toolbar"><strong className="section-title">Budget cost lines</strong><button type="button" className="outline-button" onClick={() => setForm(current => ({ ...current, lines: [...current.lines, { ...blankLine(), cost_code_id: codes[0]?.id ?? '' }] }))}><Plus size={13} /> Add line</button></div>
              {form.lines.map((line, index) => (
                <div className="budget-line-editor" key={index}>
                  <label>Cost code
                    <select required value={line.cost_code_id} onChange={event => updateLine(index, { cost_code_id: event.target.value })}>
                      <option value="">Select cost code</option>
                      {codes.map(code => <option key={code.id} value={code.id}>{code.code} · {code.name}</option>)}
                    </select>
                  </label>
                  <label>Budget amount ({projects.find(project => project.id === form.project_id)?.currency_code ?? company?.base_currency ?? 'GHS'})
                    <input required type="number" min="0.0001" step="0.0001" value={line.budget_amount} onChange={event => updateLine(index, { budget_amount: event.target.value })} placeholder="0.00" />
                  </label>
                  <label className="budget-line-note">Line notes
                    <input maxLength={500} value={line.notes ?? ''} onChange={event => updateLine(index, { notes: event.target.value })} placeholder="Optional detail" />
                  </label>
                  <button type="button" className="text-button" disabled={form.lines.length === 1} onClick={() => setForm(current => ({ ...current, lines: current.lines.filter((_, lineIndex) => lineIndex !== index) }))}>Remove</button>
                </div>
              ))}
            </div>
            {codes.length === 0 && <p className="form-wide helper-text">Create and activate cost codes before preparing a project budget.</p>}
            {error && <div className="form-alert error form-wide">{error}</div>}
            <div className="form-actions form-wide">
              <button type="button" className="outline-button" onClick={() => setShowEditor(false)} disabled={busy}>Cancel</button>
              <button className="primary-button" disabled={busy || codes.length === 0 || projects.length === 0}>{busy ? 'Saving…' : 'Save draft budget'}</button>
            </div>
          </form>
        </Modal>
      )}

      {selected && !showEditor && !showReject && (
        <Modal
          title={projects.find(project => project.id === selected.project_id)?.name ?? 'Project budget'}
          description={'Revision ' + selected.revision_number + ' · ' + label(selected.status)}
          eyebrow="PROJECT BUDGET DETAILS"
          size="large"
          onClose={() => setSelectedId(null)}
          closeDisabled={busy}
        >
          <div className="budget-detail">
            <div className="budget-detail-meta"><span>Project code</span><strong>{projects.find(project => project.id === selected.project_id)?.project_code ?? '—'}</strong><span>Currency</span><strong>{selected.currency_code}</strong><span>Created</span><strong>{new Date(selected.created_at).toLocaleDateString('en-GB')}</strong></div>
            {selected.notes && <p className="budget-notes">{selected.notes}</p>}
            {selected.status === 'rejected' && selected.rejection_reason && <div className="form-alert error">Rejection reason: {selected.rejection_reason}</div>}
            {linesQ.isLoading ? <div className="table-empty">Loading budget lines…</div> : linesQ.error ? <div className="form-alert error">{(linesQ.error as Error).message}</div> : (
              <div className="table-scroll"><table className="data-table"><thead><tr><th>Cost code</th><th>Cost category</th><th className="numeric">Budget</th><th className="numeric">Approved</th><th>Notes</th></tr></thead><tbody>
                {selectedLines.map((line, index) => {
                  const code = codes.find(item => item.id === line.cost_code_id)
                  return <tr key={line.id ?? index}><td><strong>{code?.code ?? '—'}</strong><small>{code?.name ?? 'Unknown cost code'}</small></td><td>{code ? label(code.category) : '—'}</td><td className="numeric">{money(Number(line.budget_amount), selected.currency_code)}</td><td className="numeric">{money(Number(line.approved_amount), selected.currency_code)}</td><td>{line.notes || '—'}</td></tr>
                })}
              </tbody><tfoot><tr><th colSpan={2}>Total</th><th className="numeric">{money(budgetTotal, selected.currency_code)}</th><th className="numeric">{money(approvedTotal, selected.currency_code)}</th><th /></tr></tfoot></table></div>
            )}
            {historyQ.data && historyQ.data.length > 0 && <div className="budget-history"><strong>Approval history</strong>{historyQ.data.map(entry => <div key={entry.id}><span>{label(entry.from_status ?? 'Created')} → {label(entry.to_status)}</span><small>{new Date(entry.changed_at).toLocaleString('en-GB')} · {entry.note || 'No comment'}</small></div>)}</div>}
            {error && <div className="form-alert error">{error}</div>}
            <div className="form-actions">
              {selected.status === 'draft' && canManage && <button className="outline-button" onClick={() => void openEdit(selected)} disabled={busy}>Edit draft</button>}
              {selected.status === 'draft' && canManage && <button className="primary-button" onClick={() => void transition(selected, 'submitted')} disabled={busy || selectedLines.length === 0}><Send size={13} /> Submit for approval</button>}
              {selected.status === 'submitted' && canApprove && <button className="primary-button" onClick={() => void transition(selected, 'approved')} disabled={busy}><CheckCircle2 size={13} /> Approve budget</button>}
              {selected.status === 'submitted' && canApprove && <button className="outline-button" onClick={() => { setShowReject(true); setRejectNote('') }} disabled={busy}><XCircle size={13} /> Reject</button>}
              {(selected.status === 'approved' || selected.status === 'rejected') && canManage && <button className="outline-button" onClick={() => void createRevision(selected)} disabled={busy}><Copy size={13} /> Create new revision</button>}
            </div>
          </div>
        </Modal>
      )}

      {showReject && selected && (
        <Modal title="Reject budget revision" description="A reason is required and will be saved in the approval history." eyebrow="BUDGET APPROVAL" size="medium" onClose={() => setShowReject(false)} closeDisabled={busy}>
          <form className="data-form" onSubmit={event => { event.preventDefault(); void transition(selected, 'rejected', rejectNote) }}>
            <label className="form-wide">Reason for rejection<textarea required minLength={3} maxLength={1000} rows={4} value={rejectNote} onChange={event => setRejectNote(event.target.value)} placeholder="Explain what needs to be revised…" /></label>
            {error && <div className="form-alert error form-wide">{error}</div>}
            <div className="form-actions form-wide"><button type="button" className="outline-button" onClick={() => setShowReject(false)} disabled={busy}>Cancel</button><button className="primary-button" disabled={busy || rejectNote.trim().length < 3}>{busy ? 'Rejecting…' : 'Confirm rejection'}</button></div>
          </form>
        </Modal>
      )}

      <div className="workspace-heading">
        <div><p className="eyebrow">PROJECT COST MANAGEMENT</p><h1>Project Budgets</h1><p className="page-subtitle">Prepare, submit and approve controlled project budget revisions.</p></div>
        {canManage && <button className="primary-button" onClick={openCreate} disabled={projects.length === 0 || codes.length === 0}><Plus size={15} /> New budget</button>}
      </div>

      <div className="stat-strip">
        <div><span>Total revisions</span><strong>{budgets.length}</strong></div>
        <div><span>Draft</span><strong>{totals.draft}</strong></div>
        <div><span>Awaiting approval</span><strong>{totals.submitted}</strong></div>
        <div><span>Approved revisions</span><strong>{totals.approved}</strong></div>
      </div>

      <section className="data-panel">
        <div className="list-toolbar">
          <div className="filter-tabs">
            {(['all','draft','submitted','approved','rejected'] as const).map(status => <button key={status} className={statusFilter === status ? 'selected' : ''} onClick={() => setStatusFilter(status)}>{status === 'all' ? 'All budgets' : label(status)}</button>)}
          </div>
          <div className="search-box"><Search size={15} /><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Search projects and revisions…" /></div>
        </div>
        {error && !showEditor && !selected && <div className="form-alert error">{error}</div>}
        {budgetsQ.isLoading || projectsQ.isLoading || codesQ.isLoading ? <div className="table-empty">Loading project budgets…</div>
          : budgetsQ.error || projectsQ.error || codesQ.error ? <div className="table-empty error-text">{((budgetsQ.error || projectsQ.error || codesQ.error) as Error).message}</div>
          : filtered.length === 0 ? <div className="table-empty"><ClipboardList size={24} /><strong>No project budgets found</strong><span>Create a draft budget for a project with active cost codes.</span></div>
          : <div className="table-scroll"><table className="data-table"><thead><tr><th>Project</th><th>Revision</th><th>Status</th><th>Currency</th><th>Created</th><th /></tr></thead><tbody>
            {filtered.map(item => {
              const project = projects.find(candidate => candidate.id === item.project_id)
              return <tr key={item.id}><td><strong>{project?.project_code ?? '—'}</strong><small>{project?.name ?? 'Unknown project'}</small></td><td>Rev {item.revision_number}</td><td><span className={'estimate-status ' + item.status}>{label(item.status)}</span></td><td>{item.currency_code}</td><td>{new Date(item.created_at).toLocaleDateString('en-GB')}</td><td><button className="text-button" onClick={() => { setError(''); setSelectedId(item.id) }}>Open →</button></td></tr>
            })}
          </tbody></table></div>}
      </section>
      <p className="page-footnote">Draft revisions are editable. Submitted budgets await owner or administrator approval. Approved revisions remain unchanged; amendments are prepared as a new revision.</p>
    </div>
  )
}
