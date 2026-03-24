/* ═══════════════════════════════════════════════════
   GraphLink — Documentation JS
   ═══════════════════════════════════════════════════ */

/* ── Copy buttons ───────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
  // Attach copy buttons to all .doc-code blocks
  document.querySelectorAll('.doc-code').forEach(block => {
    const btn = document.createElement('button');
    btn.className = 'doc-copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', () => {
      const code = block.querySelector('pre code') || block.querySelector('pre');
      if (!code) return;
      navigator.clipboard.writeText(code.innerText).then(() => {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
      });
    });
    block.appendChild(btn);
  });

  /* ── Tabs ─────────────────────────────────────────── */
  document.querySelectorAll('.doc-tabgroup').forEach(group => {
    const tabs = group.querySelectorAll('.doc-tab');
    const panels = group.querySelectorAll('.doc-tab-content');
    tabs.forEach((tab, i) => {
      tab.addEventListener('click', () => {
        tabs.forEach(t => t.classList.remove('active'));
        panels.forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        panels[i] && panels[i].classList.add('active');
      });
    });
  });
});
