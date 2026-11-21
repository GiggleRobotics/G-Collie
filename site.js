const gallery = document.querySelector('.film-gallery');
const video = gallery.querySelector('.scene-video');
const scenes = Array.from(gallery.querySelectorAll('input[name="scene"]'));
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const connection = navigator.connection;
let current = scenes.findIndex(scene => scene.checked);
let inView = false;
let userSelected = false;

function displayScene() {
  const scene = scenes[current];
  scene.checked = true;
  video.setAttribute('aria-label', scene.dataset.description);
  const allowMotion = userSelected || (!reducedMotion.matches && !connection?.saveData);
  if (!allowMotion || !inView || document.hidden) {
    video.pause();
    if (!allowMotion) gallery.classList.remove('show-video');
    return;
  }
  if (video.getAttribute('src') !== scene.dataset.src) {
    gallery.classList.remove('show-video');
    video.src = scene.dataset.src;
  }
  video.play().catch(() => {
    // The scene's still frame stays visible if autoplay is unavailable.
  });
}

function selectScene(index, explicit) {
  current = index;
  userSelected = explicit;
  displayScene();
}

for (const [index, scene] of scenes.entries()) {
  scene.addEventListener('change', () => selectScene(index, true));
  scene.addEventListener('click', () => {
    if (index === current && video.paused) selectScene(index, true);
  });
}
video.addEventListener('playing', () => gallery.classList.add('show-video'));
video.addEventListener('error', () => gallery.classList.remove('show-video'));
video.addEventListener('ended', () => selectScene((current + 1) % scenes.length, false));
if ('IntersectionObserver' in window) {
  const visibility = new IntersectionObserver(([entry]) => {
    inView = entry.isIntersecting;
    displayScene();
  });
  visibility.observe(gallery);
} else {
  inView = true;
  displayScene();
}
function applyPreference() {
  userSelected = false;
  displayScene();
}
reducedMotion.addEventListener('change', applyPreference);
connection?.addEventListener?.('change', applyPreference);
document.addEventListener('visibilitychange', displayScene);
