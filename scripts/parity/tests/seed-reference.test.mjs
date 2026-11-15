import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { PNG } from 'pngjs';
import { loadRefs, geometryProbe } from '../parity.mjs';
import { loadNativeManifest } from '../native-parity.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const refsDir = path.join(root, 'figma');
const exports = [
  ['figma-connecting-screen-362-19966@3x.png', '4ee863374c395663ea1e633ac5f88e785034311abb60ce1c6573e22871dd3e07'],
  ['figma-still-connecting-screen-362-20111@3x.png', '5944141dd7cf4b7a63aa8c290683557d1acf9c41aeb81cfcd441306a37f1d086'],
];

test('I2 seed references preserve the exact design-agent Light screen bytes at 402x874@3', () => {
  for (const [file, hash] of exports) {
    const bytes = readFileSync(path.join(refsDir, file));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), hash);
    const png = PNG.sync.read(bytes);
    assert.deepEqual([png.width, png.height], [1206, 2622]);
  }
  const ref = loadRefs(refsDir).find(r => r.id === 'ios-connecting');
  assert.ok(ref);
  assert.equal(ref.figmaNode, '362:20090');
  assert.deepEqual([ref.mode, ref.slotWidth, ref.slotHeight, ref.scale], ['Light', 402, 874, 3]);
  assert.equal(path.basename(ref.pngPath), exports[0][0]);
});

test('I2 Dark is explicitly no-reference, never a recoloured Light export', () => {
  const entries = loadNativeManifest(path.join(root, 'figma-refs.json')).entries;
  const dark = entries.find(e => e.id === 'ios-connecting-dark');
  assert.ok(dark);
  assert.equal(dark.referenceStatus, 'no-reference');
  assert.equal(dark.mode, 'Dark');
  assert.equal(loadRefs(refsDir).some(r => r.id === dark.id), false);
});

test('I2 measured skeleton geometry detects an edited copy beyond one point', () => {
  const ref = loadRefs(refsDir).find(r => r.id === 'ios-connecting');
  const board = ref.nodes.find(n => n.id === 'seed:board');
  assert.deepEqual([board.x, board.y, board.width, board.height], [16, 211, 370, 150]);
  const measured = { x: 16, y: 211, width: 370, height: 150 };
  assert.equal(geometryProbe(ref.nodes, [{ node: board.name, rect: measured }], 1).pass, true);
  assert.equal(geometryProbe(ref.nodes, [{ node: board.name, rect: { ...measured, y: 213 } }], 1).pass, false);
  const manifest = loadNativeManifest(path.join(root, 'figma-refs.json')).entries.find(e => e.id === ref.id);
  assert.equal(manifest.tolerance.geometryPx, 1);
  assert.ok(manifest.probes.geometry.includes('seed:board'));
});
