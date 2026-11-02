import { useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { ChevronDown, HardHat, Menu, X } from 'lucide-react'
import { modules } from '../modules/moduleRegistry'

const sections = ['WORKSPACE', 'FINANCE', 'OPERATIONS', 'ADMINISTRATION'] as const

export default function AppLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()
  const activeModule = modules.find((module) => module.path === location.pathname)

  return (
    <div className="app-shell">
      {sidebarOpen && <button className="sidebar-scrim" aria-label="Close navigation" onClick={() => setSidebarOpen(false)} />}
      <aside className={`sidebar ${sidebarOpen ? 'sidebar-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark"><HardHat size={21} /></div>
          <div><strong>CONSTRUCT</strong><span>PROJECT ERP</span></div>
          <button className="sidebar-close" aria-label="Close navigation" onClick={() => setSidebarOpen(false)}><X size={18} /></button>
        </div>
        <div className="company-switcher">
          <div className="company-avatar">CO</div>
          <div className="company-copy"><strong>My Company</strong><span>Single-company workspace</span></div>
          <ChevronDown size={16} />
        </div>
        {sections.map((section) => (
          <div className="nav-section" key={section}>
            <p>{section}</p>
            {modules.filter((module) => module.section === section).map(({ path, label, icon: Icon }) => (
              <NavLink end={path === '/'} to={path} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`} key={path} onClick={() => setSidebarOpen(false)}>
                <Icon size={17} strokeWidth={1.8} /><span>{label}</span>
              </NavLink>
            ))}
          </div>
        ))}
        <div className="sidebar-footer"><span className="status-dot" /> Development workspace</div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <button className="mobile-menu" aria-label="Open navigation" onClick={() => setSidebarOpen(true)}><Menu size={20} /></button>
          <div className="breadcrumb">Workspace <span>/</span> <strong>{activeModule?.label ?? 'Not found'}</strong></div>
          <div className="topbar-right"><span className="environment-tag">INITIAL BUILD</span><div className="user-avatar" aria-label="Development user">A</div></div>
        </header>
        <Outlet />
      </main>
    </div>
  )
}
