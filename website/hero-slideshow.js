(() => {
  const carousel = document.querySelector('#hero-showcase');
  if (!carousel) return;
  const image = carousel.querySelector('#hero-image');
  const caption = carousel.querySelector('#hero-caption');
  const rotate = carousel.querySelector('#hero-rotate');
  const status = carousel.querySelector('#hero-status');
  const count = carousel.querySelector('#hero-count');
  const slides = [{src:image.getAttribute('src'), alt:image.alt, caption:caption.textContent},
    ...Array.from(carousel.querySelector('template').content.querySelectorAll('img'), item => ({
      src:item.getAttribute('src'), alt:item.alt, caption:item.dataset.caption,
    }))];
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const canObserve = typeof IntersectionObserver === 'function';
  let paused = motion.matches || Boolean(navigator.connection?.saveData) || !canObserve;
  let visible = false;
  let hovered = false;
  let index = 0;
  let desired = 0;
  let request = 0;
  let manualRequest = false;
  let pointerPaused;
  let timer;

  function suspend() {
    clearTimeout(timer);
    // Scrolling/focus can deliver a late visibility event after an explicit selection.
    if (!manualRequest) { request += 1; desired = index; }
  }
  function schedule() {
    clearTimeout(timer);
    rotate.textContent = paused ? 'Play' : 'Pause';
    rotate.setAttribute('aria-label', paused ? 'Start slideshow' : 'Pause slideshow');
    if (!paused && visible && !hovered && !document.hidden) timer = setTimeout(() => show(1), 7000);
  }
  function pause() {
    paused = true;
    suspend();
    schedule();
  }
  async function show(step, manual = false) {
    clearTimeout(timer);
    const ticket = ++request;
    manualRequest = manual;
    desired = (desired + step + slides.length) % slides.length;
    const next = desired;
    if (manual) { paused = true; schedule(); }
    // A new request may supersede an in-flight image without blanking the last good frame.
    const candidate = new Image();
    candidate.src = slides[next].src;
    let timeout;
    try {
      await Promise.race([
        candidate.decode(),
        new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Image load timed out')), 8000); }),
      ]);
      if (ticket !== request) return;
      image.src = slides[next].src;
      image.alt = slides[next].alt;
      caption.textContent = slides[next].caption;
      count.textContent = `${next + 1} / ${slides.length}`;
      image.getAnimations().forEach(animation => animation.cancel());
      if (!motion.matches) image.animate([{transform:'translateX(6%)',opacity:.4},{transform:'translateX(0)',opacity:1}], {duration:350,easing:'ease-out'});
      index = next;
      status.textContent = manual ? `Photo ${index + 1} of ${slides.length}: ${slides[index].caption}.` : '';
    } catch {
      if (ticket !== request) return;
      paused = true;
      desired = index;
      status.textContent = 'Photo unavailable. Previous image kept. Use the arrows to try again.';
    } finally {
      clearTimeout(timeout);
      if (ticket === request) { manualRequest = false; schedule(); }
    }
  }

  carousel.querySelector('#hero-previous').addEventListener('click', () => show(-1, true));
  carousel.querySelector('#hero-next').addEventListener('click', () => show(1, true));
  // Pointer focus stops rotation before click; preserve the button's pre-focus intent.
  rotate.addEventListener('pointerdown', () => { pointerPaused = paused; });
  rotate.addEventListener('click', event => {
    const start = event.detail && pointerPaused !== undefined ? pointerPaused : paused;
    pointerPaused = undefined;
    if (start) { paused = false; status.textContent = ''; schedule(); }
    else pause();
  });
  carousel.addEventListener('focusin', pause);
  carousel.addEventListener('pointerenter', () => { hovered = true; suspend(); schedule(); });
  carousel.addEventListener('pointerleave', () => { hovered = false; schedule(); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) suspend();
    schedule();
  });
  motion.addEventListener('change', () => {
    if (motion.matches) {
      image.getAnimations().forEach(animation => animation.cancel());
      pause();
    }
  });
  if (canObserve) {
    new IntersectionObserver(entries => {
      visible = entries[0].intersectionRatio >= .5;
      if (!visible) suspend();
      schedule();
    }, {threshold:[0,.5]}).observe(carousel);
  }
  carousel.querySelector('.hero-navigation').hidden = false;
  rotate.hidden = !canObserve;
  count.hidden = false;
  schedule();
})();
