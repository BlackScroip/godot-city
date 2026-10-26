// Capture a fresh bounded fixture run before Android's log buffer rotates.
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).map(value => value.replace(/^--/, '').split('=')));
const adb = args.adb || '/Users/7700k/Library/Android/sdk/platform-tools/adb';
const serial = args.serial || 'EAWOKJGY6DIRIRT4';
const output = args.output || '/private/tmp/city-combat-log.json';
const markers = {
  COMBAT_STRESS_READY: 'ready', COMBAT_STRESS: 'summary',
  COMBAT_STRESS_PHASES: 'phases', COMBAT_STRESS_DEVICE: 'device',
  COMBAT_STRESS_CPU: 'cpu_scopes', COMBAT_STRESS_RENDER: 'render_timing',
};
const events = {};
const raw = [];
let pending = '';
let completed = false;
const child = spawn(adb, ['-s', serial, 'logcat', '-T', '1', '-v', 'time', '-s', 'godot']);
const timer = setTimeout(() => child.kill(), Number(args.timeout || 180) * 1000);
child.stdout.setEncoding('utf8');
child.stdout.on('data', data => {
  pending += data;
  const lines = pending.split('\n');
  pending = lines.pop();
  for (const line of lines) {
    raw.push(line);
    for (const [marker, name] of Object.entries(markers)) {
      const offset = line.indexOf(`${marker} `);
      if (offset < 0) continue;
      if (name !== 'ready' && !events.ready) continue;
      try {
        events[name] = JSON.parse(line.slice(offset + marker.length + 1));
        console.log(`${marker} ${JSON.stringify(events[name])}`);
      } catch { /* Ignore unrelated or OS-truncated lines. */ }
      if (name === 'device' && events.summary && events.phases) {
        completed = true;
        child.kill();
      }
    }
  }
});
child.stderr.on('data', data => process.stderr.write(data));
child.on('error', error => {
  console.error(error.message);
  process.exitCode = 2;
});
child.on('close', () => {
  clearTimeout(timer);
  writeFileSync(output, JSON.stringify({ completed, serial, captured_at: new Date().toISOString(), events, raw }, null, 2) + '\n');
  if (!completed) process.exitCode = 2;
});
