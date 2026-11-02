import { useState } from 'react'
import {
  Activity, BarChart3, Building2, ChevronDown, ClipboardList, FileText,
  HardHat, LayoutDashboard, Menu, Package, Settings, Users, Wallet,
} from 'lucide-react'

const navigation = [
  { label: 'Overview', icon: LayoutDashboard, section: 'WORKSPACE' },
  { label: 'Projects', icon: Building2, section: 'WORKSPACE' },
  { label: 'Estimates & BOQ', icon: ClipboardList, section: 'WORKSPACE' },
  { label: 'Sales & Invoicing', icon: FileText, section: 'FINANCE' },
  { label: 'Accounting', icon: Wallet, section: 'FINANCE' },
  { label: 'Procurement', icon: Package, section: 'OPERATIONS' },
  { label: 'Site Operations', icon: HardHat, section: 'OPERATIONS' },
  { label: 'People', icon: Users, section: 'ADMINISTRATION' },
  { label: 'Reports', icon: BarChart3, section: 'ADMINISTRATION' },
  { label: 'Settings', icon: Settings, section: 'ADMINISTRATION' },
]

const metrics = [
  { label: 'Active projects', value: '—', note: 'Projects in progress', icon: Building2 },
  { label: 'Receivables', value: 'GHS —', note: 'Outstanding customer balances', icon: Wallet },
  { label: 'Pending approvals', value: '—', note: 'Items awaiting review', icon: ClipboardList },
  { label: 'Site activity', value: '—', note: 'Updates requiring attention', icon: Activity },
]

export default function App() {
  const [active, setActive] = useState('Overview')
  const [sidebarOpen, setSidebarOpen] = useState(false)

  return (
    <div className="app-shell">
      <aside className={`sidebar ${sidebarOpen ? 'sidebar-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark"><HardHat size={21} /></div>
          <div><strong>CONSTRUCT</strong><span>PROJECT ERP</span></div>
        </div>
        <div className="company-switcher">
          <div className="company-avatar">CO</div>
          <div className="company-copy"><strong>My Company</strong><span>Single-company workspace</span></div>
          <ChevronDown size={16} />
        </div>
        {['WORKSPACE', 'FINANCE', 'OPERATIONS', 'ADMINISTRATION'].map((section) => (
          <div className="nav-section" key={section}>
            <p>{section}</p>
            {navigation.filter((item) => item.section === section).map(({ label, icon: Icon }) => (
              <button className={`nav-item ${active === label ? 'active' : ''}`} key={label} onClick={() => { setActive(label); setSidebarOpen(false) }}>
                <Icon size={17} strokeWidth={1.8} /><span>{label}</span>
              </button>
            ))}
          </div>
        ))}
        <div className="sidebar-footer"><span className="status-dot" /> Development workspace</div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <button className="mobile-menu" aria-label="Toggle navigation" onClick={() => setSidebarOpen(!sidebarOpen)}><Menu size={20} /></button>
          <div className="breadcrumb">Workspace <span>/</span> <strong>{active}</strong></div>
          <div className="topbar-right"><span className="environment-tag">INITIAL BUILD</span><div className="user-avatar">A</div></div>
        </header>

        <div className="page-content">
          <div className="welcome-row">
            <div>
              <p className="eyebrow">MONDAY, YOUR WORKSPACE</p>
              <h1>{active === 'Overview' ? 'Good morning' : active}</h1>
              <p className="page-subtitle">{active === 'Overview' ? 'Your construction business at a glance.' : `The ${active.toLowerCase()} workspace is being prepared.`}</p>
            </div>
            <button className="primary-button" onClick={() => setActive('Projects')}>View projects <span>↗</span></button>
          </div>

          <section className="metric-grid" aria-label="Business overview">
            {metrics.map(({ label, value, note, icon: Icon }) => (
              <article className="metric-card" key={label}>
                <div className="metric-top"><span>{label}</span><div className="metric-icon"><Icon size={18} /></div></div>
                <strong className="metric-value">{value}</strong>
                <span className="metric-note">{note}</span>
              </article>
            ))}
          </section>

          <section className="content-grid">
            <article className="panel project-panel">
              <div className="panel-heading"><div><h2>Project portfolio</h2><p>Your projects will appear here</p></div><button className="text-button" onClick={() => setActive('Projects')}>All projects <span>→</span></button></div>
              <div className="empty-state"><div className="empty-icon"><Building2 size={25} /></div><strong>Ready for your first project</strong><p>Set up a project to start tracking contracts, budgets, costs and delivery progress.</p><button className="outline-button" onClick={() => setActive('Projects')}>Explore project management</button></div>
            </article>
            <article className="panel activity-panel">
              <div className="panel-heading"><div><h2>Recent activity</h2><p>Latest updates across your business</p></div></div>
              <div className="empty-activity"><div className="activity-line" /><div><strong>No activity yet</strong><p>Actions and approvals will be recorded here.</p></div></div>
              <div className="activity-footnote">Activity history will be available once modules are connected.</div>
            </article>
          </section>

          <div className="build-notice"><div className="notice-mark">i</div><div><strong>Foundation stage</strong><p>This is the initial application shell. Live financial figures and workflows will appear after the database and accounting controls are implemented.</p></div></div>
        </div>
      </main>
    </div>
  )
}
