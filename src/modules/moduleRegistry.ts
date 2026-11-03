import type { LucideIcon } from 'lucide-react'
import {
  BarChart3, Building2, ClipboardList, FileText, HardHat, LayoutDashboard,
  Package, Receipt, Settings, Tags, Users, Wallet,
} from 'lucide-react'

export type NavigationSection = 'WORKSPACE' | 'COMMERCIAL' | 'FINANCE' | 'OPERATIONS' | 'ADMINISTRATION'

export interface ModuleDefinition {
  path: string
  label: string
  section: NavigationSection
  icon: LucideIcon
  description: string
  plannedCapabilities: string[]
}

export const modules: ModuleDefinition[] = [
  { path: '/', label: 'Overview', section: 'WORKSPACE', icon: LayoutDashboard, description: 'A consolidated view of projects, finance and operational activity.', plannedCapabilities: ['Project and financial KPIs', 'Approvals requiring attention', 'Recent business activity'] },
  { path: '/projects', label: 'Projects', section: 'WORKSPACE', icon: Building2, description: 'Manage construction projects, contracts, milestones and variations.', plannedCapabilities: ['Project register and status tracking', 'Client contracts and contract variations', 'Milestones, progress and project documents'] },
  { path: '/estimates-boq', label: 'Estimates & BOQ', section: 'WORKSPACE', icon: ClipboardList, description: 'Prepare estimates, bills of quantities and project budgets.', plannedCapabilities: ['Estimate versions and approvals', 'BOQ items, quantities and rates', 'Budget baselines and cost comparisons'] },
  { path: '/sales-invoicing', label: 'Sales & Invoicing', section: 'FINANCE', icon: FileText, description: 'Manage quotations, customer invoices, receipts and credit notes.', plannedCapabilities: ['Customer quotations and invoices', 'Progress claims and retention', 'Receipts, credit notes and customer balances'] },
  { path: '/accounting', label: 'Accounting', section: 'FINANCE', icon: Wallet, description: 'Maintain the accounting foundation and produce controlled financial reports.', plannedCapabilities: ['Chart of accounts and accounting periods', 'Double-entry journals and general ledger', 'Trial balance and financial statements'] },
  { path: '/expense-allocation', label: 'Expense Allocation', section: 'FINANCE', icon: Receipt, description: 'Record expenses, allocate project and overhead costs, and post balanced journals.', plannedCapabilities: ['Expense entry with project and overhead splits', 'Complete cost allocation before posting', 'Draft journal review and controlled posting'] },
  { path: '/procurement', label: 'Procurement', section: 'OPERATIONS', icon: Package, description: 'Control purchasing from requisition through supplier receipt and billing.', plannedCapabilities: ['Purchase requisitions and approvals', 'Supplier quotations and purchase orders', 'Goods received notes and supplier bills'] },
  { path: '/project-costs', label: 'Cost Codes & Centres', section: 'OPERATIONS', icon: Tags, description: 'Configure the cost classifications used by project budgets and actual cost allocations.', plannedCapabilities: ['Company-scoped cost code hierarchy', 'Overhead, department, site and shared cost centres', 'Controlled activation and deactivation of cost classifications'] },
  { path: '/project-budgets', label: 'Project Budgets', section: 'OPERATIONS', icon: Wallet, description: 'Prepare, revise and approve project cost budgets.', plannedCapabilities: ['Cost-code budget preparation', 'Controlled submission and approval', 'Immutable approved revisions and approval history'] },
  { path: '/site-operations', label: 'Site Operations', section: 'OPERATIONS', icon: HardHat, description: 'Capture site progress, labour, equipment and material usage.', plannedCapabilities: ['Daily site reports and progress evidence', 'Labour and equipment utilisation', 'Material requests and project issues'] },
  { path: '/people', label: 'People', section: 'ADMINISTRATION', icon: Users, description: 'Manage employees, payroll and access to the system.', plannedCapabilities: ['Employee records and contracts', 'Payroll runs and statutory deductions', 'User roles and permissions'] },
  { path: '/reports', label: 'Reports', section: 'ADMINISTRATION', icon: BarChart3, description: 'Review management, project and financial performance.', plannedCapabilities: ['Project profitability and cost reports', 'Financial statements and reconciliations', 'Operational and management dashboards'] },
  { path: '/settings', label: 'Settings', section: 'ADMINISTRATION', icon: Settings, description: 'Configure company information, numbering, preferences and controls.', plannedCapabilities: ['Company profile and financial year', 'Document numbering and approval settings', 'Tax configuration and system preferences'] },
]

export const moduleByPath = Object.fromEntries(modules.map((module) => [module.path, module]))
