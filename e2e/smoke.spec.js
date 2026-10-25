// 浏览器冒烟：三条主流程 + 零运行期错误
// ① 教材解析：导入示例教材，首页出现图谱摘要
// ② 练习出题：今日任务加载后开始练习，出现题干与选项
// ③ 修复计划：知债页生成 14 天计划，出现计划条目
// 全程阻断外部网络：AI 入口走本地规则兜底，冒烟只验证本机链路（不依赖模型可用性）
const { test, expect } = require("@playwright/test");

const EXTERNAL = /^https?:\/\/(api\.xiaomimimo\.com|cdn\.jsdelivr\.net|api\.duckduckgo\.com)/;

test.beforeEach(async ({ page }) => {
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.route(EXTERNAL, (r) => r.abort());
  await page.goto("/astralpath-monolith.html");
  await expect(page.locator("#btnSeed")).toBeVisible();
  await page.waitForFunction(() => window.APDiag !== undefined);
  // 首次启动会延迟弹出帮助中心（onboarding），它会拦截点击，出现就关掉
  try {
    await page.waitForSelector("#helpModal", { state: "visible", timeout: 8000 });
    await page.click("#helpClose");
    await page.waitForSelector("#helpModal", { state: "hidden", timeout: 5000 });
  } catch (e) {
    /* 没出现就算了 */
  }
  await page.evaluate(() => window.APDiag && window.APDiag.clear());
});

test("三条流冒烟：教材解析、练习出题、修复计划，且无运行期错误", async ({ page }) => {
  // ① 教材解析
  await page.click("#btnSeed");
  await expect(page.locator("#homeBook")).toContainText("节点", { timeout: 25_000 });

  // ② 练习出题
  await page.click('#nav [data-p="today"]');
  await page.click("#btnLoadToday");
  await expect(page.locator("#todayList")).not.toBeEmpty({ timeout: 25_000 });
  await page.locator("#todayList [data-start]").first().click();
  await expect(page.locator("#quizBox strong").first()).toBeVisible({ timeout: 25_000 });
  expect(await page.locator('#quizBox button[role="radio"]').count()).toBeGreaterThan(1);

  // ③ 修复计划
  await page.click('#nav [data-p="debt"]');
  await page.click("#btnPlan");
  await expect(page.locator("#planBox")).not.toBeEmpty({ timeout: 40_000 });
  await expect(page.locator("#planBox")).toContainText(/\S/);

  // ④ 模块接线：shared/exam.js 经 AP 生成区内联后，页面侧仍可按全局名调用
  const examOk = await page.evaluate(() => {
    try {
      const r = APExam.structureExamText("一、单选题\n1. 甲（ ）\nA. 1\nB. 2\n答案：B", "exam");
      return typeof structureExamText === "function" && r.items.length === 1 && r.items[0].answer === "B";
    } catch (e) {
      return false;
    }
  });
  expect(examOk).toBe(true);

  // 零运行期错误（APDiag 环形日志）
  const errCount = await page.evaluate(() => window.APDiag.count());
  expect(errCount).toBe(0);
});
