#!/usr/bin/env node
// Optional: LFS_WEBSITE_URL checks a deployed site instead of the staged local files.
// LFS_WEBSITE_SCREENSHOTS saves visual evidence to the supplied directory.
import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
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
      const { method, resolve: resolvePromise, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(`${method}: ${message.error.message}`));
      else resolvePromise(message.result);
    });
  }

  send(method, params = {}) {
    const id = this.nextId;
    this.nextId += 1;
    return new Promise((resolvePromise, reject) => {
      this.pending.set(id, { method, resolve: resolvePromise, reject });
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
  const site = join(profile, "site");
  await mkdir(site);
  for (const name of ["index.html", "styles.css", "feedback.js"]) {
    await copyFile(new URL(`../website/${name}`, import.meta.url), join(site, name));
  }
  await copyFile(new URL("../share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg", import.meta.url), join(site, "icon.svg"));
  const target = process.env.LFS_WEBSITE_URL || pathToFileURL(join(site, "index.html")).href;
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

  const screenshotDirectory = process.env.LFS_WEBSITE_SCREENSHOTS;
  const capture = async (name, selector) => {
    if (!screenshotDirectory) return;
    await mkdir(screenshotDirectory, { recursive: true });
    const measured = await client.send("Runtime.evaluate", {
      expression: `(() => {
        window.scrollTo({top: 0, behavior: 'instant'});
        const rect = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();
        return {x: 0, y: Math.max(0, rect.top + scrollY), width: innerWidth, height: Math.min(1400, rect.height), scale: 1};
      })()`,
      returnByValue: true,
    });
    const image = await client.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: measured.result.value });
    await writeFile(join(screenshotDirectory, `${name}.png`), Buffer.from(image.data, "base64"));
  };

  const version = (await readFile(new URL("../VERSION", import.meta.url), "utf8")).trim();
  const release = `https://github.com/mitzracing/live-for-speed-linux/releases/download/v${version}`;
  const expectedDownloads = [
    `${release}/live-for-speed-linux_${version}-0github1_amd64.deb`,
    `${release}/live-for-speed-linux-${version}-1-x86_64.pkg.tar.zst`,
  ];
  const readLayout = async (width, deviceScaleFactor = 1) => {
    await client.send("Emulation.setDeviceMetricsOverride", { width, height: 1000, deviceScaleFactor, mobile: false });
    const result = await client.send("Runtime.evaluate", {
      expression: `(() => {
        // Exercise the original defect even when checking an older, accordion-based site.
        document.querySelectorAll('#install details').forEach(el => el.open = true);
        const links = [...document.querySelectorAll('#install a[href*="/releases/download/"]')];
        const controls = links.map(link => {
          link.scrollIntoView({block: 'center', behavior: 'instant'});
          const rect = link.getBoundingClientRect();
          const card = link.closest('article, details');
          const bounds = card.getBoundingClientRect();
          const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
          const overlaps = [...card.querySelectorAll('p, h3, a')].filter(other => {
            if (other === link || other.contains(link) || link.contains(other)) return false;
            const r = other.getBoundingClientRect();
            return Math.min(rect.right, r.right) - Math.max(rect.left, r.left) > 0.5
              && Math.min(rect.bottom, r.bottom) - Math.max(rect.top, r.top) > 0.5;
          }).map(other => other.textContent.trim());
          return {
            label: link.textContent.trim(), href: link.href, overlaps,
            fragments: link.getClientRects().length,
            width: rect.width, height: rect.height,
            contained: rect.left >= bounds.left && rect.right <= bounds.right,
            reachable: Boolean(hit && link.contains(hit)),
            hiddenInDetails: Boolean(link.closest('details')),
          };
        });
        const cards = links.map(link => {
          const r = link.closest('article, details').getBoundingClientRect();
          return {left: r.left, right: r.right, top: r.top, bottom: r.bottom};
        });
        return {controls, cards, pageWidth: document.documentElement.scrollWidth, viewport: innerWidth};
      })()`,
      returnByValue: true,
    });
    assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
    const layout = result.result.value;
    assert.equal(layout.controls.length, 2, "both distribution downloads must exist");
    for (const control of layout.controls) {
      const context = `${control.label} at ${width}px / ${deviceScaleFactor}x`;
      assert.deepEqual(control.overlaps, [], `download overlaps surrounding content: ${context}`);
      assert.equal(control.fragments, 1, `download fragments across lines: ${context}`);
      assert.ok(control.width >= 44 && control.height >= 44, `small download target: ${context}`);
      assert.ok(control.contained && control.reachable, `download clipped or obscured: ${context}`);
      assert.equal(control.hiddenInDetails, false, `download hidden inside disclosure: ${context}`);
    }
    assert.deepEqual(layout.controls.map(control => control.href), expectedDownloads, "release download targets changed");
    assert.ok(layout.pageWidth <= layout.viewport + 1, `horizontal page overflow at ${width}px`);
    const [first, second] = layout.cards;
    if (width > 760) {
      assert.ok(Math.abs(first.top - second.top) < 1 && first.right <= second.left, `download cards overlap or misalign at ${width}px`);
    } else {
      assert.ok(second.top >= first.bottom + 16, `download cards do not stack with a gap at ${width}px`);
    }
    return layout;
  };

  for (const width of [1440, 1024, 800, 768, 760, 390, 320]) {
    await readLayout(width);
    if ([1440, 390].includes(width)) {
      await capture(`top-${width}`, 'body');
      await capture(`downloads-${width}`, '#install');
      for (const selector of ['#how-it-works', '#trust', '#support', '.technical', '.site-footer']) {
        await capture(`${selector.slice(1)}-${width}`, selector);
      }
    }
  }
  await readLayout(720, 2); // 1440 physical pixels at 200% scale; 720 CSS pixels of reflow.
  await client.send("Runtime.evaluate", { expression: "document.documentElement.style.fontSize = '200%'" });
  await readLayout(320);
  await client.send("Runtime.evaluate", { expression: "document.documentElement.style.removeProperty('font-size')" });
  await readLayout(390);

  for (const kind of ['bug', 'compatibility', 'feature', 'feedback']) {
    const selected = await client.send("Runtime.evaluate", {
      expression: `(() => {
        document.querySelector('[data-feedback-kind="${kind}"]').click();
        const form = document.getElementById('feedback-form');
        return {
          open: document.getElementById('feedback-disclosure').open,
          kind: form.elements.kind.value, focus: document.activeElement.id,
          packageHidden: form.querySelector('[data-package-method]').hidden,
          wrapperHidden: form.querySelector('[data-wrapper-version]').hidden,
          required: [...form.elements].filter(el => el.required).map(el => el.id).sort(),
          expanded: [...document.querySelectorAll('[data-feedback-kind]')].every(el => el.getAttribute('aria-expanded') === 'true'),
        };
      })()`, returnByValue: true,
    });
    const state = selected.result.value;
    assert.ok(state.open && state.expanded);
    assert.equal(state.kind, kind);
    assert.equal(state.focus, 'summary');
    assert.equal(state.packageHidden, kind !== 'compatibility');
    assert.equal(state.wrapperHidden, kind !== 'bug');
    const required = ['kind', 'summary', 'details', 'expected', 'safety'];
    if (['bug', 'compatibility'].includes(kind)) required.push('distribution', 'distributionVersion', 'desktop', 'graphics', 'steps');
    if (kind === 'bug') required.push('wrapperVersion');
    if (kind === 'compatibility') required.push('packageMethod');
    if (kind === 'feature') required.push('value');
    assert.deepEqual(state.required, required.sort());
  }
  await capture('feedback-390', '#feedback-disclosure');

  const contrast = await client.send("Runtime.evaluate", {
    expression: `(() => {
      const rgb = value => value.match(/[\\d.]+/g).map(Number);
      const luminance = value => rgb(value).slice(0, 3).map(n => {
        const c = n / 255;
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
      }).reduce((sum, n, i) => sum + n * [0.2126, 0.7152, 0.0722][i], 0);
      const background = el => {
        for (let node = el; node; node = node.parentElement) {
          const color = getComputedStyle(node).backgroundColor;
          if (rgb(color)[3] !== 0) return color;
        }
        throw new Error('No opaque page background');
      };
      const selectors = ['body', '.hero-lede', '.hero-note', '.eyebrow', '.button.primary', '.text-link', '.download-card p', '.release-notice', '.release-badge', 'nav a', '.legal', '.support-card strong', '.support-card span', 'label', 'input', 'select', 'textarea'];
      return selectors.flatMap(selector => [...document.querySelectorAll(selector)].map(el => {
        const foreground = luminance(getComputedStyle(el).color);
        const behind = luminance(background(el));
        return {selector, ratio: (Math.max(foreground, behind) + 0.05) / (Math.min(foreground, behind) + 0.05)};
      }));
    })()`, returnByValue: true,
  });
  assert.ok(!contrast.exceptionDetails, JSON.stringify(contrast.exceptionDetails));
  assert.ok(contrast.result.value.length > 30, 'contrast check missed page content');
  for (const sample of contrast.result.value) assert.ok(sample.ratio >= 4.5, `low text contrast: ${JSON.stringify(sample)}`);

  await client.send("Runtime.evaluate", { expression: "document.getElementById('collapse-feedback').click()" });
  await client.send("Emulation.setEmulatedMedia", { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  const motion = await client.send("Runtime.evaluate", { expression: "getComputedStyle(document.documentElement).scrollBehavior", returnByValue: true });
  assert.equal(motion.result.value, 'auto', 'reduced motion must disable smooth scrolling');
  await client.send("Runtime.evaluate", { expression: "document.body.tabIndex = -1; document.body.focus(); document.body.removeAttribute('tabindex')" });
  const key = async (name, code) => {
    for (const type of ['keyDown', 'keyUp']) await client.send('Input.dispatchKeyEvent', { type, key: name, code: name, windowsVirtualKeyCode: code });
  };
  await key('Tab', 9);
  const skip = await client.send('Runtime.evaluate', {
    expression: "({skip: document.activeElement.classList.contains('skip-link'), top: document.activeElement.getBoundingClientRect().top, scrollY, tag: document.activeElement.tagName, id: document.activeElement.id})", returnByValue: true,
  });
  assert.ok(skip.result.value.skip && skip.result.value.top >= 0, `keyboard skip link missing or clipped: ${JSON.stringify(skip.result.value)}`);
  const scrolledSkip = await client.send('Runtime.evaluate', {
    expression: `(() => {
      window.scrollTo({top: 200, behavior: 'instant'});
      const rect = document.activeElement.getBoundingClientRect();
      return {top: rect.top, bottom: rect.bottom, viewport: innerHeight};
    })()`, returnByValue: true,
  });
  assert.ok(scrolledSkip.result.value.top >= 0 && scrolledSkip.result.value.bottom <= scrolledSkip.result.value.viewport,
    `focused skip link leaves viewport during scrolling: ${JSON.stringify(scrolledSkip.result.value)}`);
  await key('Enter', 13);
  const skipped = await client.send('Runtime.evaluate', { expression: "document.activeElement.id", returnByValue: true });
  assert.equal(skipped.result.value, 'install', 'skip link did not focus downloads');
  await key('Tab', 9); // Tested-scope link in the public-test notice.
  await key('Tab', 9); // First package download.
  const focus = await client.send('Runtime.evaluate', {
    expression: "({href: document.activeElement.href, outline: getComputedStyle(document.activeElement).outlineStyle, width: parseFloat(getComputedStyle(document.activeElement).outlineWidth)})", returnByValue: true,
  });
  assert.equal(focus.result.value.href, expectedDownloads[0]);
  assert.ok(focus.result.value.outline !== 'none' && focus.result.value.width >= 2, 'download keyboard focus is invisible');

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

  await client.send('Runtime.evaluate', { expression: "document.querySelector('#feedback-result details').open = true" });
  await readLayout(320); // Expanded form and redacted preview must also fit.

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

  await client.send('Emulation.setScriptExecutionDisabled', { value: true });
  await client.send('Page.reload', { ignoreCache: true });
  let noScriptReady = false;
  for (let attempt = 0; attempt < 100 && !noScriptReady; attempt += 1) {
    const state = await client.send('Runtime.evaluate', {
      expression: "document.readyState === 'complete' && !window.LfsFeedback && document.querySelectorAll('img').length > 0 && [...document.images].every(img => img.complete && img.naturalWidth > 0)", returnByValue: true,
    });
    noScriptReady = Boolean(state.result.value);
    if (!noScriptReady) await new Promise(resolvePromise => setTimeout(resolvePromise, 50));
  }
  assert.ok(noScriptReady, 'no-JavaScript page or community icon did not load');
  await readLayout(390);
  console.log("[PASS] browser: 320–1440px downloads, 2x reflow, 200% text, contrast, keyboard, no-JS, and safe feedback handoff");
} finally {
  if (client) client.close();
  browser.kill("SIGTERM");
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
  if (browser.exitCode === null) browser.kill("SIGKILL");
  await rm(profile, { recursive: true, force: true });
}
