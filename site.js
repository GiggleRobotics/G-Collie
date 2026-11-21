const demo = document.getElementById('demo');
const demoButtons = [...demo.querySelectorAll('[data-show]')];
const states = [
  {computer:'已生成测试报告，12 项中有 2 项失败。', label:'原会话 · Codex', phone:'12 项测试已完成。'},
  {computer:'收到手机补充要求，正在调整报告顺序。', label:'你的补充要求', phone:'把失败的两项放到报告最前面。'},
  {computer:'已更新报告，失败项排在最前面。', label:'报告已更新', phone:'失败项：登录超时、附件预览失败。'}
];

function chooseStep(index) {
  const state = states[index];
  demo.dataset.step = String(index);
  document.getElementById('computer-text').textContent = state.computer;
  document.getElementById('phone-label').textContent = state.label;
  document.getElementById('phone-text').textContent = state.phone;
  for (const [position, button] of demoButtons.entries()) {
    button.setAttribute('aria-pressed', String(position === index));
  }
  document.getElementById('demo-status').textContent = state.computer + state.phone;
}
for (const button of demoButtons) {
  button.addEventListener('click', () => chooseStep(Number(button.dataset.show)));
}

const film = document.getElementById('film');
const video = film.querySelector('video');
document.getElementById('watch-film').addEventListener('click', event => {
  if (typeof film.showModal !== 'function' || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  film.showModal();
  video.play().catch(() => { /* Native controls allow manual playback. */ });
});
document.getElementById('close-film').addEventListener('click', () => film.close());
film.addEventListener('close', () => video.pause());
film.addEventListener('click', event => {
  if (event.target !== film) return;
  const bounds = film.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right ||
      event.clientY < bounds.top || event.clientY > bounds.bottom) film.close();
});
