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
  const errorLabel = form.dataset.errorLabel || 'Something went wrong — try again?';
  const originalButtonLabel = btn.textContent;
  const originalPlaceholder = input.placeholder;

  const flashError = () => {
    input.classList.add('is-error');
    setTimeout(() => input.classList.remove('is-error'), 1000);
  };

  btn.addEventListener('click', async () => {
    const email = input.value.trim();
    if (!email.includes('@')) {
      flashError();
      return;
    }
    if (btn.disabled) return;
    btn.disabled = true;
    try {
      const res = await fetch('https://api.ternpike.com/marketing/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      });
      if (!res.ok) throw new Error('waitlist signup failed: ' + res.status);
      btn.textContent = successLabel;
      btn.classList.add('is-success');
      input.value = '';
      input.placeholder = successPlaceholder;
    } catch (err) {
      console.error(err);
      flashError();
      btn.textContent = errorLabel;
      btn.disabled = false;
      setTimeout(() => {
        btn.textContent = originalButtonLabel;
        input.placeholder = originalPlaceholder;
      }, 3000);
    }
  });
}
