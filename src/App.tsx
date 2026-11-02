import { Route, Routes } from 'react-router-dom'
import AppLayout from './layouts/AppLayout'
import DashboardPage from './pages/DashboardPage'
import ModulePage from './pages/ModulePage'
import NotFoundPage from './pages/NotFoundPage'

export default function App() {
  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route index element={<DashboardPage />} />
        <Route path="projects" element={<ModulePage />} />
        <Route path="estimates-boq" element={<ModulePage />} />
        <Route path="sales-invoicing" element={<ModulePage />} />
        <Route path="accounting" element={<ModulePage />} />
        <Route path="procurement" element={<ModulePage />} />
        <Route path="site-operations" element={<ModulePage />} />
        <Route path="people" element={<ModulePage />} />
        <Route path="reports" element={<ModulePage />} />
        <Route path="settings" element={<ModulePage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
