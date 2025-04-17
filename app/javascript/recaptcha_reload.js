document.addEventListener("turbo:load", () => {
  console.log("✅ turbo:load fired");

  const recaptcha = document.querySelector(".g-recaptcha");

  if (!recaptcha) {
    console.warn("⚠️ .g-recaptcha 要素が見つかりません");
    return;
  }

  if (typeof grecaptcha === "undefined") {
    console.warn("⚠️ grecaptcha 未定義、再描画スキップ");
    return;
  }

  grecaptcha.ready(() => {
    console.log("✅ grecaptcha is ready");

    if (recaptcha.innerHTML.trim() === "") {
      console.log("🔄 reCAPTCHA ready → 再描画中");
      grecaptcha.render(recaptcha, {
        sitekey: recaptcha.dataset.sitekey
      });
    } else {
      console.log("✅ reCAPTCHA は既に描画済みまたは要素なし");
    }
  });
});
