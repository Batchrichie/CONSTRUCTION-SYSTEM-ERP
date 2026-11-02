import { Moon, Sun } from 'lucide-react'
import { useTheme } from '../contexts/ThemeContext'

export default function ThemeToggle() {
  const { theme, setTheme } = useTheme()

  return (
    <div className="theme-toggle" role="group" aria-label="Colour theme">
      <button
        type="button"
        className={theme === 'light' ? 'theme-option selected' : 'theme-option'}
        onClick={() => setTheme('light')}
        aria-label="Use light mode"
        aria-pressed={theme === 'light'}
        title="Light mode"
      >
        <Sun size={15} />
        <span>Light</span>
      </button>
      <button
        type="button"
        className={theme === 'dark' ? 'theme-option selected' : 'theme-option'}
        onClick={() => setTheme('dark')}
        aria-label="Use dark mode"
        aria-pressed={theme === 'dark'}
        title="Dark mode"
      >
        <Moon size={15} />
        <span>Dark</span>
      </button>
    </div>
  )
}
