import { Link } from 'react-router-dom'

export default function NotFoundPage() {
  return <div className="page-content"><div className="not-found"><p className="eyebrow">404 · PAGE NOT FOUND</p><h1>This page is unavailable</h1><p className="page-subtitle">The address may be incorrect or the module may not exist.</p><Link className="primary-button" to="/">Return to overview</Link></div></div>
}
