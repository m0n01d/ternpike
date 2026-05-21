// Re-export the lifecycle helper so specs can `import { teardownHarness }
// from '../teardown.js'` if that reads more naturally than '../setup.js'.

export { teardownHarness } from './setup.js'
