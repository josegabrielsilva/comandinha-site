(function () {
  var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var sections = document.querySelectorAll('.product, .features, .flow');

  if (sections.length) {
    if (prefersReducedMotion) {
      sections.forEach(function (section) {
        section.classList.add('is-visible');
      });
    } else {
      var observer = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add('is-visible');
              observer.unobserve(entry.target);
            }
          });
        },
        {
          root: null,
          rootMargin: '0px 0px -12% 0px',
          threshold: 0.2,
        }
      );

      sections.forEach(function (section) {
        observer.observe(section);
      });
    }
  }

  var statsRoot = document.getElementById('hero-stats');
  if (!statsRoot) return;

  var host = window.location.hostname;
  var isLocal = host === 'localhost' || host === '127.0.0.1';
  var apiBase = isLocal ? 'http://localhost:5148' : 'https://sysmile-api.onrender.com';

  function formatInteger(value) {
    return new Intl.NumberFormat('pt-BR').format(Math.round(value));
  }

  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  function animateCounter(element, target, duration) {
    return new Promise(function (resolve) {
      if (prefersReducedMotion || target <= 0) {
        element.textContent = formatInteger(target);
        resolve();
        return;
      }

      var start = performance.now();

      function frame(now) {
        var progress = Math.min((now - start) / duration, 1);
        var current = Math.round(target * easeOutCubic(progress));
        element.textContent = formatInteger(current);

        if (progress < 1) {
          requestAnimationFrame(frame);
        } else {
          element.textContent = formatInteger(target);
          resolve();
        }
      }

      requestAnimationFrame(frame);
    });
  }

  function revealStats() {
    statsRoot.hidden = false;
    var cards = statsRoot.querySelectorAll('.hero__stat');
    cards.forEach(function (card, index) {
      if (prefersReducedMotion) {
        card.classList.add('is-visible');
        return;
      }

      window.setTimeout(function () {
        card.classList.add('is-visible');
      }, index * 90);
    });
  }

  function loadConfettiScript() {
    return new Promise(function (resolve, reject) {
      if (window.confetti) {
        resolve(window.confetti);
        return;
      }

      var script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.3/dist/confetti.browser.min.js';
      script.async = true;
      script.onload = function () {
        resolve(window.confetti);
      };
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  function celebrate() {
    if (prefersReducedMotion) return;

    loadConfettiScript()
      .then(function (confetti) {
        var burst = function (particleRatio, opts) {
          confetti(
            Object.assign({}, opts, {
              particleCount: Math.floor(180 * particleRatio),
              spread: 72,
              startVelocity: 42,
              scalar: 0.9,
              origin: { y: 0.62 },
            })
          );
        };

        burst(0.28, { origin: { x: 0.18, y: 0.62 } });
        burst(0.28, { origin: { x: 0.82, y: 0.62 } });
        window.setTimeout(function () {
          burst(0.22, { origin: { x: 0.5, y: 0.58 } });
        }, 180);
      })
      .catch(function () {
        /* confetti is optional */
      });
  }

  function applyStats(data) {
    revealStats();

    var counterStats = [
      { key: 'establishments', duration: 1400 },
      { key: 'ordersCompleted', duration: 1800 },
      { key: 'itemsSold', duration: 2000 },
      { key: 'shiftsCompleted', duration: 1600 },
    ];

    var animations = counterStats.map(function (stat) {
      var element = statsRoot.querySelector('[data-stat="' + stat.key + '"]');
      if (!element) return Promise.resolve();
      return animateCounter(element, Number(data[stat.key]) || 0, stat.duration);
    });

    Promise.all(animations).then(celebrate);
  }

  fetch(apiBase + '/public/stats', { method: 'GET' })
    .then(function (response) {
      if (!response.ok) throw new Error('stats unavailable');
      return response.json();
    })
    .then(applyStats)
    .catch(function () {
      if (!isLocal) return;

      applyStats({
        establishments: 142,
        ordersCompleted: 12847,
        itemsSold: 89320,
        shiftsCompleted: 384,
      });
    });
})();
