// console.log("scroll_top.js");

document.addEventListener("DOMContentLoaded", () => {
  if (typeof $ !== "undefined") {
    const pagetop = $('.page_top');
    pagetop.hide();

    // スクロールして100px超えたら表示
    $(window).on("scroll", function () {
      if ($(this).scrollTop() > 100) {
        pagetop.fadeIn();
      } else {
        pagetop.fadeOut();
      }
    });

    // ページトップに戻るアニメーション
    pagetop.on("click", function () {
      console.log("================== page top clicked");
      $('html, body').animate({ scrollTop: 0 }, 500);
      return false;
    });
  } else {
    console.warn("⚠️ jQuery is not defined. page_top won't work.");
  }
});
