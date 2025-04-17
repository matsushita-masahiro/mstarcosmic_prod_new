// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
// console.log("📦 application.js loaded");

import jQuery from "jquery";
window.$ = window.jQuery = jQuery;

import Rails from "@rails/ujs";
Rails.start();
window.Rails = Rails;  // ← グローバル登録（必要なら）
import "fetch_patch" // ✅ 必ず turbo-rails より先に入れる
import "@hotwired/turbo-rails"
// あなたのJSたち

import "controllers"
import "modal"
import "fadein"
import "price_banner"
import "scroll_top"
import "zipcodeAPI"
import "all_schedule_check"
import "tooltip"

// $(function () {
//   console.log("✅ jQuery is working!");
// });

// console.log("JavaScript is working!");

// $(document).ready(function () {
//   console.log("jQuery is working!");
// });

let pagetop = $('#page_top');
pagetop.hide();
$(window).scroll(function () {
  if ($(this).scrollTop() > 500) {
    pagetop.fadeIn();
  } else {
    pagetop.fadeOut();
  }
});
pagetop.click(function () {
  console.log("================== page top clicked");
  $('body,html').animate({ scrollTop: 0 }, 700);
  return false;
});

document.addEventListener("turbo:load", function () {
  $('#access_link').on('click', () => {
    let speed = 500;
    let position = $('#access').offset().top;
    $('body,html').animate({ scrollTop: position }, speed, 'swing');
    $('.overlay').removeClass('show');
    $('.sp-menu > .button').removeClass('hide');
    return false;
  });
});

// modal.js
function closeModal(elem) {
  var modal = document.getElementById('reserveModal');

  window.addEventListener('click', function (e) {
    if (e.target == modal) {
      modal.style.display = 'none';
    }
  });

  if (elem.className == "close") {
    modal.style.display = 'none';
  }
}

// 🔥 Turbo fetch を完全 override
// import * as Turbo from "@hotwired/turbo-rails"

// console.log("🔥 Overriding Turbo.fetchWithTurboHeaders");

// Turbo.fetchWithTurboHeaders = function (url, options = {}) {
//   const modifiedHeaders = new Headers(options?.headers || {});
//   const accept = modifiedHeaders.get("Accept");

//   if (accept && accept.includes("vnd.turbo-stream.html")) {
//     console.log("💥 Turbo Accept overridden: turbo-stream → text/html");
//     modifiedHeaders.set("Accept", "text/html");
//   }

//   return fetch(url, {
//     ...options,
//     headers: modifiedHeaders
//   });
// };
