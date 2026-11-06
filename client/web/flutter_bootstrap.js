{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Prudent deliberately has no COEP header, so Flutter uses single-threaded Skwasm.
    // Keep the browser console focused on actionable errors until isolation is adopted.
    suppressMultithreadingWarning: true,
  },
});
