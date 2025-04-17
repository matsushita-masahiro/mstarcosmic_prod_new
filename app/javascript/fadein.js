// console.log("fadein.js");
document.addEventListener("DOMContentLoaded", () => {
  if (typeof $ !== "undefined") {
    $(window).on("scroll", function () {
      const windowHeight = $(window).height();
      const scroll = $(window).scrollTop();

      $(".fadein").each(function () {
        const targetPosition = $(this).offset().top;
        if (scroll > targetPosition - windowHeight + 100) {
          $(this).addClass("is-fadein");
        }
      });
    });
  } else {
    console.warn("⚠️ jQuery is not defined in fadein.js");
  }
});
