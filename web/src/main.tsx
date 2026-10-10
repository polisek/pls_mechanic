import React from 'react'
import ReactDOM from 'react-dom/client'

// Fonts – only latin + latin-ext (Czech diacritics) subsets are bundled
import '@fontsource/barlow/latin-400.css'
import '@fontsource/barlow/latin-ext-400.css'
import '@fontsource/barlow/latin-500.css'
import '@fontsource/barlow/latin-ext-500.css'
import '@fontsource/barlow/latin-600.css'
import '@fontsource/barlow/latin-ext-600.css'
import '@fontsource/barlow/latin-700.css'
import '@fontsource/barlow/latin-ext-700.css'
import '@fontsource/barlow-condensed/latin-600.css'
import '@fontsource/barlow-condensed/latin-ext-600.css'
import '@fontsource/barlow-condensed/latin-700.css'
import '@fontsource/barlow-condensed/latin-ext-700.css'
import '@fontsource/jetbrains-mono/latin-500.css'
import '@fontsource/jetbrains-mono/latin-ext-500.css'
import '@fontsource/jetbrains-mono/latin-700.css'
import '@fontsource/jetbrains-mono/latin-ext-700.css'

import '@mantine/core/styles.css'
import './styles/global.css'

import App from './App'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
