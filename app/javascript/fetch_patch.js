console.log("✅ fetch_patch loaded");

const originalFetch = window.fetch;
window.fetch = function(url, options = {}) {
  const modifiedHeaders = new Headers(options.headers || {});
  const accept = modifiedHeaders.get("Accept");

  if (accept && accept.includes("vnd.turbo-stream.html")) {
    console.log("💥 rewriting Accept: turbo-stream → text/html");
    modifiedHeaders.set("Accept", "text/html");
  }

  return originalFetch(url, {
    ...options,
    headers: modifiedHeaders
  });
};
