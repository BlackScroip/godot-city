import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const reports = resolve(dirname(fileURLToPath(import.meta.url)), '../reports');
const ffmpeg = process.env.FFMPEG_BIN || '/usr/local/Homebrew/bin/ffmpeg';
const ffprobe = process.env.FFPROBE_BIN || '/usr/local/Homebrew/bin/ffprobe';
const recording = JSON.parse(readFileSync(resolve(reports, 'attack-motion-visual-movement.json')));
const videoPath = resolve(reports, 'attack-motion-full.mp4');
assert.deepEqual(recording.failures, []);
assert.deepEqual(recording.missing_effects, []);
assert.equal(recording.seed, 731);
assert.equal(recording.hz, 60);
assert.equal(recording.shots.length, 28);
for (let id = 1; id <= 7; id++) {
  for (const slot of [0, 4, 2, 3]) {
    const shots = recording.shots.filter(shot => shot.character === id && shot.slot === slot);
    assert.equal(shots.length, 1, `Character ${id} slot ${slot} is recorded once`);
    assert(shots[0].actions.length > 0 && shots[0].effects > 0);
  }
}
const probe = JSON.parse(execFileSync(ffprobe, ['-v', 'error', '-show_entries',
  'stream=codec_type,codec_name,width,height,nb_frames,r_frame_rate', '-show_entries',
  'format=duration', '-of', 'json', videoPath], { encoding: 'utf8' }));
const video = probe.streams.find(stream => stream.codec_type === 'video');
const audio = probe.streams.find(stream => stream.codec_type === 'audio');
assert.equal(video.codec_name, 'h264');
assert.equal(audio.codec_name, 'aac');
assert.equal(video.r_frame_rate, '60/1');
assert.deepEqual([video.width, video.height], [1280, 720]);
assert(Number(video.nb_frames) >= recording.shots.reduce((sum, shot) => sum + shot.frames, 0));
assert(Math.abs(Number(probe.format.duration) - Number(video.nb_frames) / 60) < 0.001);
execFileSync(ffmpeg, ['-v', 'error', '-i', videoPath, '-f', 'null', '-']);
const pixels = execFileSync(ffmpeg, ['-v', 'error', '-i', videoPath, '-vf',
  `fps=${28 / Number(probe.format.duration)},crop=640:480:320:120,scale=80:60`,
  '-frames:v', '28', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-']);
const frameBytes = 80 * 60 * 3;
const samples = [];
const hashes = new Set();
for (let offset = 0; offset + frameBytes <= pixels.length; offset += frameBytes) {
  const frame = pixels.subarray(offset, offset + frameBytes);
  const mean = frame.reduce((sum, value) => sum + value, 0) / frame.length;
  const variance = frame.reduce((sum, value) => sum + (value - mean) ** 2, 0) / frame.length;
  assert(mean > 2 && variance > 2, 'Blank video sample');
  samples.push({ mean: Number(mean.toFixed(3)), variance: Number(variance.toFixed(3)) });
  hashes.add(createHash('sha256').update(frame).digest('hex'));
}
assert.equal(samples.length, 28);
assert.equal(hashes.size, 28, 'Repeated video samples');
const result = {
  schema: 1, date: '2026-10-23', seed: recording.seed, shots: recording.shots.length,
  file: videoPath, bytes: statSync(videoPath).size,
  sha256: createHash('sha256').update(readFileSync(videoPath)).digest('hex'), probe,
  sampled_frames: samples, unique_samples: hashes.size, full_decode_passed: true,
  confirmed_contacts: recording.shots.reduce((sum, shot) => sum + shot.impacts, 0),
  effects: recording.shots.reduce((sum, shot) => sum + shot.effects, 0),
  simulation_cpu_ms_p95: recording.simulation_cpu_ms_p95,
  scope: 'Current Godot assembly, all seven characters and four input categories. Static APK guidance, not APK runtime parity. MovieWriter and script CPU samples do not measure device FPS.'
};
writeFileSync(resolve(reports, 'attack-motion-media-validation.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({ shots: result.shots, samples: samples.length, contacts: result.confirmed_contacts, failures: [] }));
