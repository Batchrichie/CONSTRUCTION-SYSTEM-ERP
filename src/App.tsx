import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './contexts/AuthContext'
import AppLayout from './layouts/AppLayout'
import DashboardPage from './pages/DashboardPage'
import ModulePage from './pages/ModulePage'
import NotFoundPage from './pages/NotFoundPage'
import AuthPage from './pages/AuthPage'
import CompanySetupPage from './pages/CompanySetupPage'
import PartiesPage from './pages/PartiesPage'
import EstimatesPage from './pages/EstimatesPage'
import ProjectsPage from './pages/ProjectsPage'
import ProjectCostSetupPage from './pages/ProjectCostSetupPage'

export default function App() {
  const {
    user,
    company,
    loading,
    companyLoading,
    companyError,
    refreshCompany,
    configurationMissing,
  } = useAuth()

  if (loading) {
    return <main className="auth-screen"><div className="loading-card">Loading secure workspace…</div></main>
  }

  if (configurationMissing || !user) return <AuthPage />

  if (companyLoading) {
    return <main className="auth-screen"><div className="loading-card">Loading company workspace…</div></main>
  }

  if (companyError) {
    return (
      <main className="auth-screen">
        <section className="auth-card" role="alert">
          <p className="eyebrow">WORKSPACE CONNECTION</p>
          <h1>We couldn't load your company</h1>
          <p className="auth-intro">
            Your sign-in is still active, but the company workspace could not be retrieved.
            Check your connection and try again. No new company has been created.
          </p>
          <div className="form-alert error">{companyError}</div>
          <button
            className="primary-button auth-submit"
            onClick={() => void refreshCompany().catch(() => undefined)}
          >
            Retry company connection
          </button>
        </section>
      </main>
    )
  }

  if (!company) return <CompanySetupPage />

  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route index element={<DashboardPage />} />
        <Route path="projects" element={<ProjectsPage />} />
        <Route path="project-costs" element={<ProjectCostSetupPage />} />
        <Route path="customers-suppliers" element={<PartiesPage />} />
        <Route path="estimates-boq" element={<EstimatesPage />} />
        <Route path="sales-invoicing" element={<ModulePage />} />
        <Route path="accounting" element={<ModulePage />} />
        <Route path="procurement" element={<ModulePage />} />
        <Route path="site-operations" element={<ModulePage />} />
        <Route path="people" element={<ModulePage />} />
        <Route path="reports" element={<ModulePage />} />
        <Route path="settings" element={<ModulePage />} />
        <Route path="not-found" element={<NotFoundPage />} />
        <Route path="*" element={<Navigate to="/not-found" replace />} />
      </Route>
    </Routes>
  )
}
