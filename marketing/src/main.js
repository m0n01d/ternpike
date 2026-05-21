// Smooth scroll for anchor links.
document.querySelectorAll('a[href^="#"]').forEach((a) => {
  a.addEventListener('click', (e) => {
    const target = document.querySelector(a.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth' });
    }
  });
});

// Email-capture feedback. Success/error labels come from data-* attrs so copy
// stays in content.yaml.
const form = document.querySelector('.email-form');
const btn = form && form.querySelector('.email-btn');
const input = form && form.querySelector('.email-input');

if (form && btn && input) {
  const successLabel = form.dataset.successLabel || "You're in";
  const successPlaceholder = form.dataset.successPlaceholder || '';

  btn.addEventListener('click', () => {
    if (input.value.includes('@')) {
      btn.textContent = successLabel;
      btn.classList.add('is-success');
      input.value = '';
      input.placeholder = successPlaceholder;
    } else {
      input.classList.add('is-error');
      setTimeout(() => input.classList.remove('is-error'), 1000);
    }
  });
}
