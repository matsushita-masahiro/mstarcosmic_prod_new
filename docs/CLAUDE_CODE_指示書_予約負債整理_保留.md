# Claude Code 指示書: 予約まわりの負債整理（保留中）

> **この指示書はまだ実行しません。** 作成日 2026-08-08。
> 予約は本番稼働中の中核機能のため、着手のタイミングは別途判断します。
> 実行の合図があるまで着手しないでください。

---

## 0. 前提

### 統合はしない、という判断

`reserves` と `reservations` の統合は調査済みで、**見送りとしました。**

根拠:

- `Reserve` の「指名なし」は `staff_id: 0`、`Reservation` は `nil`。
  Ruby では `0.present?` が `true` になるため、
  `AvailabilityService` の78行目・274行目の判定がそのままでは壊れる。
  可用性計算が壊れると予約が取れなくなる、または二重に取れる
- `Reserve` は30分スロット単位、`Reservation` は予約1件単位。
  `AvailabilityService` の一部ロジックがこの違いを前提にしている
- 変更規模が5〜8ファイル・100〜200行。本番稼働中の予約システムには大きすぎる

したがって以下の構成は**維持します。**

```
入力・更新・削除        →  Reserve
        ↓ sync_group_to_reservations
可用性の計算・週間表示  →  Reservation
API（medirosa から）    →  Reserve
```

### この指示書でやること

統合とは**独立して**直せる負債だけを扱います。既存の挙動は変えません。

---

## 1. 直す対象

### (A) service 変換の重複と不一致 ★最優先

`machine` → `service` の変換が3箇所にあり、**内容が食い違っています。**

| 場所 | `'w'` の変換 | `'o'` の扱い |
|---|---|---|
| `Reserve#sync_group_to_reservations` | `holistic` | `else` で `holistic` |
| `Reserve#remove_from_reservations` | `holistic` | `else` で `holistic` |
| `lib/tasks/migrate_data.rake` | `wellbeing` | `staff_id` で sanmei / seitai / other |

実データには `wellbeing 106件` / `sanmei 49件` が存在します。
移行タスクが作ったものと、その後の同期が作るものとで `service` が変わる状態です。

同期側と削除側で変換が食い違うと、**削除時に対象が見つからず Reservation が残ります。**
実際、2026年分で `Reservation` が `Reserve` より1件多い原因はこれかもしれません。

### (B) else 'holistic' の握りつぶし ★最優先

```ruby
service = case machine
          when 'h' then 'holistic'
          when 'w' then 'holistic'
          when 'e' then 'esute'
          when 'stem' then 'stem'
          when 'seitai' then 'seitai'
          else 'holistic'      # ← ここ
          end
```

未知の `machine` が黙って `holistic` になります。
将来 `machine` に新しい区分を足したとき、**気づかないまま誤ったデータが積もります。**

### (C) rescue の握りつぶし

```ruby
rescue => e
  Rails.logger.warn "Reserve#sync_group_to_reservations: #{e.message}"
end
```

同期の失敗が警告ログに落ちるだけです。
2022年の23件の欠落が長期間気づかれなかったのは、これが理由です。

### (D) sync_to_reservations の空実装

```ruby
after_create :sync_to_reservations   # ← 中身がコメントのみ

def sync_to_reservations
  return if user_id == 0
  return if root_reserve_id.present? && root_reserve_id != id
  # 同じroot_reserve_idのグループを集めて1件のReservationにする
  # ただしcreate直後はroot_reserve_idがまだnilの場合があるので、
  # after_updateでも同期する
end
```

実際の同期は `sync_group_to_reservations` が担っています。
名前が紛らわしく、読む人を必ず迷わせます。

### (E) 到達不能な Reservation 関連ファイル

- `app/helpers/reservations_helper.rb`
- `app/views/reservations/*`

`config/routes.rb` の `resources :reservations` はコメントアウト済みで、
`ReservationsController` も存在しません。

---

## 2. 作業内容

### Step 1: 現状確認（着手前に必ず実行）

```bash
git status                     # クリーンであること
grep -n "case machine" -A 10 app/models/reserve.rb
grep -rn "machine" app/models/reserve.rb lib/tasks/migrate_data.rake | grep -i "when\|case"
grep -rn "reservations_helper\|views/reservations" app/ config/
bin/rails routes | grep -i reservation
```

**`bin/rails routes` に reservations の経路が出た場合は停止して報告してください。**
到達不能という前提が崩れます。

### Step 2: service 変換を1箇所に集約

`app/models/reserve.rb` にクラスメソッドを1つ作り、
3箇所すべてがそれを呼ぶようにしてください。

```ruby
# machine → Reservation.service の変換。
#
# 【重要】この変換は同期（sync_group_to_reservations）と
# 削除（remove_from_reservations）の両方で使う。
# 食い違うと、削除時に対象の Reservation が見つからず残り続ける。
# 変換を足すときは必ずこのメソッドだけを直すこと。
#
# 'w'（Wellbeing）と 'o'（算命学等）は過去に使われていた区分で、
# 2026年以降のデータには存在しない。実データとの整合のため
# 移行タスクと同じ変換を採用する。
SERVICE_BY_MACHINE = {
  "h"      => "holistic",
  "w"      => "wellbeing",
  "e"      => "esute",
  "stem"   => "stem",
  "seitai" => "seitai"
}.freeze

def self.service_for(machine, staff_id = nil)
  ...
end
```

