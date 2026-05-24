import { render } from 'ink'
import React from 'react'

import { App } from './App.js'
import { config } from './api.js'

if (!config.adminSecret) {
  console.error(
    '\nTernpike admin TUI:\n' +
      '  ADMIN_SECRET is not set.\n' +
      '  Either export it in your shell or create scripts/admin/.env:\n' +
      '    TERNPIKE_API=http://localhost:4000\n' +
      '    ADMIN_SECRET=<the secret you set on the server>\n',
  )
  process.exit(1)
}

render(<App />)
