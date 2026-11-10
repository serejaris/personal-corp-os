#!/usr/bin/env node
// Render skill cards (1080x1920 HTML files) to PNG and report vertical headroom.
// Usage: node render_card.js card.html [more.html ...]
// Needs Playwright with Chromium: npm i -D playwright && npx playwright install chromium

const path = require('path');
const { chromium } = require('playwright');

const WIDTH = 1080;
const HEIGHT = 1920;
const MIN_HEADROOM = 24;

async function measure(page) {
  return page.evaluate(() => {
    // Card structure: root frame > inner card > blocks; the footer is the last block.
    const card = document.body.firstElementChild.firstElementChild;
    const blocks = [...card.children];
    const footer = blocks[blocks.length - 1];
    const last = blocks[blocks.length - 2];
    const gap = parseFloat(getComputedStyle(card).rowGap) || 0;
    // A family counts only if one of its faces actually loaded: check() is true for undeclared fonts.
    const loaded = (family) => [...document.fonts].some(
      (face) => face.family.replace(/["']/g, '') === family && face.status === 'loaded');
    return {
      overflow: card.scrollHeight - card.clientHeight,
      pageOverflow: document.documentElement.scrollHeight - 1920,
      headroom: Math.round(footer.getBoundingClientRect().top - last.getBoundingClientRect().bottom - gap),
      fontsLoaded: loaded('Unbounded') && loaded('JetBrains Mono'),
    };
  });
}

(async () => {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('Использование: node render_card.js карточка.html [ещё.html ...]');
    process.exit(2);
  }

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } });
  let failed = false;

  for (const file of files) {
    const abs = path.resolve(file);
    await page.goto('file://' + abs);
    await page.evaluate(() => document.fonts.ready);
    const m = await measure(page);
    const png = abs.replace(/\.html?$/i, '') + '.png';
    await page.screenshot({ path: png, clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT } });

    if (!m.fontsLoaded) {
      console.log(`ВНИМАНИЕ ${file}: шрифты Unbounded / JetBrains Mono не загрузились, замер приблизительный`);
    }
    const overflow = Math.max(m.overflow, m.pageOverflow);
    if (overflow > 0) {
      failed = true;
      console.log(`ПЕРЕПОЛНЕНИЕ ${file}: ${overflow} px, сократи текст`);
    } else if (m.headroom < MIN_HEADROOM) {
      failed = true;
      console.log(`ТЕСНО ${file}: запас ${m.headroom} px, нужно от ${MIN_HEADROOM}`);
    } else {
      console.log(`OK ${file}: запас ${m.headroom} px, картинка ${png}`);
    }
  }

  await browser.close();
  process.exit(failed ? 1 : 0);
})();
