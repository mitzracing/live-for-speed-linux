#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn, spawnSync } from "node:child_process";

function browserBinary() {
  const candidates = [
    process.env.CHROME_BIN,
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  for (const name of ["chromium", "google-chrome", "google-chrome-stable", "chrome"]) {
    const located = spawnSync("which", [name], { encoding: "utf8" });
    if (located.status === 0 && located.stdout.trim()) return located.stdout.trim();
  }
  return null;
}

async function waitForDevToolsFile(path, browser) {
  for (let attempt = 0; attempt < 600; attempt += 1) {
    if (browser.exitCode !== null) throw new Error(`browser exited with ${browser.exitCode}`);
    if (existsSync(path)) return (await readFile(path, "utf8")).split("\n")[0].trim();
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 50));
  }
  throw new Error("browser DevTools endpoint did not start");
}

class DevToolsClient {
  constructor(url) {
    this.nextId = 1;
    this.pending = new Map();
    this.socket = new WebSocket(url);
  }

  async open() {
    await new Promise((resolvePromise, reject) => {
      this.socket.addEventListener("open", resolvePromise, { once: true });
      this.socket.addEventListener("error", reject, { once: true });
    });
    this.socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (!message.id || !this.pending.has(message.id)) return;
      const { resolve: resolvePromise, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolvePromise(message.result);
    });
  }

  send(method, params = {}) {
    const id = this.nextId;
    this.nextId += 1;
    return new Promise((resolvePromise, reject) => {
      this.pending.set(id, { resolve: resolvePromise, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket.close();
  }
}

const browserPath = browserBinary();
if (!browserPath) {
  if (process.env.CI || process.env.REQUIRE_BROWSER_E2E === "1") {
    throw new Error("Chromium or Google Chrome is required for browser E2E coverage");
  }
  console.log("[SKIP] browser feedback E2E: Chromium or Google Chrome not found");
  process.exit(0);
}

const profile = await mkdtemp(join(tmpdir(), "lfs-feedback-browser-"));
const browser = spawn(
  browserPath,
  [
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--hide-scrollbars",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "about:blank",
  ],
  { stdio: "ignore" },
);

let client;
try {
  const port = await waitForDevToolsFile(join(profile, "DevToolsActivePort"), browser);
  const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = pages.find((candidate) => candidate.type === "page");
  assert.ok(page?.webSocketDebuggerUrl, "no browser page target");
  client = new DevToolsClient(page.webSocketDebuggerUrl);
  await client.open();
  await client.send("Page.enable");
  await client.send("Runtime.enable");
  const target = pathToFileURL(fileURLToPath(new URL("../website/index.html", import.meta.url))).href;
  await client.send("Page.navigate", { url: target });

  let ready = false;
  for (let attempt = 0; attempt < 100 && !ready; attempt += 1) {
    const result = await client.send("Runtime.evaluate", {
      expression: "document.readyState === 'complete' && Boolean(window.LfsFeedback)",
      returnByValue: true,
    });
    ready = Boolean(result.result.value);
    if (!ready) await new Promise((resolvePromise) => setTimeout(resolvePromise, 50));
  }
  assert.ok(ready, "website feedback script did not initialize");

  const readLayout = async (width) => {
    await client.send("Emulation.setDeviceMetricsOverride", {
      width,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false,
    });
    const result = await client.send("Runtime.evaluate", {
      expression: `(() => {
        const bounds = (selector) => {
          const rect = document.querySelector(selector).getBoundingClientRect();
          return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom };
        };
        const main = document.querySelector('.main-column');
        const mainRect = main.getBoundingClientRect();
        const mainOverflow = [...main.querySelectorAll('*')].filter((element) => {
          const rect = element.getBoundingClientRect();
          if (!rect.width || (rect.left >= mainRect.left - 0.5 && rect.right <= mainRect.right + 0.5)) return false;
          for (let ancestor = element.parentElement; ancestor && ancestor !== main; ancestor = ancestor.parentElement) {
            const ancestorRect = ancestor.getBoundingClientRect();
            const overflow = getComputedStyle(ancestor).overflowX;
            if (['auto', 'hidden', 'scroll', 'clip'].includes(overflow)
              && ancestorRect.left >= mainRect.left - 0.5
              && ancestorRect.right <= mainRect.right + 0.5) return false;
          }
          return true;
        }).map((element) => element.tagName + (element.className ? '.' + String(element.className).replaceAll(' ', '.') : ''));
        return {
          page: bounds('.page-grid'),
          main: bounds('.main-column'),
          mainOverflow,
          mainPanels: [...main.children].map((panel) => {
            const rect = panel.getBoundingClientRect();
            return { left: rect.left, right: rect.right };
          }),
          side: bounds('.side-column'),
          sidePanels: [...document.querySelectorAll('.side-panel')].map((panel) => {
            const rect = panel.getBoundingClientRect();
            return { left: rect.left, right: rect.right };
          }),
        };
      })()`,
      returnByValue: true,
    });
    return result.result.value;
  };

  for (const width of [1440, 1024, 800]) {
    const layout = await readLayout(width);
    assert.ok(Math.abs(layout.main.top - layout.side.top) < 1, `columns not aligned at ${width}px`);
    assert.ok(layout.main.right <= layout.side.left + 0.5, `main column overlaps sidebar at ${width}px`);
    assert.ok(
      layout.mainPanels.every((panel) => panel.left >= layout.main.left - 0.5 && panel.right <= layout.main.right + 0.5),
      `main panel escapes its column at ${width}px`,
    );
    assert.deepEqual(layout.mainOverflow, [], `main descendant escapes its column at ${width}px: ${layout.mainOverflow.join(', ')}`);
    assert.ok(layout.side.right <= layout.page.right + 0.5, `sidebar escapes page grid at ${width}px`);
    assert.ok(
      layout.sidePanels.every((panel) => panel.left >= layout.side.left - 0.5 && panel.right <= layout.side.right + 0.5),
      `sidebar panel escapes its column at ${width}px`,
    );
  }

  const stackedLayout = await readLayout(760);
  assert.ok(stackedLayout.side.top >= stackedLayout.main.bottom, "sidebar does not stack below main content at 760px");

  const evaluated = await client.send("Runtime.evaluate", {
    expression: `(() => {
      const disclosure = document.getElementById('feedback-disclosure');
      const wasCollapsed = !disclosure.open;
      document.querySelector('[data-feedback-kind="compatibility"]').click();
      const form = document.getElementById('feedback-form');
      const set = (name, value) => { form.elements[name].value = value; };
      set('summary', 'Browser-generated compatibility report');
      set('distribution', 'Manjaro Linux');
      set('distributionVersion', 'Manjaro 26.0');
      set('packageMethod', 'source archive');
      set('desktop', 'KDE Plasma 6 on X11');
      set('graphics', 'NVIDIA RTX 3070, driver 580.82');
      set('details', 'Setup completed and the main menu opened.');
      set('expected', 'The documented setup should remain reproducible.');
      set('steps', '1. Install wrapper.\\n2. Run setup.\\n3. Open game.');
      set('value', 'Validate support on this distribution.');
      set('diagnostics', 'Log: /home/alice/.local/state/lfs-linux/latest.log\\nemail=alice@example.invalid\\ntoken=' + 'abcdefghijklmnopqrstuvwxyz0123456789');
      form.elements.safety.checked = true;
      form.requestSubmit();
      const result = document.getElementById('feedback-result');
      return {
        wasCollapsed,
        disclosureOpen: disclosure.open,
        hidden: result.hidden,
        href: document.getElementById('github-handoff').href,
        status: document.getElementById('feedback-status').textContent,
        preview: document.getElementById('report-preview').textContent,
        diagnostics: form.elements.diagnostics.value,
        activeId: document.activeElement.id,
      };
    })()`,
    returnByValue: true,
  });
  const outcome = evaluated.result.value;
  assert.equal(outcome.wasCollapsed, true);
  assert.equal(outcome.disclosureOpen, true);
  assert.equal(outcome.hidden, false);
  assert.match(outcome.status, /Removed before handoff/);
  assert.equal(outcome.activeId, "github-handoff");

  const handoff = new URL(outcome.href);
  assert.equal(handoff.origin, "https://github.com");
  assert.equal(handoff.pathname, "/mitzracing/live-for-speed-linux/issues/new");
  assert.equal(handoff.searchParams.get("template"), "compatibility.yml");
  for (const field of [
    "title",
    "distribution",
    "distribution_version",
    "package_method",
    "desktop",
    "graphics",
    "result",
    "reproduction",
    "diagnostics",
  ]) {
    assert.ok(handoff.searchParams.get(field), `browser handoff omitted ${field}`);
  }
  for (const privateValue of ["/home/alice", "alice@example.invalid", "abcdefghijklmnopqrstuvwxyz0123456789"]) {
    assert.ok(!decodeURIComponent(outcome.href).includes(privateValue), `handoff leaked ${privateValue}`);
    assert.ok(!outcome.preview.includes(privateValue), `preview leaked ${privateValue}`);
    assert.ok(!outcome.diagnostics.includes(privateValue), `form retained ${privateValue}`);
  }

  const collapsed = await client.send("Runtime.evaluate", {
    expression: `(() => {
      document.getElementById('collapse-feedback').click();
      return {
        open: document.getElementById('feedback-disclosure').open,
        focusedTag: document.activeElement.tagName,
      };
    })()`,
    returnByValue: true,
  });
  assert.equal(collapsed.result.value.open, false);
  assert.equal(collapsed.result.value.focusedTag, "SUMMARY");

  console.log("[PASS] real browser keeps main/sidebar geometry isolated and exercises safe GitHub handoff");
} finally {
  if (client) client.close();
  browser.kill("SIGTERM");
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
  if (browser.exitCode === null) browser.kill("SIGKILL");
  await rm(profile, { recursive: true, force: true });
}
