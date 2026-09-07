(() => {
  const video = document.getElementById('installer-demo');
  const poster = document.getElementById('demo-poster');
  const button = document.getElementById('demo-toggle');
  const status = document.getElementById('demo-status');
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const sources = [...video.querySelectorAll('source')];
  const failedSources = new Set();
  let visible = false;
  let userPaused = false;
  let loaded = false;
  let failed = false;
  let request = 0;

  function showPoster() {
    video.hidden = true;
    poster.hidden = false;
  }

  function pause() {
    request += 1;
    video.pause();
    button.textContent = failed ? 'Retry demo' : 'Play demo';
  }

  function failure() {
    failed = true;
    pause();
    showPoster();
    status.textContent = 'Video unavailable. Still preview shown.';
  }

  function play() {
    const attempt = ++request;
    if (!loaded || failed) {
      if (!loaded) sources.forEach(source => { source.src = source.dataset.src; });
      loaded = true;
      failed = false;
      failedSources.clear();
      video.load();
    }
    status.textContent = '';
    const playback = video.play();
    button.textContent = 'Pause demo';
    playback.catch(error => {
      if (attempt !== request || error.name === 'AbortError') return;
      if (error.name === 'NotAllowedError') {
        pause();
        showPoster();
      } else {
        failure();
      }
    });
  }

  function autoplay() {
    if (video.paused && visible && !document.hidden && !motion.matches && !navigator.connection?.saveData && !userPaused && !failed) play();
  }

  video.addEventListener('playing', () => {
    if (video.paused) return;
    video.hidden = false;
    poster.hidden = true;
    button.textContent = 'Pause demo';
  });
  video.addEventListener('pause', () => { button.textContent = failed ? 'Retry demo' : 'Play demo'; });
  video.addEventListener('error', failure);
  // With <source> children, total failure may emit only source errors and leave play() pending.
  sources.forEach(source => source.addEventListener('error', () => {
    if (!loaded) return;
    failedSources.add(source);
    if (failedSources.size === sources.length) failure();
  }));
  button.addEventListener('click', () => {
    if (video.paused) {
      userPaused = false;
      play();
    } else {
      userPaused = true;
      pause();
    }
  });
  motion.addEventListener('change', () => {
    if (motion.matches) {
      pause();
      showPoster();
    } else {
      autoplay();
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) pause();
    else autoplay();
  });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([entry]) => {
      visible = entry.intersectionRatio >= .4;
      if (visible) autoplay();
      else pause();
    }, { threshold: [.4] }).observe(video.parentElement);
  }
  // Until this handler is ready, the still image and direct video link work alone.
  button.hidden = false;
})();
