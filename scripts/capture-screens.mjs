import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const outDir = path.join(root, 'assets', 'screens');

const screens = [
  { file: 'home.html', output: 'screen-comandas.png' },
  { file: 'comanda.html', output: 'screen-comanda.png' },
  { file: 'caixa.html', output: 'screen-caixa.png' },
];

await mkdir(outDir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
});

for (const screen of screens) {
  const url = `file://${path.join(root, 'mock', 'screens', screen.file)}`;
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.screenshot({
    path: path.join(outDir, screen.output),
    type: 'png',
  });
  console.log(`Captured ${screen.output}`);
}

await browser.close();
