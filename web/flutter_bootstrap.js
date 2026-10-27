{{flutter_js}}
{{flutter_build_config}}

// Loads the game, then fades out the splash from index.html once Flutter has
// drawn its first frame.
(function () {
  const splash = document.getElementById('splash');
  window.addEventListener('flutter-first-frame', function () {
    if (!splash) return;
    splash.classList.add('done');
    setTimeout(function () { splash.remove(); }, 600);
  }, { once: true });
  _flutter.loader.load({
    config: {
      // The engine files are served with the game (same origin), so the page
      // can be cross-origin isolated and the renderer can use threads.
      canvasKitBaseUrl: 'canvaskit/',
    },
  });
})();
