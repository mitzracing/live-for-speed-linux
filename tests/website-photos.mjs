import assert from 'node:assert/strict';

// Shares the real browser and assets; only long timers are replaced at the clock boundary.
export async function checkWebsitePhotos(client, target, capture) {
  const clock = await client.send('Page.addScriptToEvaluateOnNewDocument', {source:`(() => {
    const set = window.setTimeout.bind(window), clear = window.clearTimeout.bind(window);
    const timers = new Map(); let now = 0, id = -1;
    window.setTimeout = (callback, delay = 0, ...args) => {
      if (delay < 7000) return set(callback, delay, ...args);
      const key = id--; timers.set(key, {at:now + delay, run:() => callback(...args)}); return key;
    };
    window.clearTimeout = key => { if (!timers.delete(key)) clear(key); };
    window.advancePhotoClock = elapsed => {
      const end = now + elapsed;
      for (;;) {
        const next = [...timers].filter(([, t]) => t.at <= end).sort((a,b) => a[1].at-b[1].at)[0];
        if (!next) break;
        now = next[1].at; timers.delete(next[0]); next[1].run();
      }
      now = end;
    };
  })()`});
  const requests = [];
  const listen = event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Network.requestWillBeSent' && /(?:gt3-track|drift-smoke)\.webp/.test(message.params.request.url)) requests.push(message.params.request.url);
  };
  client.socket.addEventListener('message', listen);
  await client.send('Network.enable');
  await client.send('Network.setCacheDisabled', {cacheDisabled:true});
  let sequence = 0;
  const evaluate = async expression => {
    const response = await client.send('Runtime.evaluate', {expression,returnByValue:true,awaitPromise:true,timeout:6000});
    assert.ok(!response.exceptionDetails,JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
  const waitFor = async expression => {
    for (let attempt=0; attempt<100; attempt++) {
      if (await evaluate(expression)) return;
      await new Promise(resolve=>setTimeout(resolve,50));
    }
    throw new Error(`Photo readiness timeout: ${expression}`);
  };
  const settle = () => evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
  const advance = async ms => { await evaluate(`advancePhotoClock(${ms})`); await settle(); };
  const image = "document.querySelector('#hero-image')";
  const state = () => evaluate(`({src:${image}.getAttribute('src'),alt:${image}.alt,caption:document.querySelector('#hero-caption').textContent,count:document.querySelector('#hero-count').textContent,button:document.querySelector('#hero-rotate').getAttribute('aria-label'),status:document.querySelector('#hero-status').textContent})`);
  const shown = name => waitFor(`${image}.getAttribute('src')==='assets/${name}.webp' && ${image}.complete && ${image}.naturalWidth>0`);
  async function navigate(motion = 'reduce', width = 1440) {
    await client.send('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:false});
    await client.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:motion}]});
    const url = new URL(target); url.searchParams.set('photo-check',String(++sequence));
    requests.length = 0;
    await client.send('Page.navigate',{url:url.href});
    await waitFor("document.readyState==='complete' && Boolean(window.LfsFeedback)");
    assert.ok(await evaluate("Boolean(document.querySelector('#hero-next')?.getClientRects().length)"),'hero must provide a visible next-photo control');
    await evaluate('document.fonts.ready.then(()=>true)');
    await shown('pit-lane');
    await settle();
  }
  async function keyClick(id) {
    await evaluate(`document.getElementById('${id}').focus()`);
    await client.send('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,nativeVirtualKeyCode:13,text:'\r',unmodifiedText:'\r'});
    await client.send('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
  }
  async function pointer(id) {
    const point = await evaluate(`(() => {const el=document.getElementById('${id}');el.scrollIntoView({block:'center',behavior:'instant'});const r=el.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()`);
    await client.send('Input.dispatchMouseEvent',{type:'mouseMoved',...point});
    await client.send('Input.dispatchMouseEvent',{type:'mousePressed',...point,button:'left',clickCount:1});
    await client.send('Input.dispatchMouseEvent',{type:'mouseReleased',...point,button:'left',clickCount:1});
  }
  const pointerOut = () => client.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:0,y:0});
  const reveal = async selector => { await evaluate(`document.querySelector('${selector}').scrollIntoView({block:'center',behavior:'instant'})`); await settle(); };
  // Delay completion after a real decode: works for both file:// and HTTP fixtures.
  const delayGT3Decode = () => evaluate(`(() => {
    const decode = HTMLImageElement.prototype.decode;
    HTMLImageElement.prototype.decode = function() {
      const result = decode.call(this);
      if (!this.src.endsWith('/gt3-track.webp')) return result;
      return result.then(() => new Promise(resolve => {
        window.releasePhotoDecode = () => {
          HTMLImageElement.prototype.decode = decode;
          delete window.releasePhotoDecode;
          resolve();
        };
      }));
    };
  })()`);
  try {
    await navigate();
    assert.equal(requests.length,0,'inert hero photos fetched before selection');
    await advance(30000);
    assert.equal((await state()).count,'1 / 3','reduced motion rotated automatically');
    await keyClick('hero-next'); await shown('gt3-track');
    assert.equal((await state()).caption,'GT3 / TRACKSIDE');
    assert.match((await state()).alt,/GT3 RS/);
    assert.equal((await state()).count,'2 / 3');
    assert.ok(await evaluate("!document.querySelector('.hero-photo a,.game-gallery a,.image-credit,.gallery-credits')"),'photo-credit UI remains');
    // Return from another section before explicit selection: late visibility must not cancel it.
    await evaluate("document.querySelector('.hero-actions .text-link').focus()");
    await client.send('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,text:'\r',unmodifiedText:'\r'});
    await client.send('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
    await waitFor("location.hash==='#how-it-works'");
    assert.equal(await evaluate(`${image}.getAnimations().length`),0,'reduced motion animated slide');
    await keyClick('hero-next'); await shown('drift-smoke');
    assert.equal((await state()).caption,'DRIFT / ON CIRCUIT');
    assert.match((await state()).status,/Photo 3 of 3/);
    await keyClick('hero-next'); await shown('pit-lane');
    await keyClick('hero-previous'); await shown('drift-smoke');
    assert.equal(await evaluate('document.activeElement.id'),'hero-previous','photo changes stole focus');
    console.log('[PASS] deferred hero images, native keyboard arrows/wrap, matching alt/caption, no photo-credit UI, section-return selection, reduced-motion stills');

    await navigate('no-preference');
    await advance(6999); assert.equal((await state()).count,'1 / 3');
    await advance(1); await shown('gt3-track');
    assert.equal((await state()).status,'','automatic slides must not announce themselves');
    await pointer('hero-rotate');
    assert.equal((await state()).button,'Start slideshow','pointer focus reversed pause intent');
    await pointerOut(); await reveal('#game-gallery'); await reveal('#hero-showcase');
    await advance(30000); assert.equal((await state()).count,'2 / 3','explicit pause lost after scrolling');
    await keyClick('hero-rotate'); await advance(7000); await shown('drift-smoke');
    await reveal('#game-gallery'); await advance(14000);
    assert.equal((await state()).count,'3 / 3','offscreen carousel kept rotating');
    await reveal('#hero-showcase'); await advance(7000); await shown('pit-lane');
    const center = await evaluate(`(() => {const r=${image}.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()`);
    await client.send('Input.dispatchMouseEvent',{type:'mouseMoved',...center});
    await advance(14000); assert.equal((await state()).count,'1 / 3','hover failed to stop rotation');
    await pointerOut(); await advance(7000); await shown('gt3-track');
    // Visibility is an explicit environment fixture, not a physical background-tab claim.
    await evaluate("Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'))");
    await advance(14000); assert.equal((await state()).count,'2 / 3');
    await evaluate("delete document.hidden;document.dispatchEvent(new Event('visibilitychange'))");
    await advance(7000); await shown('drift-smoke');
    await client.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
    await waitFor("document.querySelector('#hero-rotate').getAttribute('aria-label')==='Start slideshow'");
    await advance(14000); assert.equal((await state()).count,'3 / 3');
    assert.equal(await evaluate(`${image}.getAnimations().length`),0);
    console.log('[PASS] seven-second clock cadence, pointer pause intent, explicit resume, hover/offscreen, simulated hidden document, live reduced motion');

    const saveData = await client.send('Page.addScriptToEvaluateOnNewDocument',{source:"Object.defineProperty(navigator,'connection',{configurable:true,value:{saveData:true}})"});
    await navigate('no-preference'); await advance(30000);
    assert.equal(requests.length,0,'Save-Data fetched rotating photos');
    await keyClick('hero-next'); await shown('gt3-track');
    await client.send('Page.removeScriptToEvaluateOnNewDocument',{identifier:saveData.identifier});
    const noObserver = await client.send('Page.addScriptToEvaluateOnNewDocument',{source:'delete window.IntersectionObserver'});
    await navigate('no-preference'); await advance(30000);
    assert.equal(requests.length,0);
    assert.equal(await evaluate("document.querySelector('#hero-rotate').hidden"),true);
    await keyClick('hero-next'); await shown('gt3-track');
    await client.send('Page.removeScriptToEvaluateOnNewDocument',{identifier:noObserver.identifier});
    console.log('[PASS] Save-Data and missing observer use still/manual defaults');

    await client.send('Network.clearBrowserCache');
    await client.send('Network.setBlockedURLs',{urls:['*gt3-track.webp*']});
    await navigate();
    const height = await evaluate("document.querySelector('.hero-photo').getBoundingClientRect().height");
    await keyClick('hero-next'); await waitFor("document.querySelector('#hero-status').textContent.includes('Photo unavailable')");
    await shown('pit-lane');
    assert.ok(Math.abs(await evaluate("document.querySelector('.hero-photo').getBoundingClientRect().height")-height)<1);
    const failures = requests.length;
    await reveal('#game-gallery'); await reveal('#hero-showcase'); await advance(70000);
    assert.equal(requests.length,failures,'failed slide retried automatically');
    await client.send('Network.setBlockedURLs',{urls:[]});
    await keyClick('hero-next'); await shown('gt3-track');
    console.log('[PASS] failed image retains last frame and size, no retry loop, explicit recovery');

    await client.send('Network.clearBrowserCache');
    await navigate();
    await delayGT3Decode();
    await keyClick('hero-next'); await waitFor("typeof window.releasePhotoDecode==='function'");
    await keyClick('hero-next'); await shown('drift-smoke');
    await evaluate('releasePhotoDecode()');
    await settle(); await shown('drift-smoke');
    console.log('[PASS] late GT3 decode cannot overwrite a newer drift selection');

    await client.send('Network.clearBrowserCache');
    await navigate('no-preference');
    await delayGT3Decode();
    await advance(7000); await waitFor("typeof window.releasePhotoDecode==='function'");
    await pointer('hero-rotate'); await pointerOut();
    await evaluate('releasePhotoDecode()');
    await settle(); await shown('pit-lane');
    assert.equal((await state()).button,'Start slideshow');
    console.log('[PASS] pause cancels an in-flight automatic image change');

    await navigate('no-preference');
    await keyClick('hero-next'); await shown('gt3-track');
    await advance(30000); assert.equal((await state()).count,'2 / 3','manual selection did not pause rotation');
    await navigate('no-preference');
    await evaluate("document.querySelector('#hero-next').focus()");
    await advance(30000); assert.equal((await state()).count,'1 / 3','keyboard focus did not pause rotation');
    await navigate(); await delayGT3Decode();
    await keyClick('hero-next'); await waitFor("typeof window.releasePhotoDecode==='function'");
    await advance(8000);
    assert.match((await state()).status,/Photo unavailable/);
    await shown('pit-lane');
    await evaluate('releasePhotoDecode()'); await settle(); await shown('pit-lane');
    console.log('[PASS] manual selection/focus stop rotation; image deadline retains previous frame after late completion');

    for (const [width,scale] of [[320,1],[390,1],[760,1],[1024,1],[1440,1],[320,2]]) {
      await navigate('reduce',width);
      await evaluate(`document.documentElement.style.fontSize='${scale*100}%'`);
      await reveal('#game-gallery');
      await waitFor("[...document.querySelectorAll('.game-shot img')].every(i=>i.complete&&i.naturalWidth>0)");
      const layout = await evaluate(`(() => {
        const shots=[...document.querySelectorAll('.game-shot')];
        const controls=[...document.querySelectorAll('.hero-control:not([hidden])')];
        return {overflow:document.documentElement.scrollWidth>innerWidth+1,shots:shots.length,
          images:shots.every(s=>{const i=s.querySelector('img');return i.loading==='lazy'&&i.alt&&Math.abs(i.clientWidth/i.clientHeight-16/9)<.02}),
          controls:controls.every(c=>{const r=c.getBoundingClientRect();return r.width>=44&&r.height>=44&&r.left>=0&&r.right<=innerWidth+1}),
          order:document.querySelector('#install').getBoundingClientRect().top<document.querySelector('#game-gallery').getBoundingClientRect().top};})()`);
      assert.ok(!layout.overflow&&layout.images&&layout.controls&&layout.order&&layout.shots===3,JSON.stringify({width,scale,layout}));
      if (scale===1&&[390,1440].includes(width)) {
        await capture(`gallery-${width}`,'#game-gallery');
        for (const name of ['pit-lane','gt3-track','drift-smoke']) {
          await reveal('#hero-showcase'); await shown(name);
          await capture(`hero-${name}-${width}`,'.hero');
          await keyClick('hero-next');
        }
      }
    }
    await reveal('.game-shot img');
    const imageHeight = await evaluate("document.querySelector('.game-shot img').getBoundingClientRect().height");
    await evaluate("document.querySelector('.game-shot img').src='data:image/webp;base64,AA=='");
    await waitFor("document.querySelector('.game-shot img').complete&&document.querySelector('.game-shot img').naturalWidth===0");
    assert.ok(Math.abs(await evaluate("document.querySelector('.game-shot img').getBoundingClientRect().height")-imageHeight)<1,'failed gallery image expands at 200% text');
    console.log('[PASS] gallery loads, 320–1440px/200% reflow, reserved failed-image geometry and controls');

    await client.send('Emulation.setScriptExecutionDisabled',{value:true});
    await client.send('Page.reload',{ignoreCache:true});
    await waitFor("document.readyState==='complete'&&!window.LfsFeedback&&[...document.images].every(i=>i.complete&&i.naturalWidth>0)");
    await shown('pit-lane');
    assert.ok(await evaluate("document.querySelector('.hero-navigation').hidden&&document.querySelector('#hero-rotate').hidden&&document.querySelectorAll('.game-shot img').length===3"));
    console.log('[PASS] no JavaScript retains the first photo, gallery and captions without dead controls');
  } finally {
    client.socket.removeEventListener('message',listen);
    await client.send('Page.removeScriptToEvaluateOnNewDocument',{identifier:clock.identifier});
    await client.send('Network.setBlockedURLs',{urls:[]});
    await client.send('Network.setCacheDisabled',{cacheDisabled:false});
    await client.send('Emulation.setScriptExecutionDisabled',{value:false});
    await client.send('Emulation.setEmulatedMedia',{features:[]});
    await client.send('Emulation.clearDeviceMetricsOverride');
  }
}
