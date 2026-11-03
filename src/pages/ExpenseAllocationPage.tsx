import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { CheckCircle2, ClipboardList, Plus, Receipt, Save, Trash2 } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
import Modal from '../components/Modal'

type Account = {
  id: string
  account_code: string
  account_name: string
  account_type: string
  is_active: boolean
  is_postable: boolean
  allow_manual_journal: boolean
}
type Project = { id: string; project_code: string; name: string; status: string; currency_code: string }
type CostCode = { id: string; code: string; name: string; category: string }
type CostCentre = { id: string; code: string; name: string; centre_type: string }
type Journal = {
  id: string
  journal_number: string | null
  journal_date: string
  description: string
  reference: string | null
  status: string
  total_debit: number | string
  total_credit: number | string
  created_at: string
  source_module: string
}
type JournalLine = {
  id: string
  journal_entry_id: string
  line_number: number
  account_id: string
  description: string | null
  debit: number | string
  credit: number | string
}
type SavedAllocation = {
  id: string
  journal_line_id: string
  attribution_scope: 'project' | 'overhead'
  project_id: string | null
  cost_code_id: string | null
  cost_centre_id: string | null
  allocation_side: 'debit' | 'credit'
  amount: number | string
  description: string | null
}
type AllocationDraft = {
  attribution_scope: 'project' | 'overhead'
  project_id: string
  cost_code_id: string
  cost_centre_id: string
  allocation_side: 'debit' | 'credit'
  amount: string
  description: string
}
type ExpenseLineDraft = {
  account_id: string
  amount: string
  description: string
  allocations: AllocationDraft[]
}
type SettlementLineDraft = { account_id: string; amount: string; description: string }
type ExpenseForm = {
  journal_date: string
  description: string
  reference: string
  expense_lines: ExpenseLineDraft[]
  settlement_lines: SettlementLineDraft[]
}

const today = () => {
  const date = new Date()
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-')
}
const amount = (value: string | number | null | undefined) => Number(value ?? 0)
const decimalUnits = (value: string | number | null | undefined): bigint | null => {
  const match = /^([+-]?)(\d+)(?:\.(\d{0,4}))?$/.exec(String(value ?? '0').trim())
  if (!match) return null
  const units = BigInt(match[2]) * 10000n + BigInt((match[3] ?? '').padEnd(4, '0') || '0')
  return match[1] === '-' ? -units : units
}
const exactUnits = (value: string | number | null | undefined) => decimalUnits(value) ?? 0n
const sumUnits = (values: Array<string | number | null | undefined>) => values.reduce((sum, value) => sum + exactUnits(value), 0n)
const unitsToString = (units: bigint) => {
  const negative = units < 0n
  const absolute = negative ? -units : units
  const whole = absolute / 10000n
  const fraction = (absolute % 10000n).toString().padStart(4, '0').replace(/0+$/, '')
  return (negative ? '-' : '') + whole.toString() + (fraction ? '.' + fraction : '')
}
const unitsToNumber = (units: bigint) => Number(unitsToString(units))
const isPositiveAmount = (value: string | number | null | undefined) => {
  const units = decimalUnits(value)
  return units !== null && units > 0n
}
const label = (value: string) => value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
const money = (value: number, currency: string) => new Intl.NumberFormat('en-GH', {
  style: 'currency', currency: currency || 'GHS', minimumFractionDigits: 2, maximumFractionDigits: 2,
}).format(value)
const lineAmountText = (line: JournalLine) => isPositiveAmount(line.debit) ? String(line.debit) : String(line.credit)
const lineAmount = (line: JournalLine) => amount(lineAmountText(line))
const lineSide = (line: JournalLine): 'debit' | 'credit' => isPositiveAmount(line.debit) ? 'debit' : 'credit'

function defaultAllocation(projects: Project[], centres: CostCentre[], side: 'debit' | 'credit' = 'debit'): AllocationDraft {
  if (projects.length > 0) {
    return { attribution_scope: 'project', project_id: projects[0].id, cost_code_id: '', cost_centre_id: '', allocation_side: side, amount: '', description: '' }
  }
  return { attribution_scope: 'overhead', project_id: '', cost_code_id: '', cost_centre_id: centres[0]?.id ?? '', allocation_side: side, amount: '', description: '' }
}

function initialForm(accounts: Account[], projects: Project[], centres: CostCentre[]): ExpenseForm {
  return {
    journal_date: today(),
    description: '',
    reference: '',
    expense_lines: [{
      account_id: accounts.find(account => account.account_type === 'expense')?.id ?? '',
      amount: '',
      description: '',
      allocations: [defaultAllocation(projects, centres)],
    }],
    settlement_lines: [{
      account_id: accounts.find(account => ['asset', 'liability'].includes(account.account_type))?.id ?? '',
      amount: '',
      description: '',
    }],
  }
}

