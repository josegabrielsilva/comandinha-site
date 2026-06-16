(function () {
  var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  var zoomTriggers = document.querySelectorAll('.media-zoom__trigger');

  if (zoomTriggers.length) {
    var lightbox = document.createElement('div');
    lightbox.className = 'media-lightbox';
    lightbox.hidden = true;
    lightbox.innerHTML =
      '<figure class="media-lightbox__dialog">' +
      '<button type="button" class="media-lightbox__close" aria-label="Fechar">&times;</button>' +
      '<img class="media-lightbox__img" alt="" />' +
      '</figure>';

    document.body.appendChild(lightbox);

    var lightboxImage = lightbox.querySelector('.media-lightbox__img');
    var lightboxClose = lightbox.querySelector('.media-lightbox__close');
    var lightboxDialog = lightbox.querySelector('.media-lightbox__dialog');
    var lastTrigger = null;

    function closeLightbox() {
      lightbox.hidden = true;
      document.body.classList.remove('is-lightbox-open');
      lightboxImage.removeAttribute('src');
      lightboxDialog.classList.remove('media-lightbox__dialog--phone');
      if (lastTrigger) {
        lastTrigger.focus();
        lastTrigger = null;
      }
    }

    function openLightbox(trigger) {
      var figure = trigger.closest('.media-zoom');
      var image = figure && figure.querySelector('img');
      if (!image) return;

      lastTrigger = trigger;
      lightboxImage.src = image.currentSrc || image.src;
      lightboxImage.alt = image.alt;
      lightboxDialog.classList.toggle('media-lightbox__dialog--phone', !!figure.querySelector('.phone'));
      lightbox.hidden = false;
      document.body.classList.add('is-lightbox-open');
      lightboxClose.focus();
    }

    zoomTriggers.forEach(function (trigger) {
      trigger.addEventListener('click', function () {
        openLightbox(trigger);
      });
    });

    lightboxClose.addEventListener('click', closeLightbox);

    lightbox.addEventListener('click', function (event) {
      if (event.target === lightbox) closeLightbox();
    });

    document.addEventListener('keydown', function (event) {
      if (lightbox.hidden) return;
      if (event.key === 'Escape') closeLightbox();
    });
  }

  var revealSections = document.querySelectorAll(
    '.showcase, .features, .onboarding'
  );

  if (revealSections.length) {
    if (prefersReducedMotion) {
      revealSections.forEach(function (section) {
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
          rootMargin: '0px 0px -8% 0px',
          threshold: 0.12,
        }
      );

      revealSections.forEach(function (section) {
        observer.observe(section);
      });
    }
  }
})();
