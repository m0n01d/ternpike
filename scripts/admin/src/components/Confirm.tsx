import { Box, Text, useInput } from 'ink'
import TextInput from 'ink-text-input'
import React, { useState } from 'react'

type Props = {
  prompt: string
  expectedAnswer?: string
  onConfirm: () => void
  onCancel: () => void
}

export const Confirm: React.FC<Props> = ({
  prompt,
  expectedAnswer,
  onConfirm,
  onCancel,
}) => {
  const [value, setValue] = useState('')

  useInput((_input, key) => {
    if (key.escape) onCancel()
    if (!expectedAnswer && (key.return || _input === 'y')) onConfirm()
    if (!expectedAnswer && _input === 'n') onCancel()
  })

  if (expectedAnswer) {
    return (
      <Box flexDirection="column">
        <Text color="yellow">{prompt}</Text>
        <Text color="gray">type "{expectedAnswer}" then Enter (Esc cancels)</Text>
        <TextInput
          value={value}
          onChange={setValue}
          onSubmit={(v) => {
            if (v === expectedAnswer) onConfirm()
            else onCancel()
          }}
        />
      </Box>
    )
  }

  return (
    <Box flexDirection="column">
      <Text color="yellow">{prompt}</Text>
      <Text color="gray">[ y ] yes  ·  [ n ] no  ·  [ Esc ] cancel</Text>
    </Box>
  )
}
