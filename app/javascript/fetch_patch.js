// fetch_patch.js
const originalFetch = window.fetch;
window.fetch = function(url, options = {}) {
  const headers = new Headers(options.headers || {});
  if (headers.get("Accept")?.includes("vnd.turbo-stream.html")) {
    headers.set("Accept", "text/html");
  }
  return originalFetch(url, { ...options, headers });
};
