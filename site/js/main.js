/* ═══════════════════════════════════════════════════
   GraphLink — Site JS
   ═══════════════════════════════════════════════════ */

/* ── Nav scroll effect ─────────────────────────────── */
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.classList.toggle('scrolled', window.scrollY > 20);
}, { passive: true });

/* ── Hero language tabs (Dart / Java) ──────────────── */
document.querySelectorAll('.hero-lang-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const lang = tab.dataset.lang;

    document.querySelectorAll('.hero-lang-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');

    document.querySelectorAll('.output-panel pre[data-lang]').forEach(pane => {
      pane.classList.toggle('active', pane.dataset.lang === lang);
    });

    Prism.highlightAll();
  });
});

/* ── Before/After comparison tabs ──────────────────── */
document.querySelectorAll('.compare-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const target = tab.dataset.target;

    document.querySelectorAll('.compare-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');

    document.querySelectorAll('.compare-group').forEach(g => {
      g.classList.toggle('active', g.id === `compare-${target}`);
    });

    // Re-highlight since Prism may not have run on hidden content
    Prism.highlightAll();
  });
});

/* ── Quick Start tabs ───────────────────────────────── */
document.querySelectorAll('.qs-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const target = tab.dataset.qs;

    document.querySelectorAll('.qs-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');

    document.querySelectorAll('.qs-content').forEach(c => {
      c.classList.toggle('active', c.id === `qs-${target}`);
    });

    Prism.highlightAll();
  });
});

/* ── Copy to clipboard ──────────────────────────────── */
document.querySelectorAll('.copy-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    const text = btn.dataset.copy;
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(() => {
        btn.textContent = 'Copy';
        btn.classList.remove('copied');
      }, 2000);
    } catch {
      // Fallback for older browsers
      const el = document.createElement('textarea');
      el.value = text;
      el.style.position = 'fixed';
      el.style.opacity = '0';
      document.body.appendChild(el);
      el.select();
      document.execCommand('copy');
      document.body.removeChild(el);
      btn.textContent = 'Copied!';
      setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
    }
  });
});

/* ── Highlight everything once DOM+Prism are ready ──── */
document.addEventListener('DOMContentLoaded', () => {
  if (window.Prism) Prism.highlightAll();
});
