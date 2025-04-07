document.addEventListener("turbo:load", () => {
  const postalInput = document.getElementById("metatron_sale_inquiry_postcode");

  if (!postalInput) return;

  const prefectures = {
    "北海道": 1, "青森県": 2, "岩手県": 3, "宮城県": 4, "秋田県": 5,
    "山形県": 6, "福島県": 7, "茨城県": 8, "栃木県": 9, "群馬県": 10,
    "埼玉県": 11, "千葉県": 12, "東京都": 13, "神奈川県": 14, "新潟県": 15,
    "富山県": 16, "石川県": 17, "福井県": 18, "山梨県": 19, "長野県": 20,
    "岐阜県": 21, "静岡県": 22, "愛知県": 23, "三重県": 24, "滋賀県": 25,
    "京都府": 26, "大阪府": 27, "兵庫県": 28, "奈良県": 29, "和歌山県": 30,
    "鳥取県": 31, "島根県": 32, "岡山県": 33, "広島県": 34, "山口県": 35,
    "徳島県": 36, "香川県": 37, "愛媛県": 38, "高知県": 39, "福岡県": 40,
    "佐賀県": 41, "長崎県": 42, "熊本県": 43, "大分県": 44, "宮崎県": 45,
    "鹿児島県": 46, "沖縄県": 47
  };

  const handleZipcodeInput = () => {
    const zipcode = postalInput.value.replace(/[^0-9]/g, "");

    if (zipcode.length === 7) {
      fetch(`https://zipcloud.ibsnet.co.jp/api/search?zipcode=${zipcode}`)
          .then((res) => res.json())
          .then((data) => {
            const errorElement = document.getElementById("zipcode-error");
        
            if (data.results) {
              errorElement.style.display = "none"; // エラー非表示
        
              const result = data.results[0];
              const code = prefectures[result.address1];
              const prefectureSelect = document.getElementById("metatron_sale_inquiry_prefecture_code");
              const cityInput = document.getElementById("metatron_sale_inquiry_address_city");
        
              requestAnimationFrame(() => {
                if (code && prefectureSelect) {
                  prefectureSelect.value = String(code);
                  prefectureSelect.dispatchEvent(new Event("change", { bubbles: true }));
                }
        
                if (cityInput) {
                  cityInput.value = result.address2;
                  cityInput.dispatchEvent(new Event("input", { bubbles: true }));
                }
              });
            } else {
              errorElement.style.display = "block"; // エラー表示
              
                // 入力済みの住所情報をクリア
              const prefectureSelect = document.getElementById("metatron_sale_inquiry_prefecture_code");
              const cityInput = document.getElementById("metatron_sale_inquiry_address_city");
            
              if (prefectureSelect) {
                prefectureSelect.value = "";
                prefectureSelect.dispatchEvent(new Event("change", { bubbles: true }));
              }
            
              if (cityInput) {
                cityInput.value = "";
                cityInput.dispatchEvent(new Event("input", { bubbles: true }));
              }
            }
          })
          .catch(() => {
            alert("住所の取得に失敗しました");
          });

   　 }
  };

  postalInput.addEventListener("blur", handleZipcodeInput);
  postalInput.addEventListener("keyup", handleZipcodeInput); // ← 入力し終わったら即反応！
});
