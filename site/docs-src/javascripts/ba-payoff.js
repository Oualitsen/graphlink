/* ---------------------------------------------------------------------------
   Swaps the "payoff" line under the before/after tabs to match the selected
   language, and re-triggers a fade/slide animation on every tab change.

   Material's tabs are pure CSS (radio inputs), so we listen for `change` on
   the radios belonging to the tab set that contains our .ba-card blocks.
--------------------------------------------------------------------------- */
(function () {
  "use strict";

  var MESSAGES = {
    Dart:
      'No hand-written DTO. No <code>fromJson</code>. No ' +
      '<code>Map&lt;String, dynamic&gt;</code>. Rename a field in the schema, ' +
      'run <code>glink</code>, and the <strong>compiler</strong> — not your ' +
      'users — tells you what broke.',
    Java:
      'No hand-written POJO. No <code>ObjectMapper</code> plumbing. No casting, ' +
      'no generics. Rename a field, run <code>glink</code>, and the ' +
      '<strong>compiler</strong> — not your users — tells you what broke.',
    Kotlin:
      'No hand-written data classes. No response wrappers. No manual ' +
      'deserialization. Rename a field, run <code>glink</code>, and the ' +
      '<strong>compiler</strong> — not your users — tells you what broke.',
    TypeScript:
      'No hand-written <code>interface</code>. No <code>as</code> casts the ' +
      'runtime ignores. Rename a field, run <code>glink</code>, and the ' +
      '<strong>compiler</strong> — not your users — tells you what broke.'
  };

  function init() {
    var payoff = document.getElementById("ba-payoff");
    if (!payoff) return;

    // The before/after tab set is the one whose content holds our .ba-card blocks.
    var targetSet = null;
    document.querySelectorAll(".tabbed-set").forEach(function (set) {
      if (set.querySelector(".ba-card")) targetSet = set;
    });
    if (!targetSet) return;

    function labelFor(input) {
      var lbl = targetSet.querySelector('label[for="' + input.id + '"]');
      return lbl ? lbl.textContent.trim() : null;
    }

    function render(animate) {
      var checked = targetSet.querySelector('input[type="radio"]:checked');
      if (!checked) return;
      var msg = MESSAGES[labelFor(checked)];
      if (!msg) return;
      payoff.innerHTML = msg;
      if (animate) {
        payoff.classList.remove("ba-payoff--enter");
        void payoff.offsetWidth; // force reflow so the animation restarts
        payoff.classList.add("ba-payoff--enter");
      }
    }

    targetSet.querySelectorAll('input[type="radio"]').forEach(function (input) {
      input.addEventListener("change", function () { render(true); });
    });

    render(false); // sync the initial message with the default-selected tab
  }

  // Prefer Material's document$ observable (fires on every page, incl. instant
  // navigation); fall back to a plain DOM-ready hook otherwise.
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(init);
  } else if (document.readyState !== "loading") {
    init();
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
