import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react'
import { IconAlertTriangle, IconCircleCheck, IconInfoCircle } from '@tabler/icons-react'

export type ToastType = 'success' | 'error' | 'info'

interface Toast {
  id: number
  type: ToastType
  message: string
}

type PushToast = (type: ToastType, message: string) => void

const ToastContext = createContext<PushToast>(() => undefined)

const ICONS = {
  success: IconCircleCheck,
  error: IconAlertTriangle,
  info: IconInfoCircle,
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const nextId = useRef(1)

  const push = useCallback<PushToast>((type, message) => {
    if (!message) return
    const id = nextId.current++
    setToasts((list) => [...list.slice(-3), { id, type, message }])
    window.setTimeout(() => setToasts((list) => list.filter((toast) => toast.id !== id)), 4200)
  }, [])

  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="toast-stack">
        {toasts.map((toast) => {
          const Icon = ICONS[toast.type]
          return (
            <div key={toast.id} className={`toast toast--${toast.type}`}>
              <Icon size="1.15rem" stroke={1.8} />
              <span>{toast.message}</span>
            </div>
          )
        })}
      </div>
    </ToastContext.Provider>
  )
}

export const useToast = () => useContext(ToastContext)
