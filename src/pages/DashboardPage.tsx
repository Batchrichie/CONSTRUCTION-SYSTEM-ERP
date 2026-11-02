import { Activity, Building2, ClipboardList, Wallet } from 'lucide-react'
import { Link } from 'react-router-dom'

const metrics = [
  { label: 'Active projects', value: '—', note: 'Projects in progress', icon: Building2 },
  { label: 'Receivables', value: 'GHS —', note: 'Outstanding customer balances', icon: Wallet },
  { label: 'Pending approvals', value: '—', note: 'Items awaiting review', icon: ClipboardList },
  { label: 'Site activity', value: '—', note: 'Updates requiring attention', icon: Activity },
]

export default function DashboardPage() {
  return (
    <div className="page-content">
      <div className="welcome-row">
        <div><p className="eyebrow">YOUR WORKSPACE</p><h1>Good morning</h1><p className="page-subtitle">Your construction business at a glance.</p></div>
        <Link className="primary-button" to="/projects">View projects <span>↗</span></Link>
      </div>
      <section className="metric-grid" aria-label="Business overview">
        {metrics.map(({ label, value, note, icon: Icon }) => (
          <article className="metric-card" key={label}>
            <div className="metric-top"><span>{label}</span><div className="metric-icon"><Icon size={18} /></div></div>
            <strong className="metric-value">{value}</strong><span className="metric-note">{note}</span>
          </article>
        ))}
      </section>
      <section className="content-grid">
        <article className="panel project-panel">
          <div className="panel-heading"><div><h2>Project portfolio</h2><p>Your projects will appear here</p></div><Link className="text-button" to="/projects">All projects <span>→</span></Link></div>
          <div className="empty-state"><div className="empty-icon"><Building2 size={25} /></div><strong>Ready for your first project</strong><p>Set up a project to start tracking contracts, budgets, costs and delivery progress.</p><Link className="outline-button" to="/projects">Explore project management</Link></div>
        </article>
        <article className="panel activity-panel">
          <div className="panel-heading"><div><h2>Recent activity</h2><p>Latest updates across your business</p></div></div>
          <div className="empty-activity"><div className="activity-line" /><div><strong>No activity yet</strong><p>Actions and approvals will be recorded here.</p></div></div>
          <div className="activity-footnote">Activity history will be available once modules are connected.</div>
        </article>
      </section>
      <div className="build-notice"><div className="notice-mark">i</div><div><strong>Development workspace</strong><p>Dashboard values are placeholders until the database, accounting controls and operational modules are implemented.</p></div></div>
    </div>
  )
}
