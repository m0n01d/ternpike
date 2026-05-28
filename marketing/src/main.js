// Home-page OCR demo. Two scans per IP per UTC day, gated by Cloudflare
// Turnstile + a server-side KV counter (see server/scanDemo.js). The
// client downscales the image to keep the base64 well under the Worker's
// 4 MiB cap, then POSTs { turnstileToken, base64, mimeType } and renders
// the parsed fields.
(() => {
  const root = document.querySelector('.ocr-demo');
  if (!root) return;
  const turnstileContainer = root.querySelector('.ocr-turnstile');
  if (!turnstileContainer) return;

  const fileInput = root.querySelector('.ocr-file');
  const preview = root.querySelector('.ocr-preview');
  const dropLabel = root.querySelector('.ocr-drop-label');
  const retryBtn = root.querySelector('.ocr-retry');
  const statusEl = root.querySelector('.ocr-status');
  const resultEl = root.querySelector('.ocr-result');
  const errorEl = root.querySelector('.ocr-error');
  const fields = root.querySelectorAll('.ocr-field');

  const endpoint = root.dataset.endpoint;
  const siteKey = root.dataset.sitekey;
  const errors = {
    rate_limited: root.dataset.errorRateLimit,
    no_receipt: root.dataset.errorNoReceipt,
    too_large: root.dataset.errorTooLarge,
    turnstile: root.dataset.errorTurnstile,
    generic: root.dataset.errorGeneric,
  };

  let turnstileToken = null;
  let widgetId = null;
  let pendingFile = null;

  // Render the Turnstile widget once the script has loaded. With
  // `render=explicit` the global appears asynchronously, so poll briefly.
  const renderTurnstile = () => {
    if (widgetId !== null) return;
    if (!window.turnstile) {
      setTimeout(renderTurnstile, 100);
      return;
    }
    widgetId = window.turnstile.render(turnstileContainer, {
      sitekey: siteKey,
      callback: (token) => {
        turnstileToken = token;
        if (pendingFile) {
          const f = pendingFile;
          pendingFile = null;
          submit(f);
        }
      },
      'error-callback': () => {
        turnstileToken = null;
      },
      'expired-callback': () => {
        turnstileToken = null;
      },
    });
  };
  renderTurnstile();

  const resetTurnstile = () => {
    turnstileToken = null;
    if (widgetId !== null && window.turnstile) {
      window.turnstile.reset(widgetId);
    }
  };

  const setStatus = (text) => {
    statusEl.textContent = text || ' ';
  };

  const resetFields = () => {
    fields.forEach((el) => {
      el.textContent = '—';
    });
  };

  const showError = (key) => {
    errorEl.textContent = errors[key] || errors.generic;
    errorEl.classList.remove('hidden');
    setStatus('');
    retryBtn.classList.remove('hidden');
  };

  const clearOutput = () => {
    errorEl.classList.add('hidden');
    retryBtn.classList.add('hidden');
    resetFields();
  };

  const formatField = (field, value) => {
    if (value == null || value === '') return '—';
    if (field === 'amount') {
      const n = Number(value);
      return Number.isFinite(n) ? '$' + n.toFixed(2) : String(value);
    }
    return String(value);
  };

  const renderResult = (ocr) => {
    fields.forEach((el) => {
      el.textContent = formatField(el.dataset.field, ocr[el.dataset.field]);
    });
    errorEl.classList.add('hidden');
    setStatus('');
    retryBtn.classList.remove('hidden');
  };

  // Downscale + recompress before sending to the server. Mirrors the
  // ladder in src/main.js (Elm-app port handler): initial resize to 1568px
  // on the long edge, then a quality ladder, then dimension shrinking
  // until the base64 string fits the budget. The server enforces 4 MiB.
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

  const submit = async (file) => {
    setStatus(root.dataset.busyLabel);
    clearOutput();
    let down;
    try {
      down = await downscale(file);
    } catch (err) {
      console.error(err);
      showError(err && err.message === 'too-large' ? 'too_large' : 'generic');
      return;
    }
    preview.src = down.dataUrl;
    preview.classList.remove('hidden');
    dropLabel.classList.add('hidden');

    let res;
    try {
      res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          base64: down.base64,
          mimeType: 'image/jpeg',
          turnstileToken,
        }),
      });
    } catch (err) {
      console.error(err);
      showError('generic');
      resetTurnstile();
      return;
    }

    let body = {};
    try {
      body = await res.json();
    } catch {
      // fall through with empty body
    }

    if (res.status === 200 && body.ok && body.ocr) {
      renderResult(body.ocr);
      resetTurnstile();
      return;
    }
    if (res.status === 200 && body.error === 'no_receipt') {
      showError('no_receipt');
      resetTurnstile();
      return;
    }
    if (res.status === 429) {
      showError('rate_limited');
      resetTurnstile();
      return;
    }
    if (res.status === 413) {
      showError('too_large');
      resetTurnstile();
      return;
    }
    if (res.status === 401) {
      showError('turnstile');
      resetTurnstile();
      return;
    }
    showError('generic');
    resetTurnstile();
  };

  fileInput.addEventListener('change', () => {
    const file = fileInput.files && fileInput.files[0];
    if (!file) return;
    if (turnstileToken) {
      submit(file);
    } else {
      // Widget hasn't returned a token yet — stash the file and submit
      // from the Turnstile callback once it arrives.
      pendingFile = file;
      setStatus(root.dataset.busyLabel);
    }
  });

  retryBtn.addEventListener('click', () => {
    fileInput.value = '';
    preview.classList.add('hidden');
    preview.src = '';
    dropLabel.classList.remove('hidden');
    clearOutput();
    setStatus('');
    resetTurnstile();
  });
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
