const { spawnSync } = require('node:child_process');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');
const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const flutterCommand = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

const requestedSuite = process.argv[2];
const suites = requestedSuite ? [requestedSuite] : ['frontend', 'backend', 'mobile'];

const suiteCommands = {
  frontend: {
    command: npmCommand,
    args: ['run', 'test:frontend'],
    cwd: repoRoot,
    env: { ...process.env, CI: 'true' },
  },
  backend: {
    command: npmCommand,
    args: ['--prefix', 'backend', 'test'],
    cwd: repoRoot,
    env: process.env,
  },
  mobile: {
    command: flutterCommand,
    args: ['test'],
    cwd: path.join(repoRoot, 'mobile'),
    env: process.env,
  },
};

for (const suite of suites) {
  const config = suiteCommands[suite];
  if (!config) {
    console.error(`Unknown test suite: ${suite}`);
    process.exit(1);
  }

  console.log(`\n=== Running ${suite} tests ===`);
  const result = spawnSync(config.command, config.args, {
    cwd: config.cwd,
    env: config.env,
    stdio: 'inherit',
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
