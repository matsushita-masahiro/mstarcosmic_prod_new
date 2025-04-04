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

$(function () {
  console.log("✅ jQuery is working!");
});



    

// const open = document.getElementById('open');
// const overlay = document.querySelector('.overlay');
// const close = document.getElementById('close');



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
    
    
    $(function() {
      
      
          // console.log("================== schedule check 通過");
           
          // 全選択 --------------------------------------------------------------
          
          $('#all_check').on('click', function() {
            $("input[name='staff[schedule][]").prop('checked', this.checked);
            // console.log("================== all check clicked");
          });
          
          
          // 「全選択」以外のチェックボックスがクリックされたら、
          $("input[name='user[schedule][]']").on('click', function() {
            if ($('#boxes :checked').length == $('#boxes :input').length) {
              // 全てのチェックボックスにチェックが入っていたら、「全選択」 = checked
              $('#all_check').prop('checked', true);
            } else {
              // 1つでもチェックが入っていたら、「全選択」 = checked
              $('#all_check').prop('checked', false);
            }
          });
          
          
          
          // １日選択 --------------------------------------------------------------
          
          
          // 1
          $('#day_allChecked_0').on('click', function() {
            $("input[class='day_check_0']").prop('checked', this.checked);
          });
          
          // 2
          $('#day_allChecked_1').on('click', function() {
            $("input[class='day_check_1']").prop('checked', this.checked);
          });          
          
          // 3
          $('#day_allChecked_2').on('click', function() {
            $("input[class='day_check_2']").prop('checked', this.checked);
          });
          
          // 4
          $('#day_allChecked_3').on('click', function() {
            $("input[class='day_check_3']").prop('checked', this.checked);
          });  
          
          // 5
          $('#day_allChecked_4').on('click', function() {
            $("input[class='day_check_4']").prop('checked', this.checked);
          });          
          
          // 6
          $('#day_allChecked_5').on('click', function() {
            $("input[class='day_check_5']").prop('checked', this.checked);
          });
          
          // 7
          $('#day_allChecked_6').on('click', function() {
            $("input[class='day_check_6']").prop('checked', this.checked);
          });            
          
          
    
       
       
      // access へのスムーススクロール
         $('#access_link').on('click', () => {
          // console.log("============================= access_link click in application.js");
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
