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

  function initJobModal() {
    var modal = document.getElementById('job-modal');
    if (!modal) return;

    var titleEl = document.getElementById('job-modal__title');
    var formSection = document.getElementById('job-modal__form');
    var urlField = document.getElementById('job-modal__url');
    var urlFieldWrap = document.getElementById('job-modal__url-field');
    var browserFieldWrap = document.getElementById('job-modal__browser-field');
    var browserField = document.getElementById('job-modal__browser');
    var submitBtn = document.getElementById('job-modal__submit');
    var closeBtn = document.getElementById('job-modal__close');
    var progress = document.getElementById('job-modal__progress');
    var errorBox = document.getElementById('job-modal__error');

    var TITLES = { create: 'Nova playlist', retag: 'Regravar tags', sync: 'Sincronizar playlist' };
    var action = null;
    var playlistName = null;
    var pollTimer = null;

    function reset() {
      formSection.hidden = false;
      progress.hidden = true;
      progress.textContent = '';
      errorBox.hidden = true;
      urlField.value = '';
      browserField.value = '';
      submitBtn.disabled = false;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
    }

    function openModal(trigger) {
      action = trigger.dataset.jobTrigger;
      playlistName = trigger.dataset.playlist || null;
      reset();
      titleEl.textContent = TITLES[action] || '';
      urlFieldWrap.hidden = action !== 'create' && trigger.dataset.hasSource === '1';
      browserFieldWrap.hidden = action !== 'create';
      modal.showModal();
    }

    function endpointFor() {
      if (action === 'create') return '/playlists';
      return '/playlists/' + encodeURIComponent(playlistName) + '/' + action;
    }

    function extractPlaylistName(log) {
      var match = log.join('\n').match(/^Output: (.+)$/m);
      if (!match) return null;
      return match[1].trim().split('/').pop();
    }

    function poll(jobId) {
      pollTimer = setInterval(function () {
        fetch('/jobs/' + jobId)
          .then(function (r) { return r.json(); })
          .then(function (data) {
            progress.textContent = data.log.join('\n');
            progress.scrollTop = progress.scrollHeight;

            if (data.status === 'done') {
              clearInterval(pollTimer);
              var name = action === 'create' ? extractPlaylistName(data.log) : playlistName;
              window.location.href = name ? '/playlists/' + encodeURIComponent(name) : '/';
            } else if (data.status === 'error') {
              clearInterval(pollTimer);
              errorBox.hidden = false;
              errorBox.textContent = data.log[data.log.length - 1] || 'Falha desconhecida.';
            }
          });
      }, 1500);
    }

    function submit() {
      submitBtn.disabled = true;

      var params = new URLSearchParams();
      if (!urlFieldWrap.hidden) params.set('url', urlField.value);
      if (action === 'create') params.set('browser', browserField.value);

      fetch(endpointFor(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString()
      })
        .then(function (r) {
          return r.json().then(function (data) {
            if (!r.ok) throw new Error(data.error || 'Falha ao iniciar a ação.');
            return data;
          });
        })
        .then(function (data) {
          formSection.hidden = true;
          progress.hidden = false;
          poll(data.job_id);
        })
        .catch(function (err) {
          errorBox.hidden = false;
          errorBox.textContent = err.message;
          submitBtn.disabled = false;
        });
    }

    document.querySelectorAll('[data-job-trigger]').forEach(function (trigger) {
      trigger.addEventListener('click', function () { openModal(trigger); });
    });

    submitBtn.addEventListener('click', submit);
    closeBtn.addEventListener('click', function () {
      if (pollTimer) clearInterval(pollTimer);
      modal.close();
    });
  }

  document.addEventListener('turbo:load', function () {
    initThemeToggle();
    initFullscreenToggle();
    initSearch();
    initGenrePills();
    initJobModal();
  });
})();
