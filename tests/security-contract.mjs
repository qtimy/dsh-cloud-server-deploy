import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const read = (file) => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')
const install = read('install.sh')
const update = read('scripts/update.sh')
const verify = read('scripts/verify.sh')
const letsEncrypt = read('scripts/setup-letsencrypt.sh')
const example = read('deploy.conf.example')

// The deployer must not know the DSH credential path or provider-key variable
// convention. This makes credential preservation an absence-of-access property,
// not a promise implemented by copying or rewriting secrets.
const deployScripts = [
  ['install.sh', install],
  ['scripts/update.sh', update],
  ['scripts/verify.sh', verify],
  ['scripts/setup-letsencrypt.sh', letsEncrypt],
]
for (const [name, script] of deployScripts) {
  assert.doesNotMatch(script, /\.credentials\.yaml|CRED_FILE|_API_KEY/, `${name} crossed the credential boundary`)
  assert.doesNotMatch(
    script,
    /\b(?:cp|tar|rsync|find|grep|chown|chmod)\b[^\n]*["']\$\{DSH_HOME_TARGET\}["'](?:\s|$)/,
    `${name} traverses the whole DSH home`,
  )
}

assert.doesNotMatch(install, /source\s+["']?\$\{?CONFIG_FILE/, 'install.sh must not source deploy.conf')
const executableInstall = install.split(/\r?\n/)
  .filter((line) => !line.trimStart().startsWith('#'))
  .join('\n')
assert.doesNotMatch(executableInstall, /(?:^|[\/"'])\.env(?:["'\s]|$)/m, 'install.sh must not open a legacy .env')
assert.match(install, /SECURITY BOUNDARY: deploy\.conf contains deployment settings only/)
assert.match(update, /CREDENTIAL SAFETY BOUNDARY:/)

const allowedSettings = new Set([
  'DSH_VERSION',
  'PUBLIC_SETTINGS_OVER_BASIC_AUTH',
  'DSH_PORT',
  'DSH_USER',
  'DEPLOY_DIR',
  'TRUSTED_HOST',
  'BASIC_AUTH_USER',
  'BASIC_AUTH_PASSWORD',
  'SSL_CERT_PATH',
  'SSL_KEY_PATH',
])
const loadedSettings = [...install.matchAll(/read_deploy_setting ([A-Z][A-Z0-9_]*) /g)]
  .map((match) => match[1])
assert.deepEqual(new Set(loadedSettings), allowedSettings, 'deployment setting allowlist changed')

const exampleSettings = example.split(/\r?\n/)
  .filter((line) => /^[A-Z][A-Z0-9_]*=/.test(line))
  .map((line) => line.slice(0, line.indexOf('=')))
assert.ok(exampleSettings.every((name) => allowedSettings.has(name)), 'deploy.conf.example contains a non-deployment setting')

const modeCheck = install.indexOf('INSTALL_MODE=upgrade')
const firstMutation = install.indexOf('echo "===== 1/7 system dependencies ====="')
assert.ok(modeCheck > 0 && modeCheck < firstMutation, 'install mode must be detected before installation starts')
assert.match(install, /INSTALL_MODE=clean/)
assert.match(install, /install -d -o "\$\{DSH_USER\}"[\s\S]*"\$\{DSH_HOME_TARGET\}\/profiles"/)

assert.doesNotMatch(update, /\b(?:cp|chown|chmod|find|grep|tar|rsync)\b[^\n]*(?:-R|-a)[^\n]*DSH_HOME_TARGET/, 'rollback must not recursively traverse the DSH home')
assert.match(verify, /if ! sudo -u "\$\{DSH_USER\}" -H dsh --profile web --dump-config[\s\S]*cat "\$\{config_errors\}" >&2/)

console.log('credential boundary and clean-install regression checks passed')
