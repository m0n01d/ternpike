import { Box, Text } from 'ink'
import React from 'react'

import { config } from '../api.js'

type Section = 'users' | 'dbs' | 'sharedtrips' | 'seed'

type Props = {
  section: Section
  hints: string
  status?: string
  error?: string | null
  children: React.ReactNode
}

const SECTIONS: Array<{ key: Section; label: string }> = [
  { key: 'users', label: 'Users' },
  { key: 'dbs', label: 'Databases' },
  { key: 'sharedtrips', label: 'SharedTrips' },
  { key: 'seed', label: 'Seed' },
]

export const Layout: React.FC<Props> = ({
  section,
  hints,
  status,
  error,
  children,
}) => (
  <Box flexDirection="column" width="100%">
    <Box
      borderStyle="round"
      borderColor="cyan"
      paddingX={1}
      justifyContent="space-between"
    >
      <Text>
        <Text color="cyan" bold>
          ternpike-admin
        </Text>{' '}
        <Text color="gray">·</Text> {config.apiUrl}
      </Text>
      <Text color={error ? 'red' : 'green'}>
        {error ? `error: ${error}` : status || 'ready'}
      </Text>
    </Box>
    <Box>
      <Box
        flexDirection="column"
        borderStyle="single"
        borderColor="gray"
        paddingX={1}
        width={16}
      >
        {SECTIONS.map((s) => (
          <Text key={s.key} color={s.key === section ? 'cyan' : 'white'}>
            {s.key === section ? '› ' : '  '}
            {s.label}
          </Text>
        ))}
      </Box>
      <Box flexGrow={1} flexDirection="column" paddingX={1} paddingY={0}>
        {children}
      </Box>
    </Box>
    <Box borderStyle="single" borderColor="gray" paddingX={1}>
      <Text color="gray">{hints}</Text>
    </Box>
  </Box>
)
