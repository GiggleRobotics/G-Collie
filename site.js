const gallery = document.querySelector('.film-gallery');
const video = gallery.querySelector('.scene-video');
const poster = gallery.querySelector('.scene-poster');
const caption = gallery.querySelector('#scene-name');
const toggle = gallery.querySelector('.motion-toggle');
const previous = gallery.querySelector('button.previous');
const next = gallery.querySelector('button.next');
const positions = Array.from(gallery.querySelectorAll('.scene-position i'));
const scenes = [
  {caption:'电脑整理报告，手机同步进度并追加要求。', file:'session-sync-preview', poster:'sync-stage', alt:'电脑工作台与手机上的同一份报告'},
  {caption:'手机新建会话并发送任务，电脑同步显示回复。', file:'phone-create-pair', poster:'phone-create-pair', alt:'手机新建的任务出现在电脑工作台'},
  {caption:'另一台电脑通过浏览器追加要求，原电脑继续执行。', file:'computer-pair', poster:'computer-pair', alt:'两台电脑的浏览器显示同一条会话'}
];
const mediaVersion = '?ver=b69dd4d28cf6';
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const connection = navigator.connection;
let current = 0;
let revision = 0;
let inView = false;
let paused = false;
let fallbackTimer;

function prefersStill() {
  return reducedMotion.matches || connection?.saveData;
}

function mediaPath() {
  return './media/' + scenes[current].file + '.mp4' + mediaVersion;
}

function isCurrentSource() {
  return video.currentSrc === new URL(mediaPath(), document.baseURI).href;
}

function syncPlayback() {
  clearTimeout(fallbackTimer);
  const still = prefersStill();
  toggle.hidden = still;
  toggle.dataset.paused = String(paused);
  const action = paused ? '继续演示' : '暂停演示';
  toggle.title = action;
  toggle.setAttribute('aria-label', action);
  if (still || paused || !inView || document.hidden) {
    video.pause();
    if (still) gallery.classList.remove('show-video');
    return;
  }
  const src = mediaPath();
  if (video.getAttribute('src') !== src) {
    video.src = src;
  } else if (video.error) {
    // The user can navigate while the failed clip's matching still is shown.
    fallbackTimer = setTimeout(() => changeScene(1), 5000);
    return;
  }
  const requestedRevision = revision;
  video.play().catch(error => {
    if (requestedRevision === revision && error.name === 'NotAllowedError' && isCurrentSource() && !video.error) {
      paused = true;
      syncPlayback();
    }
  });
}

function changeScene(direction, manual = false) {
  revision++;
  current = (current + direction + scenes.length) % scenes.length;
  const scene = scenes[current];
  clearTimeout(fallbackTimer);
  video.pause();
  // Cancel the old request, including when switching while paused.
  if (video.hasAttribute('src')) {
    video.removeAttribute('src');
    video.load();
  }
  gallery.classList.remove('show-video');
  poster.src = './assets/' + scene.poster + '.webp' + mediaVersion;
  poster.alt = scene.alt;
  caption.setAttribute('aria-live', manual ? 'polite' : 'off');
  caption.textContent = scene.caption;
  gallery.classList.toggle('paired-computers', scene.file === 'computer-pair');
  positions.forEach((mark, index) => mark.classList.toggle('current', index === current));
  syncPlayback();
}

video.addEventListener('playing', () => {
  if (isCurrentSource() && !video.paused && !prefersStill()) gallery.classList.add('show-video');
});
video.addEventListener('ended', () => {
  if (video.ended && isCurrentSource() && !paused && !prefersStill()) changeScene(1);
});
video.addEventListener('error', () => {
  if (!isCurrentSource() || !video.error) return;
  gallery.classList.remove('show-video');
  syncPlayback();
});
previous.hidden = false;
next.hidden = false;
previous.addEventListener('click', () => changeScene(-1, true));
next.addEventListener('click', () => changeScene(1, true));
gallery.addEventListener('keydown', event => {
  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault();
    changeScene(event.key === 'ArrowLeft' ? -1 : 1, true);
  }
});
toggle.addEventListener('click', () => {
  paused = !paused;
  syncPlayback();
});
if ('IntersectionObserver' in window) {
  new IntersectionObserver(([entry]) => {
    inView = entry.isIntersecting;
    syncPlayback();
  }).observe(gallery);
} else {
  inView = true;
  syncPlayback();
}
reducedMotion.addEventListener('change', syncPlayback);
connection?.addEventListener?.('change', syncPlayback);
document.addEventListener('visibilitychange', syncPlayback);