**判断が必要な点があります。**

`'o'` の扱いは、移行タスクでは `staff_id` によって sanmei / seitai / other に
分かれていました。同期側には `'o'` の分岐がありません。

2026年以降 `'o'` は使われていないため、どちらでも実害はありません。
ただし**移行タスクと揃える**方が、過去データとの整合が取れます。
`staff_id` を引数に取る形にして、移行タスク側の分岐を再現してください。

`'w'` を `wellbeing` に変えることで、**今後 `'w'` の予約が作られた場合の
挙動が変わります。** 現状 `'w'` は使われていないので影響はありませんが、
この変更は意図的なものだと分かるようコメントを残してください。

### Step 3: 未知の machine を握りつぶさない

`else 'holistic'` をやめてください。

未知の `machine` が来たときは、

- 例外を投げるのではなく、**`Rails.logger.error` で明示的に記録**する
- `service` は `"other"` にする（`Reservation.service` は `null: false` のため）

例外にすると `rescue` に捕まって結局ログに落ちるだけになり、
かつ Reservation が作られなくなります。
**「作られるが、おかしいと分かる」状態**を目指してください。

```ruby
def self.service_for(machine, staff_id = nil)
  ...
  SERVICE_BY_MACHINE.fetch(machine) do
    Rails.logger.error("[Reserve] 未知の machine: #{machine.inspect} → other として扱います")
    "other"
  end
end
```

### Step 4: rescue を error レベルにする

`sync_group_to_reservations` と `remove_from_reservations` の
`rescue => e` を `Rails.logger.warn` から `Rails.logger.error` に変えてください。

あわせて、**何のレコードで失敗したかを出す**ようにしてください。
現状はメッセージだけで、どの予約が失敗したのか分かりません。

```ruby
rescue => e
  Rails.logger.error(
    "[Reserve##{id}] Reservation同期に失敗: #{e.class}: #{e.message} " \
    "(user_id=#{user_id}, date=#{reserved_date}, machine=#{machine})"
  )
end
```

`rescue` 自体は残してください。同期の失敗で予約作成そのものが
失敗するのは避けたいためです。

### Step 5: sync_to_reservations の空実装を削除

```ruby
after_create :sync_to_reservations   # この行を削除
def sync_to_reservations ... end     # このメソッドを削除
```

**削除前に、本当に呼ばれていないことを確認してください。**

```bash
grep -rn "sync_to_reservations" app/ lib/ test/
```

`sync_parent_group` など似た名前のメソッドがあるので、取り違えないこと。
`sync_group_to_reservations` は**残します。**

### Step 6: 到達不能なファイルの削除

Step 1 で到達不能が確認できた場合のみ。

```bash
git rm app/helpers/reservations_helper.rb
git rm -r app/views/reservations
```

**`app/models/reservation.rb` は削除しないこと。** 現役です。

---

## 3. 確認

```bash
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
```

### 変換の一致を確認する

3箇所が同じ結果を返すことを、テストで固定してください。

```ruby
# test/models/reserve_service_conversion_test.rb
#
# 【なぜ必要か】
# machine → service の変換が同期側と削除側で食い違うと、
# 削除時に対象の Reservation が見つからず残り続ける。
# 過去に実際に食い違っていた（同期は 'w'→holistic、移行タスクは 'w'→wellbeing）。
```

- 既知の `machine` がすべて期待どおりに変換されること
- 未知の `machine` が `"other"` になり、`Rails.logger.error` が呼ばれること
- 実データに存在する `service` の値（holistic / wellbeing / sanmei / seitai /
  esute / stem / other）が、すべて変換の出力として得られること

変異テストもお願いします。`SERVICE_BY_MACHINE` から1つ削ると
対応するテストが落ちること。

### 予約の作成・削除が壊れていないこと

**これが最重要です。** development で以下を確認してください。

- 予約を作成して `Reservation` が作られること
- 2枠連続の予約で `Reservation` が1件だけ作られること
- 予約を削除して `Reservation` も消えること
- 指名なし（`staff_id: 0`）の予約で自動割当が動くこと

---

## 4. やってはいけないこと

- `git push`
- `app/models/reservation.rb` の削除
- `sync_group_to_reservations` の削除
- `AvailabilityService` の変更（統合は見送りと決定済み）
- `rescue` 自体の削除（予約作成が失敗するようになるため）
- 本番・staging DB への書き込み
- 過去データの修正（2022年の23件は放置と決定済み）

---

## 5. 報告に含めること

- Step 1 の実行結果
- 各 Step の変更差分
- `'o'` と `'w'` の変換をどう決めたか、その理由
- テスト結果と変異テストの結果
- 予約の作成・削除の動作確認結果
- 削除したファイル一覧
- 気づいた懸念点

---

## 6. この指示書に含まれない残件

以下は別途検討します。

- **`Schedule` / `StaffSchedule` の並存** — `reserves`/`reservations` と
  同じ構図がスケジュール側にもあります。`AvailabilityService` に
  フォールバック処理が入っています。規模は未調査
- **2022年の23件の欠落** — 実害がないため放置
- **2026年の1件の余剰** — 原因未特定。(A) の修正で再発しなくなる可能性あり
- **施術メモと予約の紐付け** — `Reservation` に紐付ける案があるが保留
