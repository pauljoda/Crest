import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import { mkdir, stat } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
let chromium;

try {
  ({ chromium } = require("playwright"));
} catch (playwrightError) {
  try {
    ({ chromium } = require("@playwright/test"));
  } catch {
    throw new Error(
      "Playwright is required. Install playwright or provide it through NODE_PATH.",
      { cause: playwrightError },
    );
  }
}

const here = path.dirname(fileURLToPath(import.meta.url));
const outputDirectory = path.join(here, "screenshots");
const galleryUrl = pathToFileURL(path.join(here, "gallery.html"));

const captures = [
  ...Array.from({ length: 6 }, (_, index) => ({
    id: `iphone-${String(index + 1).padStart(2, "0")}`,
    width: 1242,
    height: 2688,
    directory: "iphone-6.5",
    filename: `${String(index + 1).padStart(2, "0")}.png`,
  })),
  ...Array.from({ length: 6 }, (_, index) => ({
    id: `ipad-${String(index + 1).padStart(2, "0")}`,
    width: 2064,
    height: 2752,
    directory: "ipad-13",
    filename: `${String(index + 1).padStart(2, "0")}.png`,
  })),
];

const installedChrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const executablePath =
  process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ??
  (existsSync(installedChrome) ? installedChrome : undefined);
const browser = await chromium.launch({ headless: true, executablePath });

try {
  for (const capture of captures) {
    const captureDirectory = path.join(outputDirectory, capture.directory);
    await mkdir(captureDirectory, { recursive: true });

    const page = await browser.newPage({
      viewport: { width: capture.width, height: capture.height },
      deviceScaleFactor: 1,
    });

    const url = new URL(galleryUrl);
    url.searchParams.set("slide", capture.id);
    await page.goto(url.href, { waitUntil: "load" });
    await page.evaluate(() => document.fonts.ready);

    const target = page.locator(`#${capture.id}`);
    const bounds = await target.boundingBox();
    if (
      !bounds ||
      Math.round(bounds.width) !== capture.width ||
      Math.round(bounds.height) !== capture.height
    ) {
      throw new Error(
        `${capture.id} rendered at ${bounds?.width}×${bounds?.height}; expected ${capture.width}×${capture.height}`,
      );
    }

    const missingImages = await target.locator("img").evaluateAll((images) =>
      images
        .filter((image) => !image.complete || image.naturalWidth === 0)
        .map((image) => image.getAttribute("src")),
    );
    if (missingImages.length > 0) {
      throw new Error(`${capture.id} has unloaded images: ${missingImages.join(", ")}`);
    }

    const overflow = await target.locator("[data-copy]").evaluateAll((elements) =>
      elements
        .filter(
          (element) =>
            element.scrollWidth > element.clientWidth + 1 ||
            element.scrollHeight > element.clientHeight + 1,
        )
        .map((element) => ({
          text: element.textContent?.trim().slice(0, 120),
          clientWidth: element.clientWidth,
          scrollWidth: element.scrollWidth,
          clientHeight: element.clientHeight,
          scrollHeight: element.scrollHeight,
        })),
    );
    if (overflow.length > 0) {
      throw new Error(`${capture.id} has clipped copy: ${JSON.stringify(overflow)}`);
    }

    const outputPath = path.join(captureDirectory, capture.filename);
    await target.screenshot({ path: outputPath, type: "png" });

    const output = await stat(outputPath);
    if (output.size > 10_000_000) {
      throw new Error(
        `${capture.directory}/${capture.filename} is ${output.size} bytes; App Store screenshots must remain below 10 MB`,
      );
    }

    await page.close();
    console.log(
      `Rendered ${capture.directory}/${capture.filename} (${capture.width}×${capture.height}, ${Math.round(output.size / 1024)} KB)`,
    );
  }
} finally {
  await browser.close();
}
