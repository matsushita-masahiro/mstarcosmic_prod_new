console.log("price_banner.js");

document.addEventListener("DOMContentLoaded", () => {
  if (typeof $ !== "undefined") {
    const topBtn = $('.floating');
    const footer = $('#footer');

    // スクロールでボタン表示/非表示
    $(window).on("scroll", function () {
      const documentHeight = $(document).height();
      const scrollPosition = $(window).height() + $(window).scrollTop();
      const footerHeight = footer.innerHeight();

      // フッターにぶつかる時だけabsoluteに切り替え
      if (documentHeight - scrollPosition <= footerHeight) {
        topBtn.css({
          // position: "absolute",
          opacity: 0,
          visibility: "hidden"
        });
      } else {
        topBtn.css({
          position: "fixed",
          bottom: 10
        });
      }

        // ボタンの表示切り替え topBtnで表示されてしまうので強制的に$('.floating')にした
        if ($(this).scrollTop() > 100) {
          $('.floating').css({
            opacity: 1,
            visibility: "visible"
          });
          console.log("fadeIn通過");
        } else {
          $('.floating').css({
            opacity: 0,
            visibility: "hidden"
          });
          console.log("fadeOut通過" + $('.floating').text());
        }
　　　});
      

  } else {
    console.warn("⚠️ jQuery is not defined. Floating button won't work.");
  }
});
