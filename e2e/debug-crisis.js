// 诊断脚本 v3：完全镜像 e2e 演示链路测试，逐步计时
const { chromium } = require("@playwright/test");
(async () => {
  const t0 = Date.now();
  const mark = (m) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s] ${m}`);
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push("PAGEERROR: " + String(e).slice(0, 200)));
  await page.route(/^https?:\/\/(api\.xiaomimimo\.com|cdn\.jsdelivr\.net|api\.duckduckgo\.com)/, (r) => r.abort());
  await page.goto("http://127.0.0.1:8123/astralpath-monolith.html");
  mark("page loaded");
  await page.waitForFunction(() => window.APDiag !== undefined);
  mark("APDiag ready");
  try {
    await page.waitForSelector("#helpModal", { state: "visible", timeout: 8000 });
    await page.click("#helpClose");
    await page.waitForSelector("#helpModal", { state: "hidden", timeout: 5000 });
    mark("onboarding closed");
  } catch (e) { mark("no onboarding"); }
  await page.evaluate(() => window.APDiag && window.APDiag.clear());

  await page.click('#nav [data-p="debt"]');
  mark("debt page");
  await page.locator('[data-debtact="demo"]').click();
  mark("demo diag clicked");
  try {
    await page.waitForFunction(() => (document.getElementById("debtMsg") || {}).textContent.indexOf("已载入演示诊断") >= 0, { timeout: 20000 });
    mark("debtMsg ok");
  } catch (e) { mark("debtMsg TIMEOUT: " + ((document.getElementById("debtMsg") || {}).textContent || "").slice(0, 60)); }
  try {
    await page.waitForSelector("#debtList .card", { timeout: 20000 });
    mark("debt card visible");
  } catch (e) { mark("debt card TIMEOUT"); }

  await page.click("#btnPlan");
  mark("btnPlan clicked");
  try {
    await page.waitForFunction(() => (document.getElementById("planWarnBox") || {}).textContent.indexOf("K1–K5") >= 0, { timeout: 40000 });
    mark("K1-K5 badge ok");
  } catch (e) { mark("K badge TIMEOUT: " + ((document.getElementById("planWarnBox") || {}).textContent || "").slice(0, 60)); }

  await page.click('#nav [data-p="agent"]');
  mark("agent page");
  await page.fill("#agentIn", "我不想活了");
  await page.click("#btnSend");
  mark("send clicked");
  try {
    await page.waitForFunction(() => (document.getElementById("chat") || {}).textContent.indexOf("心理援助热线") >= 0, { timeout: 20000 });
    mark("crisis reply ok");
  } catch (e) {
    const last = await page.evaluate(() => { var b = document.querySelectorAll("#chat .bub"); return b.length ? b[b.length - 1].textContent.slice(0, 80) : "(empty)"; });
    mark("crisis reply TIMEOUT, lastBub=" + last);
  }
  try {
    await page.waitForFunction(() => !!document.getElementById("ap-notify-stack"), { timeout: 10000 });
    mark("notify card ok");
  } catch (e) { mark("notify TIMEOUT"); }

  console.log("diag errors:", await page.evaluate(() => window.APDiag.count()));
  errors.slice(0, 6).forEach((e) => console.log("  ", e));
  await browser.close();
})();
