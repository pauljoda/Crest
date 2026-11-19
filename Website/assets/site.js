// Scales the drawn product illustrations to their column, and lets the
// colored sections stack as you scroll without hiding any of their content.
(function () {
  var root = document.documentElement;
  root.classList.add("js");

  var fits = Array.prototype.slice.call(document.querySelectorAll(".fit"));
  function scaleFits() {
    fits.forEach(function (fit) {
      var width = parseFloat(getComputedStyle(fit).getPropertyValue("--w"));
      if (width > 0) fit.style.setProperty("--s", (fit.clientWidth / width).toFixed(4));
    });
  }

  // A sticky card taller than the window would have its end covered by the
  // next card, so a tall card sticks only once its bottom is in view.
  var stacks = Array.prototype.slice.call(document.querySelectorAll(".stack-sticky"));
  function placeStacks() {
    var view = window.innerHeight;
    stacks.forEach(function (card) {
      var top = parseFloat(card.getAttribute("data-top")) || 16;
      card.style.top = Math.min(top, view - card.offsetHeight) + "px";
    });
  }

  function layout() {
    scaleFits();
    placeStacks();
  }

  if ("ResizeObserver" in window) {
    var observer = new ResizeObserver(layout);
    fits.concat(stacks).forEach(function (element) { observer.observe(element); });
  }
  window.addEventListener("resize", layout);
  layout();
})();
