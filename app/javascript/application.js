// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
// application.js
import jQuery from "jquery";
window.$ = window.jQuery = jQuery;
import Rails from "@rails/ujs";
Rails.start();
window.Rails = Rails;  // ← グローバル登録（必要なら）
// あなたのJSたち
import "@hotwired/turbo-rails"
import "controllers"
import "modal"
import "fadein"
import "price_banner"
import "scroll_top"
import "zipcodeAPI"
import "all_schedule_check"
import "tooltip"

$(function () {
  console.log("✅ jQuery is working!");
});




console.log("JavaScript is working!");
$(document).ready(function() { console.log("jQuery is working!"); });

// application.js


    let pagetop = $('#page_top');
    pagetop.hide();
    $(window).scroll(function () {
        if ($(this).scrollTop() > 500) {  //500pxスクロールしたら表示
            pagetop.fadeIn();
        } else {
            pagetop.fadeOut();
        }
    });
    pagetop.click(function () {
       console.log("================== page top clicked");
        $('body,html').animate({
            scrollTop: 0
        }, 700); //0.7秒かけてトップへ移動
        return false;
    });

    
    document.addEventListener("turbo:load", function() {
            // access へのスムーススクロール
            $('#access_link').on('click', () => {
            let speed = 500;
            let href = $(this).attr("href");
            let position = $('#access').offset().top;
            $('body,html').animate({
              scrollTop: position
            }, speed, 'swing');
            $('.overlay').removeClass('show');
            $('.sp-menu > .button').removeClass('hide');
             return false;
          });
    });

    
// modal.js

function closeModal(elem) {
    var modal = document.getElementById('reserveModal');
    
    window.addEventListener('click', function(e) {
      if (e.target == modal) {
        modal.style.display = 'none';
      }
    });
    
    if (elem.className == "close"){
        modal.style.display = 'none';
    }
    
}
