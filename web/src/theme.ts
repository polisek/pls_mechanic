import { createTheme, type MantineColorsTuple } from '@mantine/core'

const amber: MantineColorsTuple = [
  '#fff6e3',
  '#ffebc6',
  '#ffd58c',
  '#ffbf4f',
  '#ffac1f',
  '#ffa106',
  '#ff9b00',
  '#e38800',
  '#ca7800',
  '#af6600',
]

const dark: MantineColorsTuple = [
  '#d5d8dd',
  '#b3b8c0',
  '#8d939d',
  '#646b76',
  '#3d424b',
  '#2c3037',
  '#20232a',
  '#181a1f',
  '#121418',
  '#0c0d10',
]

export const theme = createTheme({
  primaryColor: 'amber',
  primaryShade: 6,
  colors: { amber, dark },
  white: '#eceef1',
  black: '#0c0d10',
  fontFamily: "'Barlow', 'Segoe UI', Roboto, sans-serif",
  fontFamilyMonospace: "'JetBrains Mono', Consolas, monospace",
  headings: { fontFamily: "'Barlow Condensed', 'Barlow', sans-serif", fontWeight: '700' },
  defaultRadius: 'sm',
  cursorType: 'pointer',
  focusRing: 'never',
  components: {
    Tooltip: {
      defaultProps: {
        withArrow: true,
        openDelay: 120,
        transitionProps: { transition: 'fade', duration: 120 },
        color: 'dark.7',
        multiline: true,
        maw: 320,
        zIndex: 400,
      },
    },
    Checkbox: { defaultProps: { color: 'amber.6', iconColor: 'dark.9', radius: 'xs' } },
    Switch: { defaultProps: { color: 'amber.6', size: 'md' } },
  },
})
