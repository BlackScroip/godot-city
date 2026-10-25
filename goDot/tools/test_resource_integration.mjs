import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const godot = process.env.GODOT_BIN ?? "/Applications/Godot.app/Contents/MacOS/Godot";
const tests = [
  "resource_audio_test", "player_transfer_test", "resource_feedback_test",
  "world_interactions_test", "environment_effects_test", "game_flow_test",
  "loot_flow_test", "room_gate_flow_test", "special_room_gate_test", "route_presentation_test",
];
const report = { command: "node tools/test_resource_integration.mjs", tests: [], passed: true };
mkdirSync(path.join(root, "reports"), { recursive: true });
for (const name of tests) {
  const result = spawnSync(godot, ["--headless", "--path", root, "--script", `tests/${name}.gd`, "--log-file", `/private/tmp/city-${name}.log`], { encoding: "utf8", timeout: 120000 });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  const passed = result.status === 0 && !/SCRIPT ERROR:|ERROR:|FAILURE:/.test(output);
  report.tests.push({ name, passed, exit_code: result.status, error: result.error?.message, output: output.trim() });
  report.passed &&= passed;
  console.log(`${passed ? "PASS" : "FAIL"} ${name}: ${output.trim().split("\n").at(-1)}`);
}
writeFileSync(path.join(root, "reports/resource-integration-tests.json"), JSON.stringify(report, null, 2) + "\n");
process.exitCode = report.passed ? 0 : 1;