export default function ExpenseAllocationPage() {
  const { client, company, roleCode } = useAuth()
  const queryClient = useQueryClient()
  const canRead = ['owner', 'admin', 'accountant'].includes(roleCode ?? '')
  const canCreate = ['owner', 'admin', 'accountant'].includes(roleCode ?? '')
  const canAllocate = ['owner', 'admin', 'accountant', 'project_manager'].includes(roleCode ?? '')
  const canPost = ['owner', 'admin', 'accountant'].includes(roleCode ?? '')
  const [showCreate, setShowCreate] = useState(false)
  const [selectedJournalId, setSelectedJournalId] = useState<string | null>(null)
  const [form, setForm] = useState<ExpenseForm>(() => initialForm([], [], []))
  const [allocationDrafts, setAllocationDrafts] = useState<Record<string, AllocationDraft[]>>({})
  const allocationsLoadedFor = useRef<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const accountsQ = useQuery({
    queryKey: ['expense-allocation-accounts', company?.id],
    enabled: Boolean(client && company && canRead),
    queryFn: async () => {
      const { data, error } = await client!.from('chart_of_accounts')
        .select('id,account_code,account_name,account_type,is_active,is_postable,allow_manual_journal')
        .eq('company_id', company!.id)
        .eq('is_active', true)
        .eq('is_postable', true)
        .eq('allow_manual_journal', true)
        .order('account_code')
      if (error) throw error
      return (data ?? []) as Account[]
    },
  })
  const projectsQ = useQuery({
    queryKey: ['expense-allocation-projects', company?.id],
    enabled: Boolean(client && company && canRead),
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
    queryKey: ['expense-allocation-cost-codes', company?.id],
    enabled: Boolean(client && company && canRead),
    queryFn: async () => {
      const { data, error } = await client!.from('cost_codes')
        .select('id,code,name,category')
        .eq('company_id', company!.id)
        .eq('is_active', true)
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCode[]
    },
  })
  const centresQ = useQuery({
    queryKey: ['expense-allocation-cost-centres', company?.id],
    enabled: Boolean(client && company && canRead),
    queryFn: async () => {
      const { data, error } = await client!.from('cost_centres')
        .select('id,code,name,centre_type')
        .eq('company_id', company!.id)
        .eq('is_active', true)
        .in('centre_type', ['overhead', 'department', 'shared'])
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCentre[]
    },
  })
  const journalsQ = useQuery({
    queryKey: ['expense-allocation-draft-journals', company?.id],
    enabled: Boolean(client && company && canRead),
    queryFn: async () => {
      const { data, error } = await client!.from('journal_entries')
        .select('id,journal_number,journal_date,description,reference,status,total_debit,total_credit,created_at,source_module')
        .eq('company_id', company!.id)
        .eq('status', 'draft')
        .order('journal_date', { ascending: false })
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Journal[]
    },
  })

  const accounts = accountsQ.data ?? []
  const projects = projectsQ.data ?? []
  const costCodes = codesQ.data ?? []
  const costCentres = centresQ.data ?? []
  const journals = journalsQ.data ?? []
  const journalIds = useMemo(() => journals.map(journal => journal.id), [journals])
  const linesQ = useQuery({
    queryKey: ['expense-allocation-draft-lines', company?.id, journalIds],
    enabled: Boolean(client && company && canRead && journalIds.length > 0),
    queryFn: async () => {
      const { data, error } = await client!.from('journal_lines')
        .select('id,journal_entry_id,line_number,account_id,description,debit,credit')
        .eq('company_id', company!.id)
        .in('journal_entry_id', journalIds)
        .order('line_number')
      if (error) throw error
      return (data ?? []) as JournalLine[]
    },
  })
  const allLines = linesQ.data ?? []
  const expenseAccountIds = useMemo(() => new Set(accounts.filter(account => account.account_type === 'expense').map(account => account.id)), [accounts])
  const expenseLines = useMemo(() => allLines.filter(line => expenseAccountIds.has(line.account_id)), [allLines, expenseAccountIds])
  const expenseLineIds = useMemo(() => expenseLines.map(line => line.id), [expenseLines])
  const allocationsQ = useQuery({
    queryKey: ['expense-allocation-existing', company?.id, expenseLineIds],
    enabled: Boolean(client && company && canRead && expenseLineIds.length > 0),
    queryFn: async () => {
      const { data, error } = await client!.from('journal_line_cost_allocations')
        .select('id,journal_line_id,attribution_scope,project_id,cost_code_id,cost_centre_id,allocation_side,amount,description')
        .eq('company_id', company!.id)
        .in('journal_line_id', expenseLineIds)
      if (error) throw error
      return (data ?? []) as SavedAllocation[]
    },
  })

  const draftJournals = useMemo(() => journals.filter(journal => expenseLines.some(line => line.journal_entry_id === journal.id)), [journals, expenseLines])
  const selectedJournal = draftJournals.find(journal => journal.id === selectedJournalId) ?? null
  const selectedExpenseLines = useMemo(
    () => expenseLines.filter(line => line.journal_entry_id === selectedJournalId),
    [expenseLines, selectedJournalId],
  )
  const expenseTotalUnits = sumUnits(form.expense_lines.map(line => line.amount))
  const settlementTotalUnits = sumUnits(form.settlement_lines.map(line => line.amount))
  const expenseTotal = unitsToNumber(expenseTotalUnits)
  const settlementTotal = unitsToNumber(settlementTotalUnits)

  useEffect(() => {
    if (!selectedJournalId || !allocationsQ.data || allocationsLoadedFor.current === selectedJournalId) return
    setAllocationDrafts(current => {
      const next = { ...current }
      selectedExpenseLines.forEach(line => {
        next[line.id] = allocationsQ.data!
          .filter(item => item.journal_line_id === line.id)
          .map(item => ({
            attribution_scope: item.attribution_scope,
            project_id: item.project_id ?? '',
            cost_code_id: item.cost_code_id ?? '',
            cost_centre_id: item.cost_centre_id ?? '',
            allocation_side: item.allocation_side,
            amount: String(item.amount),
            description: item.description ?? '',
          }))
      })
      return next
    })
    allocationsLoadedFor.current = selectedJournalId
  }, [selectedJournalId, allocationsQ.data, selectedExpenseLines])

  function refreshDraftData() {
    if (!company) return
    void queryClient.invalidateQueries({ queryKey: ['expense-allocation-draft-journals', company.id] })
    void queryClient.invalidateQueries({ queryKey: ['expense-allocation-draft-lines', company.id] })
    void queryClient.invalidateQueries({ queryKey: ['expense-allocation-existing', company.id] })
  }

  function openCreate() {
    setForm(initialForm(accounts, projects, costCentres))
    setError('')
    setNotice('')
    setShowCreate(true)
  }

  function updateExpenseLine(index: number, patch: Partial<ExpenseLineDraft>) {
    setForm(current => ({
      ...current,
      expense_lines: current.expense_lines.map((line, lineIndex) => {
        if (lineIndex !== index) return line
        const next = { ...line, ...patch }
        if (patch.amount !== undefined && line.allocations.length === 1) {
          next.allocations = [{ ...line.allocations[0], amount: patch.amount }]
        }
        return next
      }),
    }))
  }

  function updateSettlementLine(index: number, patch: Partial<SettlementLineDraft>) {
    setForm(current => ({
      ...current,
      settlement_lines: current.settlement_lines.map((line, lineIndex) => lineIndex === index ? { ...line, ...patch } : line),
    }))
  }

  function updateNewAllocation(lineIndex: number, allocationIndex: number, patch: Partial<AllocationDraft>) {
    setForm(current => ({
      ...current,
      expense_lines: current.expense_lines.map((line, index) => index === lineIndex
        ? { ...line, allocations: line.allocations.map((allocation, rowIndex) => rowIndex === allocationIndex ? { ...allocation, ...patch } : allocation) }
        : line),
    }))
  }

  function addNewExpenseLine() {
    setForm(current => ({
      ...current,
      expense_lines: [...current.expense_lines, {
        account_id: accounts.find(account => account.account_type === 'expense')?.id ?? '',
        amount: '',
        description: '',
        allocations: [defaultAllocation(projects, costCentres)],
      }],
    }))
  }

  function addNewAllocation(lineIndex: number) {
    setForm(current => ({
      ...current,
      expense_lines: current.expense_lines.map((line, index) => index === lineIndex
        ? { ...line, allocations: [...line.allocations, { ...defaultAllocation(projects, costCentres), amount: '' }] }
        : line),
    }))
  }

  function updateSavedAllocation(lineId: string, index: number, patch: Partial<AllocationDraft>) {
    setAllocationDrafts(current => ({
      ...current,
      [lineId]: (current[lineId] ?? []).map((row, rowIndex) => rowIndex === index ? { ...row, ...patch } : row),
    }))
  }

  function addSavedAllocation(line: JournalLine) {
    setAllocationDrafts(current => ({
      ...current,
      [line.id]: [...(current[line.id] ?? []), { ...defaultAllocation(projects, costCentres, lineSide(line)), amount: '' }],
    }))
  }

  async function saveLineAllocations(line: JournalLine) {
    if (!client || !company) return
    if (allocationsQ.isLoading || allocationsQ.isFetching || allocationsQ.isError || !allocationsQ.data) {
      setError('Wait for saved allocation details to finish loading before changing this line.')
      return
    }
    const rows = allocationDrafts[line.id] ?? []
    const total = sumUnits(rows.map(row => row.amount))
    if (total > exactUnits(lineAmountText(line))) {
      setError('The allocation total cannot exceed the journal line amount.')
      return
    }
    if (rows.some(row => !isPositiveAmount(row.amount) || (row.attribution_scope === 'project' ? !row.project_id : !row.cost_centre_id))) {
      setError('Complete each allocation row with a valid destination and a positive amount.')
      return
    }
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const { error } = await client.rpc('replace_journal_line_cost_allocations', {
        p_company_id: company.id,
        p_journal_line_id: line.id,
        p_allocations: rows.map(row => ({
          attribution_scope: row.attribution_scope,
          project_id: row.attribution_scope === 'project' ? row.project_id : null,
          cost_code_id: row.cost_code_id || null,
          cost_centre_id: row.attribution_scope === 'overhead' ? row.cost_centre_id : null,
          allocation_side: lineSide(line),
          amount: row.amount,
          description: row.description.trim() || null,
        })),
      })
      if (error) throw error
      await queryClient.invalidateQueries({ queryKey: ['expense-allocation-existing', company.id] })
      setNotice('Allocations saved for this expense line.')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save this line allocation.')
    } finally {
      setBusy(false)
    }
  }

  async function createAndPostExpense(event: FormEvent) {
    event.preventDefault()
    if (!client || !company) return
    if (!form.journal_date || form.description.trim().length < 2) {
      setError('Enter the expense date and a clear description.')
      return
    }
    if (form.expense_lines.length === 0 || form.expense_lines.some(line => !line.account_id || !isPositiveAmount(line.amount))) {
      setError('Every expense line needs an expense account and a positive amount.')
      return
    }
    if (form.settlement_lines.length === 0 || form.settlement_lines.some(line => !line.account_id || !isPositiveAmount(line.amount))) {
      setError('Add at least one payment or payable account with a positive amount.')
      return
    }
    if (sumUnits(form.expense_lines.map(line => line.amount)) !== sumUnits(form.settlement_lines.map(line => line.amount))) {
      setError('The payment/payable total must equal the total expense amount.')
      return
    }
    for (const line of form.expense_lines) {
      const allocated = sumUnits(line.allocations.map(row => row.amount))
      if (line.allocations.length === 0 || allocated !== exactUnits(line.amount)) {
        setError('Allocate the full amount of every expense line before creating the journal.')
        return
      }
      if (line.allocations.some(row => !isPositiveAmount(row.amount) || (row.attribution_scope === 'project' ? !row.project_id : !row.cost_centre_id))) {
        setError('Each allocation needs a valid project or overhead cost centre and a positive amount.')
        return
      }
    }

    setBusy(true)
    setError('')
    setNotice('')
    let createdJournalId: string | null = null
    try {
      const journalLines = [
        ...form.expense_lines.map(line => ({
          account_id: line.account_id,
          debit: line.amount,
          credit: '0',
          description: line.description.trim() || null,
        })),
        ...form.settlement_lines.map(line => ({
          account_id: line.account_id,
          debit: '0',
          credit: line.amount,
          description: line.description.trim() || null,
        })),
      ]
      const { data: journalId, error: createError } = await client.rpc('create_journal_draft', {
        p_company_id: company.id,
        p_journal_date: form.journal_date,
        p_description: form.description.trim(),
        p_lines: journalLines,
        p_reference: form.reference.trim() || null,
        p_idempotency_key: 'expense-' + crypto.randomUUID(),
        p_branch_id: null,
      })
      if (createError) throw createError
      createdJournalId = journalId as string

      const { data: createdLines, error: linesError } = await client.from('journal_lines')
        .select('id,journal_entry_id,line_number,account_id,description,debit,credit')
        .eq('company_id', company.id)
        .eq('journal_entry_id', createdJournalId)
        .order('line_number')
      if (linesError) throw linesError

      for (let index = 0; index < form.expense_lines.length; index += 1) {
        const journalLine = (createdLines ?? []).find(line => line.line_number === index + 1)
        if (!journalLine) throw new Error('The expense journal was created, but its expense line could not be reloaded.')
        const allocationRows = form.expense_lines[index].allocations
        const { error: allocationError } = await client.rpc('replace_journal_line_cost_allocations', {
          p_company_id: company.id,
          p_journal_line_id: journalLine.id,
          p_allocations: allocationRows.map(row => ({
            attribution_scope: row.attribution_scope,
            project_id: row.attribution_scope === 'project' ? row.project_id : null,
            cost_code_id: row.cost_code_id || null,
            cost_centre_id: row.attribution_scope === 'overhead' ? row.cost_centre_id : null,
            allocation_side: 'debit',
            amount: row.amount,
            description: row.description.trim() || null,
          })),
        })
        if (allocationError) throw allocationError
      }

      const { error: postError } = await client.rpc('post_journal_entry', { p_journal_entry_id: createdJournalId })
      if (postError) throw postError
      setShowCreate(false)
      setNotice('Expense journal posted successfully.')
      setSelectedJournalId(null)
      refreshDraftData()
      await queryClient.invalidateQueries({ queryKey: ['expense-allocation-draft-journals', company.id] })
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : 'The expense could not be completed.'
      if (createdJournalId) {
        setShowCreate(false)
        setSelectedJournalId(createdJournalId)
        setNotice('Draft journal ' + createdJournalId + ' was created, but the remaining step failed: ' + message + ' Review the draft below before retrying.')
        refreshDraftData()
      } else {
        setError(message)
      }
    } finally {
      setBusy(false)
    }
  }

  async function postExistingDraft(journal: Journal) {
    if (!client || !company) return
    const lines = selectedExpenseLines
    if (allocationsQ.isLoading || allocationsQ.isFetching || allocationsQ.isError || !allocationsQ.data) {
      setError('Wait for the saved allocation details to finish loading before posting.')
      return
    }
    const incomplete = lines.filter(line => {
      const rows = allocationsQ.data!.filter(row => row.journal_line_id === line.id)
      const total = sumUnits(rows.map(row => row.amount))
      return total !== exactUnits(lineAmountText(line))
    })
    if (incomplete.length > 0) {
      setError('Every expense debit and credit must be fully allocated before posting.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const { error } = await client.rpc('post_journal_entry', { p_journal_entry_id: journal.id })
      if (error) throw error
      setSelectedJournalId(null)
      setNotice('Journal posted successfully.')
      refreshDraftData()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The journal could not be posted.')
    } finally {
      setBusy(false)
    }
  }

  const loading = accountsQ.isLoading || projectsQ.isLoading || codesQ.isLoading || centresQ.isLoading || journalsQ.isLoading || linesQ.isLoading || allocationsQ.isLoading
  const queryError = accountsQ.error || projectsQ.error || codesQ.error || centresQ.error || journalsQ.error || linesQ.error || allocationsQ.error
  const currency = company?.base_currency ?? 'GHS'

  if (!canRead) {
    return <div className="page-content"><section className="module-status-panel"><h2>Accounting access required</h2><p>Your role does not currently have permission to view draft journal entries. Ask a company administrator to review your accounting access.</p></section></div>
  }

  return (
    <div className="page-content">
      {showCreate && (
        <Modal
          title="Record project expense"
          description="Create a balanced draft journal, allocate every expense line, then post it to the ledger."
          eyebrow="EXPENSE ALLOCATION"
          size="large"
          onClose={() => setShowCreate(false)}
          closeDisabled={busy}
        >
          <form className="data-form expense-create-form" onSubmit={createAndPostExpense}>
            <label>Expense date<input required type="date" value={form.journal_date} onChange={event => setForm({ ...form, journal_date: event.target.value })} /></label>
            <label>Reference<input maxLength={100} value={form.reference} onChange={event => setForm({ ...form, reference: event.target.value })} placeholder="Receipt / supplier invoice number" /></label>
            <label className="form-wide">Description<input required minLength={2} maxLength={500} value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} placeholder="e.g. Cement purchase for site works" /></label>

            <div className="form-wide expense-form-section">
              <div className="list-toolbar"><strong className="section-title">Expense lines</strong><button type="button" className="outline-button" onClick={addNewExpenseLine}><Plus size={13} /> Add expense line</button></div>
              {form.expense_lines.map((line, index) => (
                <div className="expense-entry-card" key={index}>
                  <div className="expense-entry-heading"><strong>Expense line {index + 1}</strong>{form.expense_lines.length > 1 && <button type="button" className="text-button danger-text" onClick={() => setForm(current => ({ ...current, expense_lines: current.expense_lines.filter((_, rowIndex) => rowIndex !== index) }))}><Trash2 size={12} /> Remove</button>}</div>
                  <div className="expense-entry-grid">
                    <label>Expense account<select required value={line.account_id} onChange={event => updateExpenseLine(index, { account_id: event.target.value })}><option value="">Select expense account</option>{accounts.filter(account => account.account_type === 'expense').map(account => <option key={account.id} value={account.id}>{account.account_code} · {account.account_name}</option>)}</select></label>
                    <label>Amount ({currency})<input required type="number" min="0.0001" step="0.0001" value={line.amount} onChange={event => updateExpenseLine(index, { amount: event.target.value })} placeholder="0.00" /></label>
                    <label className="expense-description">Line description<input maxLength={250} value={line.description} onChange={event => updateExpenseLine(index, { description: event.target.value })} placeholder="Optional line detail" /></label>
                  </div>
                  <div className="expense-allocation-heading"><strong>Allocate this expense</strong><span>{money(unitsToNumber(sumUnits(line.allocations.map(row => row.amount))), currency)} of {money(amount(line.amount), currency)}</span></div>
                  {line.allocations.map((allocation, allocationIndex) => (
                    <div className="allocation-editor-row" key={allocationIndex}>
                      <label>Destination<select value={allocation.attribution_scope} onChange={event => updateNewAllocation(index, allocationIndex, { attribution_scope: event.target.value as 'project' | 'overhead', project_id: event.target.value === 'project' ? projects[0]?.id ?? '' : '', cost_centre_id: event.target.value === 'overhead' ? costCentres[0]?.id ?? '' : '' })}><option value="project">Project</option><option value="overhead">Overhead</option></select></label>
                      {allocation.attribution_scope === 'project' ? (
                        <>
                          <label>Project<select required value={allocation.project_id} onChange={event => updateNewAllocation(index, allocationIndex, { project_id: event.target.value })}><option value="">Select project</option>{projects.map(project => <option key={project.id} value={project.id}>{project.project_code} · {project.name}</option>)}</select></label>
                          <label>Cost code<select value={allocation.cost_code_id} onChange={event => updateNewAllocation(index, allocationIndex, { cost_code_id: event.target.value })}><option value="">Unclassified</option>{costCodes.map(code => <option key={code.id} value={code.id}>{code.code} · {code.name}</option>)}</select></label>
                        </>
                      ) : (
                        <label>Cost centre<select required value={allocation.cost_centre_id} onChange={event => updateNewAllocation(index, allocationIndex, { cost_centre_id: event.target.value })}><option value="">Select cost centre</option>{costCentres.map(centre => <option key={centre.id} value={centre.id}>{centre.code} · {centre.name}</option>)}</select></label>
                      )}
                      <label>Allocated amount<input required type="number" min="0.0001" step="0.0001" value={allocation.amount} onChange={event => updateNewAllocation(index, allocationIndex, { amount: event.target.value })} placeholder="0.00" /></label>
                      <button type="button" className="icon-remove" aria-label="Remove allocation" disabled={line.allocations.length === 1} onClick={() => setForm(current => ({ ...current, expense_lines: current.expense_lines.map((item, rowIndex) => rowIndex === index ? { ...item, allocations: item.allocations.filter((_, allocIndex) => allocIndex !== allocationIndex) } : item) }))}><Trash2 size={14} /></button>
                    </div>
                  ))}
                  <button type="button" className="text-button add-allocation-button" onClick={() => addNewAllocation(index)}><Plus size={12} /> Split across another destination</button>
                </div>
              ))}
            </div>

            <div className="form-wide expense-form-section">
              <div className="list-toolbar"><strong className="section-title">Payment / payable accounts</strong><button type="button" className="outline-button" onClick={() => setForm(current => ({ ...current, settlement_lines: [...current.settlement_lines, { account_id: accounts.find(account => ['asset', 'liability'].includes(account.account_type))?.id ?? '', amount: '', description: '' }] }))}><Plus size={13} /> Add settlement line</button></div>
              {form.settlement_lines.map((line, index) => (
                <div className="settlement-editor-row" key={index}>
                  <label>Credit account<select required value={line.account_id} onChange={event => updateSettlementLine(index, { account_id: event.target.value })}><option value="">Select account</option>{accounts.filter(account => ['asset', 'liability'].includes(account.account_type)).map(account => <option key={account.id} value={account.id}>{account.account_code} · {account.account_name}</option>)}</select></label>
                  <label>Amount ({currency})<input required type="number" min="0.0001" step="0.0001" value={line.amount} onChange={event => updateSettlementLine(index, { amount: event.target.value })} placeholder="0.00" /></label>
                  <label>Line description<input maxLength={250} value={line.description} onChange={event => updateSettlementLine(index, { description: event.target.value })} placeholder="Cash, bank or supplier payable" /></label>
                  <button type="button" className="icon-remove" aria-label="Remove settlement line" disabled={form.settlement_lines.length === 1} onClick={() => setForm(current => ({ ...current, settlement_lines: current.settlement_lines.filter((_, rowIndex) => rowIndex !== index) }))}><Trash2 size={14} /></button>
                </div>
              ))}
            </div>

            <div className="form-wide expense-totals">
              <div><span>Total expense debit</span><strong>{money(expenseTotal, currency)}</strong></div>
              <div><span>Total payment / payable credit</span><strong>{money(settlementTotal, currency)}</strong></div>
              <div><span>Difference</span><strong className={sumUnits(form.expense_lines.map(line => line.amount)) === sumUnits(form.settlement_lines.map(line => line.amount)) ? 'balanced' : 'unbalanced'}>{money(unitsToNumber(expenseTotalUnits >= settlementTotalUnits ? expenseTotalUnits - settlementTotalUnits : settlementTotalUnits - expenseTotalUnits), currency)}</strong></div>
            </div>
            {error && <div className="form-alert error form-wide">{error}</div>}
            <div className="form-actions form-wide"><button type="button" className="outline-button" onClick={() => setShowCreate(false)} disabled={busy}>Cancel</button><button className="primary-button" disabled={busy || accounts.filter(account => account.account_type === 'expense').length === 0 || accounts.filter(account => ['asset', 'liability'].includes(account.account_type)).length === 0}>{busy ? 'Creating and posting…' : 'Create and post expense'}</button></div>
          </form>
        </Modal>
      )}

      {selectedJournal && (
        <Modal
          title={selectedJournal.journal_number || 'Draft expense journal'}
          description={selectedJournal.description + ' · ' + new Date(selectedJournal.journal_date + 'T00:00:00').toLocaleDateString('en-GB')}
          eyebrow="DRAFT EXPENSE ALLOCATION"
          size="large"
          onClose={() => { allocationsLoadedFor.current = null; setSelectedJournalId(null); setError('') }}
          closeDisabled={busy}
        >
          <div className="expense-draft-detail">
            <div className="budget-detail-meta"><span>Reference</span><strong>{selectedJournal.reference || '—'}</strong><span>Source</span><strong>{label(selectedJournal.source_module)}</strong><span>Total journal</span><strong>{money(amount(selectedJournal.total_debit), currency)}</strong></div>
            {selectedExpenseLines.map(line => {
              const rows = allocationDrafts[line.id] ?? []
              const allocatedUnits = sumUnits(rows.map(row => row.amount))
              const remainingUnits = exactUnits(lineAmountText(line)) - allocatedUnits
              const remaining = unitsToNumber(remainingUnits)
              return (
                <section className="draft-expense-line" key={line.id}>
                  <div className="draft-expense-heading"><div><strong>{accounts.find(account => account.id === line.account_id)?.account_code ?? 'Expense account'} · {accounts.find(account => account.id === line.account_id)?.account_name ?? 'Expense'}</strong><small>{line.description || 'Expense journal line'} · {label(lineSide(line))}</small></div><div><strong>{money(lineAmount(line), currency)}</strong><small className={remainingUnits === 0n ? 'balanced' : 'unbalanced'}>{remainingUnits === 0n ? 'Fully allocated' : money(remaining, currency) + ' remaining'}</small></div></div>
                  {allocationsQ.isLoading ? <p className="helper-text">Loading saved allocations…</p> : rows.map((row, index) => (
                    <div className="allocation-editor-row saved-allocation-row" key={index}>
                      <label>Destination<select value={row.attribution_scope} disabled={!canAllocate} onChange={event => updateSavedAllocation(line.id, index, { attribution_scope: event.target.value as 'project' | 'overhead', project_id: event.target.value === 'project' ? projects[0]?.id ?? '' : '', cost_centre_id: event.target.value === 'overhead' ? costCentres[0]?.id ?? '' : '' })}><option value="project">Project</option><option value="overhead">Overhead</option></select></label>
                      {row.attribution_scope === 'project' ? (
                        <>
                          <label>Project<select value={row.project_id} disabled={!canAllocate} onChange={event => updateSavedAllocation(line.id, index, { project_id: event.target.value })}><option value="">Select project</option>{projects.map(project => <option key={project.id} value={project.id}>{project.project_code} · {project.name}</option>)}</select></label>
                          <label>Cost code<select value={row.cost_code_id} disabled={!canAllocate} onChange={event => updateSavedAllocation(line.id, index, { cost_code_id: event.target.value })}><option value="">Unclassified</option>{costCodes.map(code => <option key={code.id} value={code.id}>{code.code} · {code.name}</option>)}</select></label>
                        </>
                      ) : (
                        <label>Cost centre<select value={row.cost_centre_id} disabled={!canAllocate} onChange={event => updateSavedAllocation(line.id, index, { cost_centre_id: event.target.value })}><option value="">Select cost centre</option>{costCentres.map(centre => <option key={centre.id} value={centre.id}>{centre.code} · {centre.name}</option>)}</select></label>
                      )}
                      <label>Amount<input type="number" min="0.0001" step="0.0001" value={row.amount} disabled={!canAllocate} onChange={event => updateSavedAllocation(line.id, index, { amount: event.target.value })} /></label>
                      {canAllocate && <button type="button" className="icon-remove" aria-label="Remove allocation" onClick={() => setAllocationDrafts(current => ({ ...current, [line.id]: (current[line.id] ?? []).filter((_, rowIndex) => rowIndex !== index) }))}><Trash2 size={14} /></button>}
                    </div>
                  ))}
                  {canAllocate && <div className="draft-line-actions"><button type="button" className="text-button" onClick={() => addSavedAllocation(line)}><Plus size={12} /> Add allocation</button><button type="button" className="outline-button" onClick={() => void saveLineAllocations(line)} disabled={busy || allocationsQ.isLoading || allocationsQ.isFetching || allocationsQ.isError || !allocationsQ.data}><Save size={12} /> Save line allocations</button></div>}
                </section>
              )
            })}
            {error && <div className="form-alert error">{error}</div>}
            <div className="form-actions">
              {canPost && <button type="button" className="primary-button" onClick={() => void postExistingDraft(selectedJournal)} disabled={busy || selectedExpenseLines.length === 0 || allocationsQ.isLoading || allocationsQ.isFetching || allocationsQ.isError || !allocationsQ.data}><CheckCircle2 size={13} /> {busy ? 'Posting…' : 'Post journal'}</button>}
            </div>
            <p className="page-footnote">Posting is permitted only when each expense debit and credit is fully allocated and the journal passes the database accounting-period and double-entry checks.</p>
          </div>
        </Modal>
      )}

      <div className="workspace-heading">
        <div><p className="eyebrow">FINANCE · PROJECT COST CONTROL</p><h1>Expense Allocation</h1><p className="page-subtitle">Record expenses, distribute costs and post verified project and overhead allocations.</p></div>
        {canCreate && <button className="primary-button" onClick={openCreate}><Plus size={15} /> Record expense</button>}
      </div>

      <div className="stat-strip">
        <div><span>Draft expense journals</span><strong>{draftJournals.length}</strong></div>
        <div><span>Expense lines awaiting allocation</span><strong>{expenseLines.filter(line => {
          const saved = allocationsQ.data?.filter(item => item.journal_line_id === line.id) ?? []
          return sumUnits(saved.map(item => item.amount)) !== exactUnits(lineAmountText(line))
        }).length}</strong></div>
        <div><span>Active projects</span><strong>{projects.length}</strong></div>
        <div><span>Currency</span><strong>{currency}</strong></div>
      </div>

      {notice && <div className="form-alert success expense-notice">{notice}</div>}
      {queryError && <div className="form-alert error">{(queryError as Error).message}</div>}
      <section className="data-panel">
        <div className="list-toolbar"><div><strong className="section-title">Draft expense journals</strong><span className="subtle-count"> · {draftJournals.length} awaiting completion</span></div><span className="helper-text">Only draft journals with expense-account lines appear here.</span></div>
        {loading ? <div className="table-empty">Loading expense journals…</div>
          : queryError ? <div className="table-empty error-text">Could not load expense journals.</div>
          : draftJournals.length === 0 ? <div className="table-empty"><Receipt size={24} /><strong>No draft expense journals</strong><span>Record a new expense or open a draft journal created by another workflow to complete its cost allocations.</span></div>
          : <div className="table-scroll"><table className="data-table"><thead><tr><th>Date</th><th>Journal / description</th><th>Expense lines</th><th className="numeric">Journal total</th><th>Status</th><th /></tr></thead><tbody>
            {draftJournals.map(journal => {
              const count = expenseLines.filter(line => line.journal_entry_id === journal.id).length
              const allocated = expenseLines.filter(line => line.journal_entry_id === journal.id).every(line => {
                const saved = allocationsQ.data?.filter(item => item.journal_line_id === line.id) ?? []
                return sumUnits(saved.map(item => item.amount)) === exactUnits(lineAmountText(line))
              })
              return <tr key={journal.id}><td>{new Date(journal.journal_date + 'T00:00:00').toLocaleDateString('en-GB')}</td><td><strong>{journal.journal_number || 'Draft journal'}</strong><small>{journal.description}</small></td><td>{count}</td><td className="numeric">{money(amount(journal.total_debit), currency)}</td><td><span className={'estimate-status ' + (allocated ? 'approved' : 'submitted')}>{allocated ? 'Allocated' : 'Needs allocation'}</span></td><td><button className="text-button" onClick={() => { setError(''); setSelectedJournalId(journal.id) }}>Review →</button></td></tr>
            })}
          </tbody></table></div>}
      </section>
      <p className="page-footnote"><ClipboardList size={13} /> Expense journals are created and posted through the existing database RPCs. Direct edits to posted journals are not permitted; corrections must use the established reversal workflow.</p>
    </div>
  )
}
