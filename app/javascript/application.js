import "jquery"; // ✅ ← 必ず入れる（importmapを使用している場合）

import Rails from "@rails/ujs";
Rails.start();
window.Rails = Rails;

import "fetch_patch"
import "@hotwired/turbo-rails"

import "controllers"
import "modal"
import "fadein"
import "price_banner"
import "scroll_top"
import "zipcodeAPI"
import "all_schedule_check"
import "tooltip"
import "recaptcha_reload"
import "calendar"
import "new_staff_schedules"
import "business_trips"

// jQueryの動作確認
document.addEventListener("turbo:load", function () {
  if (typeof $ !== "undefined") {
    console.log("🚀 jQuery is ready!");
  } else {
    console.error("❌ jQuery is not loaded!");
  }

  let pagetop = $('#page_top');
  pagetop.hide();

  $(window).off('scroll.pagetop').on('scroll.pagetop', function () {
    if ($(this).scrollTop() > 500) {
      pagetop.fadeIn();
    } else {
      pagetop.fadeOut();
    }
  });

  pagetop.off('click').on('click', function () {
    console.log("page top clicked");
    $('body,html').animate({ scrollTop: 0 }, 700);
    return false;
  });

  $('#access_link').off('click').on('click', () => {
    let speed = 500;
    let position = $('#access').offset().top;
    $('body,html').animate({ scrollTop: position }, speed, 'swing');
    $('.overlay').removeClass('show');
    $('.sp-menu > .button').removeClass('hide');
    return false;
  });
});
