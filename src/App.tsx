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
export default function App(){
 const {user,company,loading,configurationMissing}=useAuth()
 if(loading)return <main className="auth-screen"><div className="loading-card">Loading secure workspace…</div></main>
 if(configurationMissing||!user)return <AuthPage/>
 if(!company)return <CompanySetupPage/>
 return <Routes><Route element={<AppLayout/>}><Route index element={<DashboardPage/>}/><Route path="projects" element={<ModulePage/>}/><Route path="customers-suppliers" element={<PartiesPage/>}/><Route path="estimates-boq" element={<EstimatesPage/>}/><Route path="sales-invoicing" element={<ModulePage/>}/><Route path="accounting" element={<ModulePage/>}/><Route path="procurement" element={<ModulePage/>}/><Route path="site-operations" element={<ModulePage/>}/><Route path="people" element={<ModulePage/>}/><Route path="reports" element={<ModulePage/>}/><Route path="settings" element={<ModulePage/>}/><Route path="not-found" element={<NotFoundPage/>}/><Route path="*" element={<Navigate to="/not-found" replace/>}/></Route></Routes>
}
