import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const reports = resolve(dirname(fileURLToPath(import.meta.url)), '../reports');
const ffmpeg = process.env.FFMPEG_BIN || '/usr/local/Homebrew/bin/ffmpeg';
const ffprobe = process.env.FFPROBE_BIN || '/usr/local/Homebrew/bin/ffprobe';
const readJson = name => JSON.parse(readFileSync(resolve(reports, name), 'utf8'));
const full = readJson('heavy-visual-heavy-full.json');
const low = readJson('heavy-visual-heavy-low.json');
const fields = ['name', 'character', 'slot', 'enemy', 'frames', 'actions', 'damage', 'impacts', 'contact_frames', 'target_end_positions', 'player_end_position'];

for (const result of [full, low]) {
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.missing_effects, []);
  assert.equal(result.shots.length, 7);
  assert.equal(result.seed, 731);
  assert.equal(result.hz, 60);
}
for (const [index, shot] of full.shots.entries()) {
  assert(shot.impacts > 0, `${shot.name}: no contacts`);
  for (const field of fields) assert.deepEqual(shot[field], low.shots[index][field], `${shot.name}: ${field}`);
}

const videos = [];
for (const quality of ['full', 'low']) {
  const file = resolve(reports, `heavy-${quality}.mp4`);
  const probe = JSON.parse(execFileSync(ffprobe, ['-v', 'error', '-show_entries', 'stream=codec_type,codec_name,width,height,nb_frames,r_frame_rate', '-show_entries', 'format=duration', '-of', 'json', file], { encoding: 'utf8' }));
  const video = probe.streams.find(s => s.codec_type === 'video');
  const audio = probe.streams.find(s => s.codec_type === 'audio');
  assert.equal(video.codec_name, 'h264');
  assert.equal(audio.codec_name, 'aac');
  assert.deepEqual([video.width, video.height, video.nb_frames, video.r_frame_rate], [1280, 720, '2115', '60/1']);
  assert(Math.abs(Number(probe.format.duration) - 35.25) < 0.001);
  execFileSync(ffmpeg, ['-v', 'error', '-i', file, '-f', 'null', '-']);
  const samples = execFileSync(ffmpeg, ['-v', 'error', '-ss', '1', '-i', file, '-vf', 'fps=1/5,scale=64:36', '-frames:v', '7', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-']);
  const frameBytes = 64 * 36 * 3;
  const variances = [];
  const hashes = new Set();
  for (let offset = 0; offset + frameBytes <= samples.length; offset += frameBytes) {
    const frame = samples.subarray(offset, offset + frameBytes);
    const mean = frame.reduce((sum, value) => sum + value, 0) / frame.length;
    const variance = frame.reduce((sum, value) => sum + (value - mean) ** 2, 0) / frame.length;
    assert(mean > 2 && variance > 2, `${quality}: blank video sample`);
    variances.push(Number(variance.toFixed(3)));
    hashes.add(createHash('sha256').update(frame).digest('hex'));
  }
  assert.equal(variances.length, 7);
  assert.equal(hashes.size, 7, `${quality}: repeated video samples`);
  videos.push({ file, bytes: statSync(file).size, sha256: createHash('sha256').update(readFileSync(file)).digest('hex'), probe, sampled_frame_variances: variances });
}

const result = {
  schema: 1, date: '2026-10-23', seed: 731, hz: 60,
  full_low_contact_damage_actions_positions_identical: true,
  confirmed_contacts_each: full.shots.reduce((sum, shot) => sum + shot.impacts, 0),
  effects: { full: full.shots.reduce((sum, shot) => sum + shot.effects, 0), low: low.shots.reduce((sum, shot) => sum + shot.effects, 0) },
  simulation_cpu_ms_p95: { full: full.simulation_cpu_ms_p95, low: low.simulation_cpu_ms_p95 },
  videos,
  scope: 'Fixed MovieWriter visual verification. CPU samples exclude rendering; these results are not device FPS or mobile acceptance. APK shader/runtime parity is not established.'
};
writeFileSync(resolve(reports, 'heavy-media-validation.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({ videos: videos.length, contacts: result.confirmed_contacts_each, quality_results_identical: true, failures: [] }));
