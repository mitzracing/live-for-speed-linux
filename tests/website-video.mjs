import assert from "node:assert/strict";

// Shares the existing browser process and static-site builder; no second harness.
export async function checkWebsiteVideo(client, target, capture) {
  await client.send('Network.enable');
  await client.send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 700, deviceScaleFactor: 1, mobile: false});
  const requests = [];
  const recordRequest = event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Network.requestWillBeSent' && /installer-demo\.(webm|mp4)/.test(message.params.request.url)) requests.push(message.params.request.url);
  };
  client.socket.addEventListener('message', recordRequest);
  async function evaluate(expression) {
    const response = await client.send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true, timeout: 5000});
    assert.ok(!response.exceptionDetails, JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  async function waitFor(expression) {
    for (let attempt = 0; attempt < 100; attempt++) {
      if (await evaluate(expression)) return;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw new Error(`Timed out: ${expression}`);
  }
  async function navigate() {
    await client.send('Page.navigate', {url: target});
    await waitFor("document.readyState === 'complete' && Boolean(window.LfsFeedback)");
    assert.ok(await evaluate("Boolean(document.querySelector('#installer-demo'))"), 'installer video missing from website');
    await evaluate('document.fonts.ready.then(() => true)');
  }
  async function motion(value) {
    await client.send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-reduced-motion', value}]});
  }
  async function reveal() {
    await evaluate("document.querySelector('.demo-frame').scrollIntoView({block: 'center', behavior: 'instant'})");
  }
  async function toggle() {
    await evaluate("document.querySelector('#demo-toggle').focus()");
    await client.send('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r'});
    await client.send('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13});
  }
  const video = "document.querySelector('#installer-demo')";
  const poster = "document.querySelector('#demo-poster')";
  const button = "document.querySelector('#demo-toggle')";
  try {
    await motion('no-preference');
    await client.send('Emulation.setDeviceMetricsOverride', {width:1440,height:1600,deviceScaleFactor:1,mobile:false});
    await navigate();
    assert.ok(await evaluate(`[...document.querySelectorAll('figure > figcaption')].every(caption => caption === caption.parentElement.firstElementChild || caption === caption.parentElement.lastElementChild)`), 'figure caption must be first or last child');
    await waitFor(`${video}.currentTime > .15 && !${video}.paused && ${poster}.hidden`);
    console.log('[PASS] cold initial viewport with visible demo starts playback');
    await client.send('Emulation.setDeviceMetricsOverride', {width:1440,height:700,deviceScaleFactor:1,mobile:false});
    requests.length = 0;
    await navigate();
    assert.ok(await evaluate(`document.fonts.check('600 32px "Space Grotesk"') && [...document.fonts].some(face => face.family.includes('Space Grotesk') && face.status === 'loaded')`), 'local heading font did not load');
    assert.equal(await evaluate(`${video}.currentSrc`), '', 'offscreen video eagerly loads');
    assert.equal(requests.length, 0, 'offscreen video requests media bytes');
    await reveal();
    await waitFor(`${video}.currentTime > .15 && !${video}.paused`);
    const decoded = await evaluate(`({width:${video}.videoWidth,height:${video}.videoHeight,duration:${video}.duration,muted:${video}.muted,loop:${video}.loop,frames:${video}.getVideoPlaybackQuality().totalVideoFrames,src:${video}.currentSrc})`);
    assert.equal(decoded.width, 1240); assert.equal(decoded.height, 1200);
    assert.ok(decoded.duration > 10.4 && decoded.duration < 10.6 && decoded.muted && decoded.loop && decoded.frames > 0);
    assert.ok(decoded.src.endsWith('.webm'));
    assert.equal(await evaluate(`${poster}.hidden`), true);
    const control = await evaluate(`(() => {const b=${button},r=b.getBoundingClientRect();return {width:r.width,height:r.height,controls:b.getAttribute('aria-controls'),visible:r.top>=0&&r.bottom<=innerHeight}})()`);
    assert.ok(control.width >= 44 && control.height >= 44);
    assert.equal(control.controls, 'installer-demo');
    await toggle(); await waitFor(`${video}.paused && ${button}.textContent.includes('Play')`);
    const pausedTime = await evaluate(`${video}.currentTime`);
    await evaluate("scrollTo({top:0,behavior:'instant'})");
    await new Promise(resolve => setTimeout(resolve, 120));
    await reveal(); await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal(await evaluate(`${video}.currentTime`), pausedTime, 'explicit pause was overridden by scrolling');
    await toggle(); await waitFor(`!${video}.paused`);
    await evaluate(`${video}.currentTime = ${video}.duration - .15`);
    await waitFor(`${video}.currentTime < 2 && !${video}.paused`);
    await evaluate("scrollTo({top:0,behavior:'instant'})");
    await waitFor(`${video}.paused`);
    await reveal(); await waitFor(`!${video}.paused`);
    await motion('reduce');
    await waitFor(`${video}.paused && ${video}.hidden && !${poster}.hidden`);
    console.log('[PASS] real WebM decode, muted looping, keyboard pause/resume, explicit pause retained, offscreen pause/resume, live reduced-motion change');

    await navigate();
    const reducedStart = requests.length;
    await reveal(); await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal(await evaluate(`${video}.currentSrc`), '');
    assert.equal(requests.length, reducedStart, 'reduced motion fetched video bytes');
    assert.equal(await evaluate(`${poster}.hidden`), false);
    await toggle(); await waitFor(`${video}.currentTime > .15 && !${video}.paused`);
    await toggle(); await waitFor(`${video}.paused`);
    console.log('[PASS] reduced-motion initial poster, no media fetch, deliberate keyboard opt-in');

    await motion('no-preference');
    const saveData = await client.send('Page.addScriptToEvaluateOnNewDocument', {source: "Object.defineProperty(navigator, 'connection', {configurable:true,value:{saveData:true}})"});
    await navigate(); await reveal(); await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal(await evaluate(`${video}.currentSrc`), '', 'simulated Save-Data preference ignored');
    await toggle(); await waitFor(`${video}.currentTime > .15 && !${video}.paused`);
    await client.send('Page.removeScriptToEvaluateOnNewDocument', {identifier: saveData.identifier});
    const noObserver = await client.send('Page.addScriptToEvaluateOnNewDocument', {source: 'delete window.IntersectionObserver'});
    await navigate(); await reveal(); await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal(await evaluate(`${video}.currentSrc`), '', 'missing observer should keep poster by default');
    await toggle(); await waitFor(`${video}.currentTime > .15 && !${video}.paused`);
    await client.send('Page.removeScriptToEvaluateOnNewDocument', {identifier: noObserver.identifier});
    console.log('[PASS] simulated Save-Data and missing observer keep still preview; manual play remains available');

    await client.send('Network.setBlockedURLs', {urls: ['*installer-demo.webm*', '*installer-demo.mp4*']});
    await navigate();
    const height = await evaluate("document.querySelector('.demo-frame').getBoundingClientRect().height");
    await reveal();
    await waitFor(`${button}.textContent.includes('Retry') && !${poster}.hidden && ${video}.hidden`);
    assert.ok(Math.abs(await evaluate("document.querySelector('.demo-frame').getBoundingClientRect().height") - height) < 1, 'media failure shifted layout');
    const failedRequests = requests.length;
    await evaluate("scrollTo({top:0,behavior:'instant'})");
    await new Promise(resolve => setTimeout(resolve, 100));
    await reveal(); await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal(requests.length, failedRequests, 'failed media retries automatically');
    await client.send('Network.setBlockedURLs', {urls: []});
    await toggle(); await waitFor(`${video}.currentTime > .15 && !${video}.paused`);
    assert.equal(await evaluate("document.querySelector('#demo-status').textContent"), '');
    console.log('[PASS] unavailable media keeps poster and dimensions, does not retry itself, explicit retry recovers');

    await client.send('Network.setBlockedURLs', {urls: ['*installer-demo.webm*']});
    await navigate(); await reveal();
    await waitFor(`${video}.currentTime > .15 && !${video}.paused && ${video}.currentSrc.endsWith('.mp4')`);
    assert.equal(await evaluate(`${video}.videoWidth`), 1240);
    console.log('[PASS] blocked WebM falls back to decoded MP4');
    await client.send('Network.setBlockedURLs', {urls: []});

    await motion('reduce');
    for (const [width, textScale] of [[320, 1], [390, 1], [760, 1], [1024, 1], [1440, 1], [320, 2]]) {
      await client.send('Emulation.setDeviceMetricsOverride', {width,height:1000,deviceScaleFactor:1,mobile:false});
      await navigate();
      await evaluate(`document.documentElement.style.fontSize='${textScale * 100}%';document.querySelector('.demo-transcript').open=true`);
      const layout = await evaluate(`(() => {const b=document.querySelector('#demo-toggle').getBoundingClientRect(),a=document.querySelector('.demo-actions a').getBoundingClientRect(),f=document.querySelector('.demo-frame').getBoundingClientRect();return {overflow:document.documentElement.scrollWidth>innerWidth+1,overlap:b.left<a.right&&b.right>a.left&&b.top<a.bottom&&b.bottom>a.top,width:b.width,height:b.height,frameInside:f.left>=0&&f.right<=innerWidth,linkMargin:getComputedStyle(document.querySelector('.demo-actions a')).marginTop,statusFont:getComputedStyle(document.querySelector('#demo-status')).fontSize}})()`);
      assert.ok(!layout.overflow && !layout.overlap && layout.frameInside && layout.width>=44 && layout.height>=44, JSON.stringify({width,textScale,layout}));
      assert.equal(layout.linkMargin,'0px');
      assert.equal(layout.statusFont,`${12 * textScale}px`);
    }
    console.log('[PASS] media controls and expanded transcript reflow at 320–1440px and 200% text; no overlap or horizontal scroll');

    // A warm font can bypass request blocking. Use the owned browser's cache controls,
    // not CSSOM edits: external file:// stylesheets have opaque origins in Chromium.
    await client.send('Network.setCacheDisabled', {cacheDisabled: true});
    await client.send('Network.clearBrowserCache');
    await client.send('Network.setBlockedURLs', {urls: ['*spacegrotesk.woff2*']});
    for (const width of [320, 1440]) {
      await client.send('Emulation.setDeviceMetricsOverride', {width,height:1000,deviceScaleFactor:1,mobile:false});
      await navigate();
      const fallback = await evaluate(`(() => {const h=document.querySelector('h1').getBoundingClientRect();const links=[...document.querySelectorAll('#install a[href*="/releases/download/"]')];return {failed:[...document.fonts].some(face=>face.family.includes('Space Grotesk')&&face.status==='error'),heading:h.width>0&&h.height>0,contained:document.documentElement.scrollWidth<=innerWidth+1,downloads:links.length===2&&links.every(link=>{const r=link.getBoundingClientRect();return r.width>=44&&r.height>=44;})};})()`);
      assert.ok(fallback.failed && fallback.heading && fallback.contained && fallback.downloads, JSON.stringify({width,fallback}));
    }
    await client.send('Network.setBlockedURLs', {urls: []});
    await client.send('Network.setCacheDisabled', {cacheDisabled: false});
    console.log('[PASS] local heading font loads; unavailable font retains visible headings and usable downloads');

    await motion('reduce');
    for (const width of [1440, 390]) {
      await client.send('Emulation.setDeviceMetricsOverride', {width,height:1000,deviceScaleFactor:1,mobile:false});
      await navigate();
      await evaluate('Promise.all([...document.images].map(image=>image.decode())).then(()=>true)');
      await capture(`installer-${width}`, '.product-proof');
    }
    await client.send('Emulation.setScriptExecutionDisabled', {value:true});
    await client.send('Page.reload', {ignoreCache:true});
    await waitFor("document.readyState === 'complete' && !window.LfsFeedback && [...document.images].every(i=>i.complete&&i.naturalWidth>0)");
    assert.equal(await evaluate(`${video}.currentSrc`), '');
    assert.equal(await evaluate(`${poster}.hidden`), false);
    assert.equal(await evaluate(`${button}.hidden`), true);
    assert.ok(await evaluate("Boolean(document.querySelector('a[href=\"assets/installer-demo.mp4\"]'))"));
    assert.ok(await evaluate("document.querySelector('.demo-transcript').textContent.includes('Details')"));
    console.log('[PASS] no JavaScript: still preview, direct video link, readable demo steps');
  } finally {
    client.socket.removeEventListener('message', recordRequest);
    await client.send('Network.setBlockedURLs', {urls: []});
    await client.send('Network.setCacheDisabled', {cacheDisabled: false});
    await client.send('Emulation.setScriptExecutionDisabled', {value: false});
    await client.send('Emulation.setEmulatedMedia', {features: []});
    await client.send('Emulation.clearDeviceMetricsOverride');
  }
}
