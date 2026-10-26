// Measure presented SurfaceView frames; Android UI gfxinfo omits game rendering.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).map(value => value.replace(/^--/, '').split('=')));
const adb = args.adb || '/Users/7700k/Library/Android/sdk/platform-tools/adb';
const serial = args.serial || 'EAWOKJGY6DIRIRT4';
const packageName = args.package || 'com.teamelo.dungeonchasers.godot';
const seconds = Number(args.seconds || 20);
const walkPattern = (args.swipes || args.swipe || '155,915,280,915').split('|').map(value => {
  const points = value.split(',').map(Number);
  if (points.length !== 4 || points.some(point => !Number.isFinite(point))) throw new Error('Each swipe must contain four finite coordinates');
  return points;
});
let walkStroke = 0;
const shell = command => execFileSync(adb, ['-s', serial, 'shell', command], { encoding: 'utf8', timeout: 15000 });
const surfaces = shell('dumpsys SurfaceFlinger --list').split('\n');
const surface = surfaces.find(value => value.includes(packageName) && value.includes('SurfaceView') && value.includes('(BLAST)'));
if (!surface) throw new Error('No presented game surface found');
const battery = shell('dumpsys battery');
const display = shell('wm size');
const state = () => ({
  power: shell('dumpsys power').split('\n').filter(value => /mWakefulness=/.test(value)).join('\n'),
  focus: shell('dumpsys window').split('\n').filter(value => /mCurrentFocus=/.test(value)).join('\n'),
});
const stateStart = state();
const timestamps = new Set();
const raw = [];
const initial = shell(`dumpsys SurfaceFlinger --latency '${surface.replaceAll("'", "'\\''")}'`);
let cutoff = 0n;
for (const line of initial.trim().split('\n').slice(1)) {
  const fields = line.trim().split(/\s+/);
  if (fields.length !== 3) continue;
  const time = BigInt(fields[1]);
  if (time > cutoff && time < 9223372036854775807n) cutoff = time;
}
const started = Date.now();
let refreshNs = 0;
let lastNewFrameMs = 0;
while (Date.now() - started < seconds * 1000) {
  const result = shell(`dumpsys SurfaceFlinger --latency '${surface.replaceAll("'", "'\\''")}'`);
  const lines = result.trim().split('\n');
  refreshNs = Number(lines.shift());
  for (const line of lines) {
    const fields = line.trim().split(/\s+/);
    if (fields.length !== 3) continue;
    const time = BigInt(fields[1]);
    if (time > cutoff && time < 9223372036854775807n && !timestamps.has(time.toString())) {
      timestamps.add(time.toString());
      lastNewFrameMs = Date.now() - started;
    }
  }
  raw.push({ elapsed_ms: Date.now() - started, result });
  if (args.phase === 'walk') {
    const points = walkPattern[walkStroke++ % walkPattern.length];
    shell(`input touchscreen swipe ${points.join(' ')} 800`);
  } else {
    await new Promise(resolve => setTimeout(resolve, 750));
  }
}
const times = [...timestamps].map(BigInt).sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
const intervals = times.slice(1).map((time, index) => Number(time - times[index]) / 1e6);
const measured = intervals;
const sorted = [...measured].sort((a, b) => a - b);
const percentile = quantile => sorted[Math.max(0, Math.ceil(sorted.length * quantile) - 1)];
const stateEnd = state();
const freshFrames = measured.length > 0 && lastNewFrameMs >= seconds * 800;
const foreground = [stateStart, stateEnd].every(value => value.focus.includes(`${packageName}/`) && value.power.includes('mWakefulness=Awake'));
const valid = freshFrames && foreground;
const summary = {
  valid, frames: measured.length,
  average_fps: measured.length ? measured.length * 1000 / measured.reduce((sum, x) => sum + x, 0) : null,
  p95_ms: percentile(0.95), p99_ms: percentile(0.99), max_ms: sorted.at(-1),
  over_33_ms: measured.filter(x => x > 33.3334).length, over_50_ms: measured.filter(x => x > 50).length,
};
const report = { measured_at: new Date().toISOString(), package: packageName, serial, surface,
  phase: args.phase || 'idle', seconds, refresh_ns: refreshNs, display, battery_start: battery,
  walk_pattern: args.phase === 'walk' ? walkPattern : [], walk_strokes: walkStroke,
  battery_end: shell('dumpsys battery'), state_start: stateStart, state_end: stateEnd,
  collection_ms: Date.now() - started, last_new_frame_ms: lastNewFrameMs,
  validation: valid ? 'Fresh frames continued through the capture window; game was awake and foreground at both endpoints.' : !foreground ? 'Game was not awake and foreground at both endpoints; exclude this run from FPS comparisons.' : 'No fresh frames, or presentation stopped before the capture window ended; exclude this run from FPS comparisons.',
  summary, intervals_ms: measured, raw,
  scope: 'Actual presented SurfaceView frame intervals, one foreground-device sample; includes compositor scheduling and device thermal state. Does not measure input latency or prove reference APK runtime parity.' };
writeFileSync(args.output || '/private/tmp/city-android-frame-probe.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(summary));
if (!valid) process.exitCode = 2;
