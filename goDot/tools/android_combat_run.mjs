// Start capture before launch and sample presented frames immediately at READY.
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const args = Object.fromEntries(process.argv.slice(2).map(value => value.replace(/^--/, '').split('=')));
const adb = args.adb || '/Users/7700k/Library/Android/sdk/platform-tools/adb';
const serial = args.serial || 'EAWOKJGY6DIRIRT4';
const packageName = args.package || 'com.teamelo.dungeonchasers.godot';
const prefix = args.output || 'reports/android-combat-auto';
const seconds = Number(args.seconds || 15);
const timeout = Number(args.timeout || 180);
if (!Number.isFinite(seconds) || seconds < 1 || !Number.isFinite(timeout) || timeout <= seconds) throw new Error('Invalid capture duration');
const runAdb = values => execFileSync(adb, ['-s', serial, ...values], { encoding: 'utf8', timeout: 20000 });
const shell = (...values) => runAdb(['shell', ...values]);
const state = () => ({
  battery: shell('dumpsys', 'battery'), thermal: shell('dumpsys', 'thermalservice'),
  focus: shell('dumpsys', 'window').split('\n').filter(line => line.includes('mCurrentFocus=')).join('\n'),
  power: shell('dumpsys', 'power').split('\n').filter(line => line.includes('mWakefulness=')).join('\n'),
});
const start = new Date().toISOString();
runAdb(['shell', 'am', 'force-stop', packageName]);
const stateStart = state();
const logPath = `${prefix}-log.json`;
const framePath = `${prefix}.json`;
const children = new Set();
const childExit = child => new Promise(resolve => {
  children.add(child);
  child.once('error', error => { children.delete(child); resolve({ code: null, error: error.message }); });
  child.once('close', (code, signal) => { children.delete(child); resolve({ code, signal }); });
});
let probe = null;
let probeExit = null;
let ready = null;
let pending = '';
let failed = '';
let screenshotTimer;
let screenshotError = '';
const timer = setTimeout(() => {
  failed = 'Capture timed out';
  for (const child of children) child.kill();
}, timeout * 1000);
const logger = spawn(process.execPath, [fileURLToPath(new URL('./android_combat_log.mjs', import.meta.url)),
  `--adb=${adb}`, `--serial=${serial}`, `--output=${logPath}`, `--timeout=${timeout}`], { stdio: ['ignore', 'pipe', 'inherit'] });
const loggerExit = childExit(logger);
logger.stdout.setEncoding('utf8');
logger.stdout.on('data', data => {
  process.stdout.write(data);
  pending += data;
  const lines = pending.split('\n');
  pending = lines.pop();
  for (const line of lines) {
    if (!line.startsWith('COMBAT_STRESS_READY ') || ready) continue;
    try { ready = JSON.parse(line.slice('COMBAT_STRESS_READY '.length)); }
    catch { continue; }
    probe = spawn(process.execPath, [fileURLToPath(new URL('./android_frame_probe.mjs', import.meta.url)),
      `--adb=${adb}`, `--serial=${serial}`, `--package=${packageName}`, `--seconds=${seconds}`, `--output=${framePath}`],
    { stdio: ['ignore', 'inherit', 'inherit'] });
    probeExit = childExit(probe);
    if (args.screenshot) screenshotTimer = setTimeout(() => {
      try { writeFileSync(args.screenshot, execFileSync(adb, ['-s', serial, 'exec-out', 'screencap', '-p'], { timeout: 20000 })); }
      catch (error) { screenshotError = error.message; }
    }, 5000);
  }
});
let launch = '';
let logResult;
let probeResult;
try {
  launch = runAdb(['shell', 'am', 'start', '-n', `${packageName}/com.godot.game.GodotAppLauncher`]);
  logResult = await loggerExit;
  if (probeExit) probeResult = await probeExit;
} catch (error) {
  failed = error.message;
  for (const child of children) child.kill();
  await loggerExit;
  if (probeExit) await probeExit;
} finally {
  clearTimeout(timer);
  clearTimeout(screenshotTimer);
}
const readJson = path => { try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; } };
const log = readJson(logPath);
const frames = probe ? readJson(framePath) : null;
let stateEnd;
try { stateEnd = state(); } catch (error) { stateEnd = { error: error.message }; }
const expectedFixture = args.fixture || 'source-crowd';
const complete = !failed && logResult?.code === 0 && probeResult?.code === 0 &&
  log?.completed && frames?.summary?.valid && log.events?.device?.fixture === expectedFixture;
const report = { started_at: start, completed_at: new Date().toISOString(), complete,
  package: packageName, serial, expected_fixture: expectedFixture, launch, ready,
  state_start: stateStart, state_end: stateEnd, log_exit: logResult, probe_exit: probeResult,
  error: failed, log_path: logPath, presented_frames_path: probe ? framePath : null,
  screenshot: args.screenshot || null, screenshot_error: screenshotError,
  summary: log?.events?.summary?.summary, presented_summary: frames?.summary,
  scope: 'One automatically synchronized foreground endpoint-validated device run. Temperature recorded before launch and after exit. No causal before/after claim without comparable conditions.' };
writeFileSync(`${prefix}-run.json`, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ complete, report: `${prefix}-run.json`, summary: report.summary, presented_summary: report.presented_summary }));
if (!complete) process.exitCode = 2;
