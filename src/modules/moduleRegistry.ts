import type { LucideIcon } from 'lucide-react'
import {
  BarChart3, Building2, ClipboardList, FileText, HardHat, LayoutDashboard,
  Package, Settings, Users, Wallet,
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
  { path: '/procurement', label: 'Procurement', section: 'OPERATIONS', icon: Package, description: 'Control purchasing from requisition through supplier receipt and billing.', plannedCapabilities: ['Purchase requisitions and approvals', 'Supplier quotations and purchase orders', 'Goods received notes and supplier bills'] },
  { path: '/site-operations', label: 'Site Operations', section: 'OPERATIONS', icon: HardHat, description: 'Capture site progress, labour, equipment and material usage.', plannedCapabilities: ['Daily site reports and progress evidence', 'Labour and equipment utilisation', 'Material requests and project issues'] },
  { path: '/people', label: 'People', section: 'ADMINISTRATION', icon: Users, description: 'Manage employees, payroll and access to the system.', plannedCapabilities: ['Employee records and contracts', 'Payroll runs and statutory deductions', 'User roles and permissions'] },
  { path: '/reports', label: 'Reports', section: 'ADMINISTRATION', icon: BarChart3, description: 'Review management, project and financial performance reports.', plannedCapabilities: ['Project profitability and cost reports', 'Financial statements and reconciliations', 'Operational and management dashboards'] },
  { path: '/settings', label: 'Settings', section: 'ADMINISTRATION', icon: Settings, description: 'Configure company information, numbering, preferences and controls.', plannedCapabilities: ['Company profile and financial year', 'Document numbering and approval settings', 'Tax configuration and system preferences'] },
]

export const moduleByPath = Object.fromEntries(modules.map((module) => [module.path, module]))
