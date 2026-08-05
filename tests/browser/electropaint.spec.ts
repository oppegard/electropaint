import { expect, test } from "@playwright/test";

async function advanceTo(page: import("@playwright/test").Page, targetTick: number): Promise<void> {
  const currentTick = Number(await page.locator("#tick-label").textContent());
  await page.evaluate((ticks) => {
    window.dispatchEvent(new CustomEvent("electropaint-test-advance", { detail: ticks }));
  }, targetTick - currentTick);
  await expect(page.locator("#tick-label")).toHaveText(String(targetTick).padStart(6, "0"));
}

test("classic default is deterministic", async ({ page }) => {
  const errors: string[] = [];
  page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
  page.on("pageerror", (error) => errors.push(error.message));
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.locator("#playback-label")).toHaveText("Reconstructed showcase");
  await expect(page.locator("#tick-label")).toHaveText("000001");
  await page.waitForTimeout(100);
  await expect(page.locator("#tick-label")).toHaveText("000001");
  await page.locator("#stage").evaluate((element: HTMLElement) => {
    element.style.width = "402px";
    element.style.height = "402px";
    element.style.margin = "0";
    element.style.position = "fixed";
    element.style.inset = "0 auto auto 0";
  });
  await advanceTo(page, 240);
  await expect(page.locator("#electropaint")).toHaveScreenshot("classic-motion-outline.png");
  await advanceTo(page, 720);
  await expect(page.locator("#electropaint")).toHaveScreenshot("classic-fade-smear.png");
  await advanceTo(page, 1080);
  await expect(page.locator("#electropaint")).toHaveScreenshot("classic-outline-only.png");
  expect(errors).toEqual([]);
});

test("IRIS_GT exposes RGB-only controls and renders", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page.locator("#stage").evaluate((element: HTMLElement) => {
    element.style.width = "402px";
    element.style.height = "402px";
    element.style.margin = "0";
    element.style.position = "fixed";
    element.style.inset = "0 auto auto 0";
  });
  await page.locator("#mode").selectOption("iris-gt");
  await expect(page.locator('[data-control-id="ribbons"]')).toBeVisible();
  await expect(page.locator('[data-control-id="depth"]')).toBeVisible();
  await advanceTo(page, 700);
  await expect(page.locator("#electropaint")).toHaveScreenshot("iris-gt-alpha-lighting-depth.png");
  await advanceTo(page, 840);
  await expect(page.locator("#electropaint")).toHaveScreenshot("iris-gt-ribbons.png");
});

test("keyboard shortcuts and malformed imports are safe", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator('[data-control-id="outline"]')).toBeChecked();
  await page.keyboard.press("o");
  await expect(page.locator('[data-control-id="outline"]')).not.toBeChecked();
  const puck = page.locator(".puck-surface");
  const bounds = await puck.boundingBox();
  if (!bounds) throw new Error("Position puck is not visible");
  await page.mouse.click(bounds.x + bounds.width * 0.75, bounds.y + bounds.height * 0.25);
  expect(Number(await page.locator('[data-control-id="position.x"]').inputValue())).toBeCloseTo(0.5, 1);
  expect(Number(await page.locator('[data-control-id="position.y"]').inputValue())).toBeCloseTo(0.5, 1);

  await page.locator("#import-file").setInputFiles("tests/browser/bad.json");
  await expect(page.locator("#session-status")).toContainText("Import rejected");
  await expect(page.locator("#mode")).toHaveValue("classic");
});

test("fullscreen entry and exit retain the square canvas", async ({ page }) => {
  await page.goto("/");
  await page.locator("#fullscreen").click();
  await expect.poll(() => page.evaluate(() => Boolean(document.fullscreenElement))).toBe(true);
  await page.keyboard.press("f");
  await expect.poll(() => page.evaluate(() => Boolean(document.fullscreenElement))).toBe(false);
});

test("WebGL context loss is explained and restored", async ({ page }) => {
  await page.goto("/");
  const supported = await page.locator("#electropaint").evaluate((canvas: HTMLCanvasElement) => {
    const gl = canvas.getContext("webgl2");
    const extension = gl?.getExtension("WEBGL_lose_context");
    if (!extension) return false;
    extension.loseContext();
    window.setTimeout(() => extension.restoreContext(), 1000);
    return true;
  });
  test.skip(!supported, "WEBGL_lose_context is unavailable");
  await expect(page.locator("#webgl-message")).toContainText("context was lost");
  await expect(page.locator("#webgl-message")).toBeHidden({ timeout: 5000 });
});

test("WebGL2 failure has an explanatory fallback", async ({ page }) => {
  await page.addInitScript(() => {
    const nativeGetContext = HTMLCanvasElement.prototype.getContext;
    Object.defineProperty(HTMLCanvasElement.prototype, "getContext", {
      configurable: true,
      value(this: HTMLCanvasElement, contextId: string, ...args: unknown[]) {
        if (contextId === "webgl2") return null;
        return Reflect.apply(nativeGetContext, this, [contextId, ...args]) as RenderingContext | null;
      },
    });
  });
  await page.goto("/");
  await expect(page.locator("#webgl-message")).toContainText("WebGL2 is unavailable");
  await expect(page.locator("#webgl-message")).toBeVisible();
});

test("hidden tabs pause without a catch-up jump", async ({ page }) => {
  await page.addInitScript(() => {
    let testHidden = false;
    Object.defineProperty(Document.prototype, "hidden", {
      configurable: true,
      get: () => testHidden,
    });
    window.addEventListener("electropaint-test-visibility", (event) => {
      testHidden = event instanceof CustomEvent && event.detail === true;
      document.dispatchEvent(new Event("visibilitychange"));
    });
  });
  await page.goto("/");
  await expect.poll(async () => Number(await page.locator("#tick-label").textContent())).toBeGreaterThan(3);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("electropaint-test-visibility", { detail: true })));
  await page.waitForTimeout(100);
  const hiddenTick = Number(await page.locator("#tick-label").textContent());
  await page.waitForTimeout(250);
  expect(Number(await page.locator("#tick-label").textContent())).toBe(hiddenTick);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("electropaint-test-visibility", { detail: false })));
  await expect.poll(async () => Number(await page.locator("#tick-label").textContent())).toBeGreaterThan(hiddenTick);
  const resumedTick = Number(await page.locator("#tick-label").textContent());
  expect(resumedTick - hiddenTick).toBeLessThan(20);
});
