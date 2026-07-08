(function () {
  'use strict';

  function updateThemeToggleState() {
    var toggle = document.getElementById('theme-toggle');
    if (!toggle) return;
    toggle.setAttribute('aria-pressed', String(document.documentElement.dataset.theme === 'dark'));
  }

  function setTheme(theme) {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem('exportify-theme', theme);
    } catch (e) {
      /* modo privado, ignora */
    }
    updateThemeToggleState();
  }

  function initThemeToggle() {
    var toggle = document.getElementById('theme-toggle');
    if (!toggle) return;
    updateThemeToggleState();
    toggle.addEventListener('click', function () {
      var current = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
      setTheme(current === 'dark' ? 'light' : 'dark');
    });
  }

  function initFullscreenToggle() {
    var toggle = document.getElementById('fullscreen-toggle');
    if (!toggle) return;
    toggle.addEventListener('click', function () {
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else {
        document.documentElement.requestFullscreen();
      }
    });
  }

  function filterItems(term) {
    var container = document.getElementById('search-container');
    if (!container) return;
    var needle = term.trim().toLowerCase();
    container.querySelectorAll('[data-search-text]').forEach(function (el) {
      var haystack = el.dataset.searchText.toLowerCase();
      el.hidden = needle.length > 0 && haystack.indexOf(needle) === -1;
    });
  }

  function initSearch() {
    var input = document.getElementById('search-input');
    if (!input) return;
    var container = document.getElementById('search-container');
    input.hidden = !container;
    if (!container) return;
    input.value = '';
    input.addEventListener('input', function () {
      filterItems(input.value);
    });
  }

  function initGenrePills() {
    var pills = document.querySelectorAll('.genre-pill');
    var input = document.getElementById('search-input');
    pills.forEach(function (pill) {
      pill.addEventListener('click', function () {
        var isActive = !pill.classList.contains('genre-pill--active');
        pills.forEach(function (other) {
          other.classList.remove('genre-pill--active');
        });
        pill.classList.toggle('genre-pill--active', isActive);
        var term = isActive ? pill.dataset.genre : '';
        if (input) input.value = term;
        filterItems(term);
      });
    });
  }

  document.addEventListener('turbo:load', function () {
    initThemeToggle();
    initFullscreenToggle();
    initSearch();
    initGenrePills();
  });
})();
