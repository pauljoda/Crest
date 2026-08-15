const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const nav = document.querySelector('[data-nav]');

function updateNavigation() {
  nav?.classList.toggle('scrolled', window.scrollY > 40);
}

updateNavigation();
window.addEventListener('scroll', updateNavigation, { passive: true });

const reveals = document.querySelectorAll('.reveal');
if (reducedMotion || !('IntersectionObserver' in window)) {
  reveals.forEach((element) => element.classList.add('visible'));
} else {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.14 });
  reveals.forEach((element) => observer.observe(element));
}

const spaceBrowser = document.querySelector('[data-space-browser]');
const spaceBrowserShell = spaceBrowser?.querySelector('.space-browser-shell');
const spaceChoices = [...(spaceBrowser?.querySelectorAll('[data-space-choice]') ?? [])];
const spaceImages = [...(spaceBrowser?.querySelectorAll('[data-space-image]') ?? [])];
const spaceKicker = spaceBrowser?.querySelector('[data-space-kicker]');
const spaceTitle = spaceBrowser?.querySelector('[data-space-title]');
const spaceDetail = spaceBrowser?.querySelector('[data-space-detail]');
const spaceMeta = spaceBrowser?.querySelector('[data-space-meta]');
const spaceContent = {
  work: {
    kicker: 'Work Space · Focused, signed in, ready',
    title: 'One sidebar for the workday.',
    detail: "Work accounts, Launch Atlas, and Monday's tabs stay together. Personal browsing never appears in the same history or session.",
    meta: 'Work accounts · Launch Atlas · Monday overview'
  },
  personal: {
    kicker: 'Personal Space · Warm, familiar, yours',
    title: 'Your weekend has its own place.',
    detail: 'Trips, recipes, reading, and personal sign-ins live behind a different crest—with their own cookies, history, tabs, and passwords.',
    meta: 'Personal accounts · Weekend Plans · A slower Saturday'
  }
};
const spaceOrder = Object.keys(spaceContent);
let activeSpace = spaceOrder[0];
let spaceDragStart;
let spaceWheelLocked = false;

function showSpace(key) {
  if (!Object.hasOwn(spaceContent, key)) return;
  activeSpace = key;
  spaceChoices.forEach((choice) => updateSpaceChoice(choice, key));
  spaceImages.forEach((image) => updateSpaceImage(image, key));
  updateSpaceCopy(spaceContent[key], key);
}

function updateSpaceChoice(choice, key) {
  const selected = choice.dataset.spaceChoice === key;
  choice.classList.toggle('active', selected);
  choice.setAttribute('aria-pressed', String(selected));
}

function updateSpaceImage(image, key) {
  const selected = image.dataset.spaceImage === key;
  image.classList.toggle('active', selected);
  image.setAttribute('aria-hidden', String(!selected));
}

function updateSpaceCopy(content, key) {
  if (spaceKicker) spaceKicker.textContent = content.kicker;
  if (spaceTitle) spaceTitle.textContent = content.title;
  if (spaceDetail) spaceDetail.textContent = content.detail;
  if (spaceMeta) spaceMeta.textContent = content.meta;
}

function stepSpace(direction) {
  const currentIndex = spaceOrder.indexOf(activeSpace);
  const nextIndex = (currentIndex + direction + spaceOrder.length) % spaceOrder.length;
  showSpace(spaceOrder[nextIndex]);
}

function finishSpaceDrag(event) {
  if (!spaceBrowserShell || !spaceDragStart) return;
  if (spaceBrowserShell.hasPointerCapture(event.pointerId)) {
    spaceBrowserShell.releasePointerCapture(event.pointerId);
  }
  const horizontalTravel = event.clientX - spaceDragStart.x;
  const verticalTravel = event.clientY - spaceDragStart.y;
  spaceDragStart = undefined;
  if (Math.abs(horizontalTravel) < 42 || Math.abs(horizontalTravel) < Math.abs(verticalTravel)) return;
  stepSpace(horizontalTravel < 0 ? 1 : -1);
}

spaceChoices.forEach((choice) => {
  choice.addEventListener('click', () => showSpace(choice.dataset.spaceChoice));
});
spaceBrowserShell?.addEventListener('pointerdown', (event) => {
  if (event.pointerType === 'mouse' && event.button !== 0) return;
  spaceDragStart = { x: event.clientX, y: event.clientY };
  spaceBrowserShell.setPointerCapture(event.pointerId);
});
spaceBrowserShell?.addEventListener('pointerup', finishSpaceDrag);
spaceBrowserShell?.addEventListener('pointercancel', () => { spaceDragStart = undefined; });
spaceBrowserShell?.addEventListener('wheel', (event) => {
  const horizontalTravel = Math.abs(event.deltaX) > Math.abs(event.deltaY)
    ? event.deltaX
    : (event.shiftKey ? event.deltaY : 0);
  if (Math.abs(horizontalTravel) < 24 || spaceWheelLocked) return;
  event.preventDefault();
  stepSpace(horizontalTravel > 0 ? 1 : -1);
  spaceWheelLocked = true;
  window.setTimeout(() => { spaceWheelLocked = false; }, 450);
}, { passive: false });
spaceBrowserShell?.addEventListener('keydown', (event) => {
  if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
  event.preventDefault();
  stepSpace(event.key === 'ArrowRight' ? 1 : -1);
});
