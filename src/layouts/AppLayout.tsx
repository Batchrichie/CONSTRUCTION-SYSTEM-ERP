import { useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { ChevronDown, HardHat, Menu, X, LogOut, Users } from 'lucide-react'
import { modules } from '../modules/moduleRegistry'
import { useAuth } from '../contexts/AuthContext'
const sections=['WORKSPACE','COMMERCIAL','FINANCE','OPERATIONS','ADMINISTRATION'] as const
export default function AppLayout(){
 const [sidebarOpen,setSidebarOpen]=useState(false);const location=useLocation();const {company,user,signOut}=useAuth()
 const active=modules.find(m=>m.path===location.pathname);const partyActive=location.pathname==='/customers-suppliers'
 return <div className="app-shell">{sidebarOpen&&<button className="sidebar-scrim" aria-label="Close navigation" onClick={()=>setSidebarOpen(false)}/>}<aside className={'sidebar '+(sidebarOpen?'sidebar-open':'')}>
  <div className="brand"><div className="brand-mark"><HardHat size={21}/></div><div><strong>CONSTRUCT</strong><span>PROJECT ERP</span></div><button className="sidebar-close" aria-label="Close navigation" onClick={()=>setSidebarOpen(false)}><X size={18}/></button></div>
  <div className="company-switcher"><div className="company-avatar">CO</div><div className="company-copy"><strong>{company?.display_name??'Company'}</strong><span>{company?.base_currency??'GHS'} workspace</span></div><ChevronDown size={16}/></div>
  {sections.map(section=><div className="nav-section" key={section}><p>{section}</p>{section==='COMMERCIAL'&&<NavLink to="/customers-suppliers" className={'nav-item '+(partyActive?'active':'')} onClick={()=>setSidebarOpen(false)}><Users size={17}/><span>Customers & Suppliers</span></NavLink>}{modules.filter(m=>m.section===section).map(({path,label,icon:Icon})=><NavLink end={path==='/'} to={path} className={({isActive})=>'nav-item '+(isActive?'active':'')} key={path} onClick={()=>setSidebarOpen(false)}><Icon size={17}/><span>{label}</span></NavLink>)}</div>)}
  <div className="sidebar-footer"><span className="status-dot"/> Development workspace</div></aside>
  <main className="main-area"><header className="topbar"><button className="mobile-menu" aria-label="Open navigation" onClick={()=>setSidebarOpen(true)}><Menu size={20}/></button><div className="breadcrumb">Workspace <span>/</span> <strong>{partyActive?'Customers & Suppliers':active?.label??'Not found'}</strong></div><div className="topbar-right"><span className="environment-tag">DEVELOPMENT</span><div className="user-avatar" title={user?.email??''}>{user?.email?.slice(0,1).toUpperCase()??'U'}</div><button className="signout-button" onClick={()=>void signOut()} aria-label="Sign out"><LogOut size={16}/></button></div></header><Outlet/></main></div>
}
