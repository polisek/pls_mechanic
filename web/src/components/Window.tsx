import type { CSSProperties, ReactNode } from 'react'
import { IconX } from '@tabler/icons-react'
import { useUi } from '../lib/ui'

interface WindowProps {
  icon: ReactNode
  title: ReactNode
  subtitle?: ReactNode
  headerRight?: ReactNode
  footer?: ReactNode
  onClose: () => void
  className?: string
  style?: CSSProperties
  /** false = no dimmed backdrop (tuning keeps the car visible) */
  backdrop?: boolean
  children: ReactNode
}

export function Window({
  icon,
  title,
  subtitle,
  headerRight,
  footer,
  onClose,
  className,
  style,
  backdrop = true,
  children,
}: WindowProps) {
  const { t } = useUi()
  return (
    <div className={`layer${backdrop ? ' backdrop' : ''}`}>
      <section className={`win${className ? ` ${className}` : ''}`} style={style}>
        <header className="win__head">
          <div className="win__icon">{icon}</div>
          <div className="win__titles">
            <h2 className="win__title">{title}</h2>
            {subtitle ? <div className="win__subtitle">{subtitle}</div> : null}
          </div>
          {headerRight ? <div className="win__head-right">{headerRight}</div> : null}
          <button type="button" className="win__close" onClick={onClose} title={t('ui_close', 'Close')}>
            <span className="kbd">ESC</span>
            <IconX size="1.1rem" stroke={2} />
          </button>
        </header>
        <div className="win__body">{children}</div>
        {footer ? <footer className="win__foot">{footer}</footer> : null}
      </section>
    </div>
  )
}
