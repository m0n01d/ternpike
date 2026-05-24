import pc from 'picocolors'

export const formatBytes = (n: number | null): string => {
  if (n === null || n === undefined) return '—'
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`
}

export const tierColor = (tier: string): string => {
  if (tier === 'osprey') return pc.green(tier)
  if (tier === 'trailblazer') return pc.yellow(tier)
  return pc.gray(tier)
}

export const tierBadge = (tier: string): string => {
  if (tier === 'osprey') return pc.bgGreen(pc.black(' OSPREY '))
  if (tier === 'trailblazer') return pc.bgYellow(pc.black(' TRAIL '))
  return pc.inverse(pc.gray(' TERN '))
}

export const truncate = (s: string, n: number): string => {
  if (s.length <= n) return s
  return s.slice(0, n - 1) + '…'
}
