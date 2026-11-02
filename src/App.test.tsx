import { render,screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient,QueryClientProvider } from '@tanstack/react-query'
import { describe,expect,it } from 'vitest'
import App from './App'
import { AuthProvider } from './contexts/AuthContext'
function renderApp(){const queryClient=new QueryClient();return render(<QueryClientProvider client={queryClient}><MemoryRouter><AuthProvider><App/></AuthProvider></MemoryRouter></QueryClientProvider>)}
describe('ERP application access',()=>{
 it('requires Supabase configuration before sign in',()=>{renderApp();expect(screen.getByRole('heading',{name:'Welcome back'})).toBeInTheDocument();expect(screen.getByText(/Supabase is not configured/i)).toBeInTheDocument()})
})
