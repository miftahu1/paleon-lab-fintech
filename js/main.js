/* Tessera Financial — minimal site interactions (no frameworks)
   - mobile nav toggle
   - contact form local validation (no backend, no network)
   - year stamping where needed
*/
(function () {
  "use strict";

  // Mobile navigation toggle
  var toggle = document.getElementById("navToggle");
  var nav = document.getElementById("primaryNav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  // Footer/app year
  var y = document.getElementById("year");
  if (y) y.textContent = new Date().getFullYear();

  // Contact form — purely local acknowledgement, no data leaves the browser
  var form = document.getElementById("contactForm");
  if (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var ok = true;
      var fields = form.querySelectorAll("[required]");
      fields.forEach(function (f) {
        if (!f.value.trim()) {
          ok = false;
          f.setAttribute("aria-invalid", "true");
        } else {
          f.removeAttribute("aria-invalid");
        }
      });
      var email = form.querySelector("#email");
      if (email && email.value && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.value)) {
        ok = false;
        email.setAttribute("aria-invalid", "true");
      }
      var note = document.getElementById("formSuccess");
      if (ok && note) {
        note.classList.add("show");
        form.reset();
        note.scrollIntoView({ behavior: "smooth", block: "center" });
      } else if (note) {
        note.classList.remove("show");
      }
    });
  }
})();
