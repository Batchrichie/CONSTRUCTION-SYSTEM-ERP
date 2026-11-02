import { Navigate, useLocation } from 'react-router-dom'
import { ArrowRight, Construction, ListChecks } from 'lucide-react'
import { modules } from '../modules/moduleRegistry'

export default function ModulePage() {
  const { pathname } = useLocation()
  const definition = modules.find((item) => item.path === pathname)
  if (!definition) return <Navigate to="/not-found" replace />
  const Icon = definition.icon

  return (
    <div className="page-content">
      <div className="module-heading">
        <div className="module-title-icon"><Icon size={22} /></div>
        <div><p className="eyebrow">{definition.section}</p><h1>{definition.label}</h1><p className="page-subtitle">{definition.description}</p></div>
      </div>
      <section className="module-status-panel">
        <div className="module-status-top"><span className="module-status-icon"><Construction size={19} /></span><span className="status-pill">Planned module</span></div>
        <h2>This workspace is being built</h2>
        <p>The module structure is in place. Its workflows, permissions and database connections will be implemented in planned development stages.</p>
        <div className="module-divider" />
        <h3><ListChecks size={16} /> Planned capabilities</h3>
        <ul className="capability-list">{definition.plannedCapabilities.map((capability) => <li key={capability}><span className="capability-check">✓</span>{capability}</li>)}</ul>
      </section>
      <div className="build-notice"><div className="notice-mark">i</div><div><strong>No live records yet</strong><p>This page does not create or display operational records. Database-backed functionality will be enabled after the relevant module is implemented and tested.</p></div></div>
      <a className="module-back-link" href="/">Return to overview <ArrowRight size={15} /></a>
    </div>
  )
}
