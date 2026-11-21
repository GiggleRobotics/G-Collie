const picker = document.querySelector('.tutorial-picker');
const tabs = Array.from(picker.querySelectorAll('a'));
const panel = document.querySelector('#tutorial-player');
let tutorial = panel.querySelector('video');
const download = document.querySelector('#tutorial-download');
const title = document.querySelector('#tutorial-name');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let current;

function startTutorial() {
  if (!reducedMotion.matches && !navigator.connection?.saveData) {
    tutorial.play().catch(() => { /* Native controls remain available. */ });
  }
}

function selectTutorial(tab) {
  if (current === tab) return;
  current = tab;
  const label = tab.textContent + ' 首次连接演示';
  for (const item of tabs) {
    const active = item === tab;
    item.setAttribute('aria-selected', String(active));
    item.tabIndex = active ? 0 : -1;
  }
  panel.setAttribute('aria-labelledby', tab.id);
  title.textContent = label;
  download.href = tab.href;
  download.setAttribute('aria-label', '下载' + label);
  if (tutorial.querySelector('source').src !== tab.href) {
    tutorial.pause();
    const next = tutorial.cloneNode(true);
    next.poster = tab.dataset.poster;
    next.querySelector('source').src = tab.href;
    tutorial.replaceWith(next);
    tutorial = next;
  }
  tutorial.setAttribute('aria-label', label);
  const fallback = tutorial.querySelector('a');
  fallback.href = tab.href;
  fallback.textContent = '打开' + label;
}

function tabFromHash() {
  return tabs.find(tab => '#' + tab.id === location.hash);
}

picker.setAttribute('role', 'tablist');
panel.setAttribute('role', 'tabpanel');
for (const tab of tabs) {
  tab.setAttribute('role', 'tab');
  tab.removeAttribute('aria-current');
  tab.setAttribute('aria-controls', panel.id);
  tab.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    if (tab !== current) {
      selectTutorial(tab);
      history.replaceState(null, '', '#' + tab.id);
      startTutorial();
    }
  });
}
picker.addEventListener('keydown', event => {
  const index = tabs.indexOf(document.activeElement);
  if (index < 0) return;
  const destinations = {
    ArrowRight: (index + 1) % tabs.length,
    ArrowLeft: (index + tabs.length - 1) % tabs.length,
    Home: 0,
    End: tabs.length - 1,
  };
  const next = event.key === ' ' ? index : destinations[event.key];
  if (next === undefined) return;
  event.preventDefault();
  tabs[next].focus();
  tabs[next].click();
});
window.addEventListener('hashchange', () => {
  const tab = tabFromHash();
  if (tab && tab !== current) {
    selectTutorial(tab);
    startTutorial();
  }
});
selectTutorial(tabFromHash() || tabs[0]);
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    observer.disconnect();
    startTutorial();
  });
  observer.observe(tutorial);
} else {
  startTutorial();
}
reducedMotion.addEventListener('change', event => {
  if (event.matches) tutorial.pause();
});
