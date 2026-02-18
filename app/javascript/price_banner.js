console.log("price_banner.js loaded");

const initializePriceBanner = () => {
  if (typeof $ !== "undefined") {
    const topBtn = $('.floating');
    const footer = $('#footer');

    console.log("スクロールでボタン表示/非表示 関数の前の前");

    $(document.body).off("scroll.priceBanner").on("scroll.priceBanner", function () {
      const scrollTop = document.scrollingElement.scrollTop;
      const documentHeight = $(document).height();
      const scrollPosition = $(window).height() + scrollTop;
      const footerHeight = footer.innerHeight();

      console.log("スクロールでボタン表示/非表示 関数の前");
      console.log("スクロール量:", scrollTop);

      if (documentHeight - scrollPosition <= footerHeight) {
        topBtn.css({
          opacity: 0,
          visibility: "hidden"
        });
      } else {
        topBtn.css({
          position: "fixed",
          bottom: 10,
          opacity: 1,
          visibility: "visible"
        });
      }

      if (scrollTop > 100) {
        topBtn.css({
          opacity: 1,
          visibility: "visible"
        });
        console.log("fadeIn通過");
      } else {
        topBtn.css({
          opacity: 0,
          visibility: "hidden"
        });
        console.log("fadeOut通過" + topBtn.text());
      }
    });

    console.log("スクロールイベントが登録されました");
  } else {
    console.warn("⚠️ jQuery is not defined. Floating button won't work.");
  }
};

document.addEventListener("turbo:load", initializePriceBanner);
