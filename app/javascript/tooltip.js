// app/javascript/controllers/tooltip.js
// console.log("tooltip.js");

// app/javascript/tooltip.js
document.addEventListener("turbo:load", function() {
  var tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]');
  tooltipElements.forEach(function (element) {
    new bootstrap.Tooltip(element); // ここでツールチップを初期化
  });
});

