(function () {
  "use strict";

  var INTERVAL = 4500;

  function init(root) {
    var track = root.querySelector(".gl-slides");
    var tabs = root.querySelectorAll(".gl-tab");
    var count = tabs.length;
    var index = 0;
    var timer = null;
    var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function goTo(n, user) {
      index = (n + count) % count;
      track.style.transform = "translateX(-" + index * 100 + "%)";
      for (var j = 0; j < count; j++) {
        var active = j === index;
        tabs[j].classList.toggle("is-active", active);
        tabs[j].setAttribute("aria-selected", active ? "true" : "false");
      }
      if (user) restart();
    }

    function start() {
      if (reduced || timer) return;
      timer = setInterval(function () { goTo(index + 1); }, INTERVAL);
    }

    function stop() {
      clearInterval(timer);
      timer = null;
    }

    function restart() {
      stop();
      start();
    }

    for (var i = 0; i < count; i++) {
      tabs[i].addEventListener("click", goTo.bind(null, i, true));
    }
    root.addEventListener("mouseenter", stop);
    root.addEventListener("mouseleave", start);
    root.addEventListener("focusin", stop);
    root.addEventListener("focusout", start);
    root.addEventListener("keydown", function (e) {
      if (e.key === "ArrowLeft") goTo(index - 1, true);
      if (e.key === "ArrowRight") goTo(index + 1, true);
    });

    goTo(0);
    start();
  }

  document.addEventListener("DOMContentLoaded", function () {
    var roots = document.querySelectorAll(".gl-carousel");
    for (var i = 0; i < roots.length; i++) init(roots[i]);
  });
})();
