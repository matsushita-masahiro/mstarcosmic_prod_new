# HANDOFF

今回の権限まわりの修正で見つけたが、**意図的に対応しなかった**既知の問題。
直すときにここを消すこと。

## 1. payments/index.html.erb:17 が user_id nil で落ちる

```erb
<td class="center"><%= User.find_by(id: payment.user_id).name %></td>
```

`find_by` は見つからなければ nil を返すのに、そのまま `.name` を呼んでいる。
`payments.user_id` が nil または存在しない User を指していると 500 になる。

本番の支払いは `complete_cash_payment` / `complete_payment` が
`user_id: current_user.id` で作るため実際には起きない。
テストでは fixture が原因で踏んだ（次項）。

対応するなら `User.find_by(id: payment.user_id)&.name` で足りる。

## 2. payments.yml / coupons.yml が Rails の雛形のまま

`one: {}` / `two: {}` のままなので、`fixtures :all` で
**user_id が nil の Payment が2件**入る。前項のビューがこれで落ちる。

`test/controllers/payments_authorization_test.rb` は setup で
`Payment.delete_all` / `Coupon.delete_all` して回避している。
fixture を実データにするか、空にする（users.yml と同じ扱い）のが本筋。

`test/fixtures/users.yml` は既に空にしてある（コメント参照）。

## 3. users/registrations/edit.html.erb:69 の `== "a"` は "1" の誤記

```erb
<% if current_user.user_type == "a" %>
```

user_type に "a" は存在しないため、この条件は誰にも成立せず、
**Devise 側の登録情報編集画面には user_type の選択欄が描画されていない。**

意図的に未修正。理由は、`users/edit.html.erb:73` に同等の欄が
（正しい `== "1"` で）あり機能は足りているため。
脆弱性修正の最中に user_type の書き換え経路を増やしたくない。

該当行にはその旨のコメントを入れてある。**直すなら意図的な判断として行うこと。**

## 4. users_controller.rb の UserBackup.delete_all で世代が1つしか残らない

`backup_users` は毎回 `UserBackup.delete_all` してから作り直すため、
**バックアップは常に1世代のみ**。さらに `user_backups.created_at` /
`updated_at` は users の値をコピーしているので、
**バックアップを取った時刻がどこにも記録されていない。**

このため「いつ時点のスナップショットか」が判定できず、
user_type の変更履歴を追う用途には使えない（下記「履歴の追跡」参照）。

## 5. reserves_controller.rb:7 の `oniy:` タイプミス

```ruby
before_action :redirect_edit_user, oniy: [:index]
```

`only` ではなく `oniy`。Rails は未知のキーを黙って無視するため、
このフィルタは **index だけでなく全アクションに掛かっている**。
直すと今まで走っていたアクションで挙動が変わる可能性があるため、
影響を確認してから直すこと。

---

## 履歴の追跡について（今回の調査結果）

**user_type の変更履歴は追跡不可能。**

- paper_trail / audited / logidze **いずれも Gemfile に無い**
- schema.rb の全34テーブルに versions / audits 相当のテーブルは無い
- `karte_access_logs` はカルテ閲覧専用で user_type を記録しない
- `users.updated_at` はあらゆる更新で変わるため証拠にならない
- `user_backups` は user_type を持つが、上記4のとおり1世代のみ・取得時刻不明

**Coupon の "used" → "new" 巻き戻しは、時刻と実行者は追跡不可能。
ただし「起きたこと自体」は検出できる。**

`payments_controller#update` は使用時に `status = "used"` と同時に
`remarks` を書き込むが、`#destroy`（使用取消）は `status` を `"new"` に
戻すだけで **`remarks` を消さない**。発行時に `remarks` は設定されない。

したがって以下が「一度使われた後に取り消された回数券」になる。

```sql
SELECT COUNT(*) FROM coupons
WHERE status = 'new' AND remarks IS NOT NULL AND remarks <> '';
```

`updated_at` は最後の変更時刻なので、取消が最後の操作だった場合に限り
取消時刻の目安になる。その後に再度使われていれば上書きされる。
**正規の訂正と不正な水増しを区別する情報は無い。**

---

## 今回対応せず、判断が必要なもの

### complete_payment は動作しない（デッドコード）

`complete_payment` は `session[:pay_type]` を読むが、
**このキーに値を入れている箇所がコードベース上に1つも無い**
（`= nil` の4箇所だけ）。`PayType.find(nil)` で落ちる。

枚数は `coupon_times` が 0 / 5 / 11 のいずれかしか返さないホワイトリストに
なっているため、`complete_cash_payment` にあったような任意枚数の問題は無い。
そのため E の枚数検証はこちらには入れていない。

なお `coupon_times` が返す 11 は、現行の
`ALLOWED_COUPON_COUNTS = [5, 10]` と食い違っている。旧料金体系の名残。

### pay_select_1.html.erb / pay_select_2.html.erb は未使用

どこからも render されていない。参照する `@user_type` は
`pay_select` アクションでコメントアウトされているため、
仮に描画しても落ちる。

`pay_select_1` は `/payments/2/new` のように **PayType の ID** を
`:id` に渡す旧方式で、現行の `pay_select.html.erb` の
**枚数**を渡す方式と意味が違う。同じ URL に別の意味の値が流れる設計なので、
復活させるなら先に整理すること。

### 支払金額がシステム上どこにも記録されていない

現行の購入導線は
`pay_select` → `/payments/{5,10}/new` → `_new_paypal`（「PayPal 工事中、
サロンでのカード支払いをお願いします」）→ `_cash` → `complete_cash_payment`。

`complete_cash_payment` は `Payment.new(user_id: current_user.id)` で作るため、
**`payments.price` は常に nil**、`pay_type` も nil。
決済は店頭で行われ、アプリは回数券の発行のみを担っている。

`payments.price` を使うのは動作しない `complete_payment` だけ。
金額を記録する必要があるかは業務側の判断。
