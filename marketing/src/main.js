// Home-page OCR demo. Visitor uploads a receipt + email; the server runs
// OCR and emails the parsed fields back along with a single-use promo
// code (see server/scanDemo.js). No third-party widget; per-email rate
// limit lives server-side in KV.
(() => {
  const root = document.querySelector('.ocr-demo');
  if (!root) return;

  const fileInput = root.querySelector('.ocr-file');
  const emailInput = root.querySelector('.ocr-email');
  const preview = root.querySelector('.ocr-preview');
  const dropLabel = root.querySelector('.ocr-drop-label');
  const submitBtn = root.querySelector('.ocr-submit');
  const retryBtn = root.querySelector('.ocr-retry');
  const statusEl = root.querySelector('.ocr-status');
  const errorEl = root.querySelector('.ocr-error');
  const idleBlock = root.querySelector('.ocr-idle');
  const sentBlock = root.querySelector('.ocr-sent');
  const sentEmailEl = root.querySelector('.ocr-sent-email');

  const endpoint = root.dataset.endpoint;
  const errors = {
    invalid_email: root.dataset.errorInvalidEmail,
    rate_limited: root.dataset.errorRateLimit,
    no_receipt: root.dataset.errorNoReceipt,
    too_large: root.dataset.errorTooLarge,
    email: root.dataset.errorEmail,
    generic: root.dataset.errorGeneric,
  };
  // Mirror server EMAIL_RE.
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

  let selectedFile = null;

  const setStatus = (text) => {
    statusEl.textContent = text || ' ';
  };

  const showError = (key) => {
    errorEl.textContent = errors[key] || errors.generic;
    errorEl.classList.remove('hidden');
    setStatus('');
    submitBtn.disabled = false;
  };

  const clearError = () => {
    errorEl.classList.add('hidden');
  };

  const showSent = (email) => {
    idleBlock.classList.add('hidden');
    sentBlock.classList.remove('hidden');
    sentEmailEl.textContent = email;
    clearError();
    setStatus('');
  };

  const resetToIdle = () => {
    fileInput.value = '';
    selectedFile = null;
    preview.classList.add('hidden');
    preview.src = '';
    dropLabel.classList.remove('hidden');
    emailInput.value = '';
    sentBlock.classList.add('hidden');
    idleBlock.classList.remove('hidden');
    clearError();
    setStatus('');
    submitBtn.disabled = false;
  };

  // Downscale + recompress before sending. Mirrors the ladder in
  // src/main.js (Elm-app port handler): 1568px on the long edge, then
  // quality ladder 0.85→0.45, then dimension shrink. Server caps 4 MiB.
  const MAX_BASE64_BYTES = 4 * 1024 * 1024;
  const base64Bytes = (dataUrl) => {
    const comma = dataUrl.indexOf(',');
    return comma >= 0 ? dataUrl.length - comma - 1 : dataUrl.length;
  };
  const loadImage = (file) =>
    new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        URL.revokeObjectURL(url);
        resolve(img);
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error('image-load'));
      };
      img.src = url;
    });
  const downscale = async (file) => {
    const img = await loadImage(file);
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('canvas-context');
    const maxDim = 1568;
    const initialScale = Math.min(
      1,
      maxDim / Math.max(img.naturalWidth || img.width, img.naturalHeight || img.height),
    );
    let w = Math.max(1, Math.round((img.naturalWidth || img.width) * initialScale));
    let h = Math.max(1, Math.round((img.naturalHeight || img.height) * initialScale));
    const render = (width, height, quality) => {
      canvas.width = width;
      canvas.height = height;
      ctx.drawImage(img, 0, 0, width, height);
      return canvas.toDataURL('image/jpeg', quality);
    };
    let dataUrl = null;
    let bytes = Infinity;
    for (const q of [0.85, 0.75, 0.65, 0.55, 0.45]) {
      dataUrl = render(w, h, q);
      bytes = base64Bytes(dataUrl);
      if (bytes <= MAX_BASE64_BYTES) break;
    }
    while (bytes > MAX_BASE64_BYTES && Math.max(w, h) > 600) {
      w = Math.max(1, Math.round(w * 0.8));
      h = Math.max(1, Math.round(h * 0.8));
      dataUrl = render(w, h, 0.55);
      bytes = base64Bytes(dataUrl);
    }
    if (bytes > MAX_BASE64_BYTES) throw new Error('too-large');
    const comma = dataUrl.indexOf(',');
    return {
      base64: comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl,
      dataUrl,
    };
  };

  const submit = async () => {
    clearError();
    const email = (emailInput.value || '').trim().toLowerCase();
    if (!EMAIL_RE.test(email)) {
      showError('invalid_email');
      emailInput.focus();
      return;
    }
    if (!selectedFile) {
      // No file picked — flash the drop zone.
      const drop = root.querySelector('.ocr-drop');
      if (drop) {
        drop.classList.add('border-rust');
        setTimeout(() => drop.classList.remove('border-rust'), 800);
      }
      return;
    }

    submitBtn.disabled = true;
    setStatus(root.dataset.busyLabel);

    let down;
    try {
      down = await downscale(selectedFile);
    } catch (err) {
      console.error(err);
      showError(err && err.message === 'too-large' ? 'too_large' : 'generic');
      return;
    }

    let res;
    try {
      res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          base64: down.base64,
          email,
          mimeType: 'image/jpeg',
        }),
      });
    } catch (err) {
      console.error(err);
      showError('generic');
      return;
    }

    let body = {};
    try {
      body = await res.json();
    } catch {
      // body stays empty
    }

    if (res.status === 200 && body.ok) {
      showSent(email);
      return;
    }
    if (res.status === 200 && body.error === 'no_receipt') {
      showError('no_receipt');
      return;
    }
    if (res.status === 400 && body.error === 'invalid_email') {
      showError('invalid_email');
      return;
    }
    if (res.status === 429) {
      showError('rate_limited');
      return;
    }
    if (res.status === 413) {
      showError('too_large');
      return;
    }
    if (res.status === 502 && body.error === 'email') {
      showError('email');
      return;
    }
    showError('generic');
  };

  fileInput.addEventListener('change', () => {
    const file = fileInput.files && fileInput.files[0];
    if (!file) return;
    selectedFile = file;
    clearError();
    // Show a small preview in the drop zone.
    const reader = new FileReader();
    reader.onload = (e) => {
      preview.src = e.target.result;
      preview.classList.remove('hidden');
      dropLabel.classList.add('hidden');
    };
    reader.readAsDataURL(file);
  });

  submitBtn.addEventListener('click', submit);

  retryBtn.addEventListener('click', resetToIdle);
})();

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
