import { useMemo, useState } from 'react'
import { AlertTriangle, BarChart3, TrendingUp } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '../contexts/AuthContext'
import { exactUnits, unitsToNumber } from '../lib/decimalAmount'

type Project = {
  id: string
  project_code: string
  name: string
  status: string
  currency_code: string
}
type BudgetVersion = {
  id: string
  project_id: string
  revision_number: number
  currency_code: string
}
type BudgetLine = {
  id: string
  budget_version_id: string
  project_id: string
  cost_code_id: string
  approved_amount: number | string
}
type ActualCost = {
  project_id: string
  project_code: string
  project_name: string
  cost_code_id: string | null
  cost_code: string | null
  cost_code_name: string | null
  journal_date: string
  signed_cost: number | string
}
type CostCode = { id: string; code: string; name: string; category: string }

const label = (value: string) => value.replaceAll('_', ' ').replace(/\\b\\w/g, character => character.toUpperCase())
const money = (value: number, currency: string) => new Intl.NumberFormat('en-GH', {
  style: 'currency', currency: currency || 'GHS', minimumFractionDigits: 2, maximumFractionDigits: 2,
}).format(value)

export default function BudgetVsActualPage() {
  const { client, company } = useAuth()
  const [projectFilter, setProjectFilter] = useState('all')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')

  const projectsQ = useQuery({
    queryKey: ['budget-actual-projects', company?.id],
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

  const versionsQ = useQuery({
    queryKey: ['budget-actual-approved-versions', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!.from('project_budget_versions')
        .select('id,project_id,revision_number,currency_code')
        .eq('company_id', company!.id)
        .eq('status', 'approved')
        .order('revision_number', { ascending: false })
      if (error) throw error
      return (data ?? []) as BudgetVersion[]
    },
  })

  const latestVersions = useMemo(() => {
    const seen = new Set<string>()
    return (versionsQ.data ?? []).filter(version => {
      if (seen.has(version.project_id)) return false
      seen.add(version.project_id)
      return true
    })
  }, [versionsQ.data])
  const versionIds = latestVersions.map(version => version.id)

  const budgetsQ = useQuery({
    queryKey: ['budget-actual-approved-lines', company?.id, versionIds.join(',')],
    enabled: Boolean(client && company && versionsQ.isSuccess),
    queryFn: async () => {
      if (versionIds.length === 0) return [] as BudgetLine[]
      const { data, error } = await client!.from('project_budgets')
        .select('id,budget_version_id,project_id,cost_code_id,approved_amount')
        .eq('company_id', company!.id)
        .in('budget_version_id', versionIds)
      if (error) throw error
      return (data ?? []) as BudgetLine[]
    },
  })

  const actualsQ = useQuery({
    queryKey: ['budget-actual-posted-costs', company?.id, fromDate, toDate],
    enabled: Boolean(client && company && (!fromDate || !toDate || fromDate <= toDate)),
    queryFn: async () => {
      let query = client!.from('project_cost_ledger')
        .select('project_id,project_code,project_name,cost_code_id,cost_code,cost_code_name,journal_date,signed_cost')
        .eq('company_id', company!.id)
        .order('journal_date', { ascending: false })
      if (fromDate) query = query.gte('journal_date', fromDate)
      if (toDate) query = query.lte('journal_date', toDate)
      const { data, error } = await query
      if (error) throw error
      return (data ?? []) as ActualCost[]
    },
  })

  const codesQ = useQuery({
    queryKey: ['budget-actual-cost-codes', company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!.from('cost_codes')
        .select('id,code,name,category')
        .eq('company_id', company!.id)
        .order('code')
      if (error) throw error
      return (data ?? []) as CostCode[]
    },
  })

  const projects = projectsQ.data ?? []
  const codes = codesQ.data ?? []
  const currency = company?.base_currency ?? 'GHS'
  const selectedProjects = projects.filter(project => projectFilter === 'all' || project.id === projectFilter)
  const selectedProjectIds = new Set(selectedProjects.map(project => project.id))
  const approvedByVersion = new Map(latestVersions.map(version => [version.project_id, version]))
  const budgetRows = (budgetsQ.data ?? []).filter(line => selectedProjectIds.has(line.project_id))
  const actualRows = (actualsQ.data ?? []).filter(row => selectedProjectIds.has(row.project_id))

  const reportRows = useMemo(() => {
    const keyFor = (projectId: string, costCodeId: string | null) => projectId + ':' + (costCodeId ?? 'unclassified')
    const grouped = new Map<string, {
      projectId: string
      costCodeId: string | null
      budgetUnits: bigint
      actualUnits: bigint
    }>()
    for (const line of budgetRows) {
      const key = keyFor(line.project_id, line.cost_code_id)
      const row = grouped.get(key) ?? { projectId: line.project_id, costCodeId: line.cost_code_id, budgetUnits: 0n, actualUnits: 0n }
      row.budgetUnits += exactUnits(line.approved_amount)
      grouped.set(key, row)
    }
    for (const actual of actualRows) {
      const key = keyFor(actual.project_id, actual.cost_code_id)
      const row = grouped.get(key) ?? { projectId: actual.project_id, costCodeId: actual.cost_code_id, budgetUnits: 0n, actualUnits: 0n }
      row.actualUnits += exactUnits(actual.signed_cost)
      grouped.set(key, row)
    }
    return Array.from(grouped.values()).map(row => {
      const project = projects.find(item => item.id === row.projectId)
      const code = codes.find(item => item.id === row.costCodeId)
      const budgetCurrency = approvedByVersion.get(row.projectId)?.currency_code ?? project?.currency_code ?? currency
      const currencyComparable = budgetCurrency === currency
      const varianceUnits = currencyComparable ? row.budgetUnits - row.actualUnits : null
      return {
        ...row,
        project,
        code,
        budgetCurrency,
        currencyComparable,
        varianceUnits,
        utilisation: row.budgetUnits > 0n && currencyComparable
          ? Number(row.actualUnits * 10000n / row.budgetUnits) / 100
          : null,
      }
    }).sort((a, b) => (a.project?.project_code ?? '').localeCompare(b.project?.project_code ?? '')
      || (a.code?.code ?? 'ZZZ').localeCompare(b.code?.code ?? 'ZZZ'))
  }, [budgetRows, actualRows, projects, codes, approvedByVersion, currency])

  const currencySummaries = useMemo(() => {
    const groups = new Map<string, { budget: bigint; actual: bigint; comparable: boolean; projects: Set<string> }>()
    for (const row of reportRows) {
      const key = row.currencyComparable ? currency : row.budgetCurrency
      const group = groups.get(key) ?? { budget: 0n, actual: 0n, comparable: row.currencyComparable, projects: new Set<string>() }
      group.budget += row.budgetUnits
      if (row.currencyComparable) group.actual += row.actualUnits
      group.comparable = group.comparable && row.currencyComparable
      group.projects.add(row.projectId)
      groups.set(key, group)
    }
    return Array.from(groups.entries()).map(([code, value]) => ({ code, ...value }))
  }, [reportRows, currency])

  const loading = projectsQ.isLoading || versionsQ.isLoading || budgetsQ.isLoading || actualsQ.isLoading || codesQ.isLoading
  const queryError = projectsQ.error || versionsQ.error || budgetsQ.error || actualsQ.error || codesQ.error
  const invalidDates = Boolean(fromDate && toDate && fromDate > toDate)
  const approvedProjectCount = new Set(budgetRows.map(line => line.project_id)).size
  const hasCurrencyMismatch = reportRows.some(row => !row.currencyComparable)

  return (
    <div className="page-content">
      <div className="workspace-heading">
        <div>
          <p className="eyebrow">MANAGEMENT REPORTING · PHASE 7.4</p>
          <h1>Budget vs Actual</h1>
          <p className="page-subtitle">Compare each project's latest approved cost budget with posted project costs by cost code.</p>
        </div>
        <span className="report-icon"><BarChart3 size={19} /></span>
      </div>

      <section className="data-panel budget-actual-filters">
        <div className="list-toolbar"><strong className="section-title">Report filters</strong><button className="text-button" onClick={() => { setProjectFilter('all'); setFromDate(''); setToDate('') }}>Clear filters</button></div>
        <div className="budget-actual-filter-grid">
          <label>Project
            <select value={projectFilter} onChange={event => setProjectFilter(event.target.value)}>
              <option value="all">All projects</option>
              {projects.map(project => <option key={project.id} value={project.id}>{project.project_code} · {project.name}</option>)}
            </select>
          </label>
          <label>Actual costs from<input type="date" value={fromDate} max={toDate || undefined} onChange={event => setFromDate(event.target.value)} /></label>
          <label>Actual costs to<input type="date" value={toDate} min={fromDate || undefined} onChange={event => setToDate(event.target.value)} /></label>
        </div>
        <p className="helper-text">The approved budget is the latest approved revision. Date filters apply to posted actual costs only; budgets are not prorated.</p>
      </section>

      {invalidDates && <div className="form-alert error">The start date cannot be later than the end date.</div>}
      {hasCurrencyMismatch && <div className="form-alert error budget-actual-warning"><AlertTriangle size={15} /> Some project budgets use a different currency from the company's accounting currency ({currency}). Their budget and actual figures are shown separately and no variance is calculated. Foreign-exchange conversion is not yet part of this report.</div>}
      {queryError && <div className="form-alert error">{(queryError as Error).message}</div>}

      <div className="budget-actual-summary-grid">
        {currencySummaries.length === 0
          ? <div className="stat-strip"><div><span>Approved budget projects</span><strong>{approvedProjectCount}</strong></div><div><span>Posted cost entries</span><strong>{actualRows.length}</strong></div><div><span>Company currency</span><strong>{currency}</strong></div></div>
          : currencySummaries.map(group => (
            <div className="data-panel budget-actual-summary" key={group.code}>
              <div><span>{group.code} approved budget</span><strong>{money(unitsToNumber(group.budget), group.code)}</strong></div>
              {group.comparable
                ? <><div><span>Posted actual cost</span><strong>{money(unitsToNumber(group.actual), group.code)}</strong></div><div><span>Remaining / (overrun)</span><strong className={group.budget - group.actual < 0n ? 'unbalanced' : 'balanced'}>{money(unitsToNumber(group.budget - group.actual), group.code)}</strong></div></>
                : <div><span>Comparison</span><strong>Currency conversion required</strong></div>}
              <small>{group.projects.size} project(s) in this currency group</small>
            </div>
          ))}
      </div>

      <section className="data-panel">
        <div className="list-toolbar"><div><strong className="section-title">Project cost performance</strong><span className="subtle-count"> · {reportRows.length} cost-code rows</span></div><span className="helper-text">Only posted transactions are included.</span></div>
        {loading ? <div className="table-empty">Loading budget and actual costs…</div>
          : queryError ? <div className="table-empty error-text">Could not load the budget-versus-actual report.</div>
          : invalidDates ? <div className="table-empty">Correct the date range to view the report.</div>
          : reportRows.length === 0 ? <div className="table-empty"><BarChart3 size={24} /><strong>No approved budgets or posted costs found</strong><span>Approve a project budget and post allocated project expenses to populate this report.</span></div>
          : <div className="table-scroll"><table className="data-table"><thead><tr><th>Project / cost code</th><th className="numeric">Approved budget</th><th className="numeric">Actual cost ({currency})</th><th className="numeric">Variance</th><th className="numeric">Used</th></tr></thead><tbody>
            {reportRows.map(row => {
              const actual = unitsToNumber(row.actualUnits)
              const budget = unitsToNumber(row.budgetUnits)
              const variance = row.varianceUnits === null ? null : unitsToNumber(row.varianceUnits)
              return <tr key={row.projectId + ':' + (row.costCodeId ?? 'unclassified')}>
                <td><strong>{row.project?.project_code ?? row.projectId}</strong><small>{row.project?.name ?? 'Project'} · {row.code ? row.code.code + ' · ' + row.code.name : 'Unclassified cost'}</small></td>
                <td className="numeric">{money(budget, row.budgetCurrency)}</td>
                <td className="numeric">{money(actual, currency)}</td>
                <td className="numeric">{variance === null ? '—' : <span className={variance < 0 ? 'unbalanced' : 'balanced'}>{money(variance, row.budgetCurrency)}</span>}</td>
                <td className="numeric">{row.utilisation === null ? '—' : row.utilisation.toFixed(1) + '%'}</td>
              </tr>
            })}
          </tbody></table></div>}
      </section>
      <p className="page-footnote"><TrendingUp size={13} /> Positive variance means budget remaining. Negative variance means actual cost has exceeded the approved budget. Reversals reduce actual cost through their signed ledger entries.</p>
    </div>
  )
}
