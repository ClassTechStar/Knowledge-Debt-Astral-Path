// Hallmark after 截图：起点 / 知债 / 识网 三屏（1440×900）
const { chromium } = require("@playwright/test");
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.route(/^https?:\/\/(api\.xiaomimimo\.com|cdn\.jsdelivr\.net|api\.duckduckgo\.com)/, (r) => r.abort());
  await page.goto("http://127.0.0.1:8123/astralpath-monolith.html");
  await page.waitForFunction(() => window.APDiag !== undefined, { timeout: 20000 });
  try {
    await page.waitForSelector("#helpModal", { state: "visible", timeout: 6000 });
    await page.click("#helpClose");
  } catch (e) { /* 没弹就算了 */ }
  await page.evaluate(() => window.APDiag && window.APDiag.clear());
  await page.waitForTimeout(600);
  await page.screenshot({ path: ".hallmark/after-home.png" });
  await page.click('#nav [data-p="debt"]');
  await page.locator('[data-debtact="demo"]').click();
  await page.waitForTimeout(2500);
  await page.screenshot({ path: ".hallmark/after-debt.png" });
  await page.click('#nav [data-p="graph"]');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: ".hallmark/after-graph.png" });
  console.log("shots saved: after-home / after-debt / after-graph");
  await browser.close();
})();
