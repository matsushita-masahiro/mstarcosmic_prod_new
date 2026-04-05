# API 実装ガイド

## 概要

mstarcosmic アプリに API を実装し、別ドメインの medirosa.jp から DB を閲覧・操作する構成。

```
[medirosa.jp (port 3001)] --HTTPS/API Key--> [mstarcosmic (port 3000)] ---> [PostgreSQL (本番: Heroku)]
```

---

## 1. このアプリ（mstarcosmic）側 — 実装済み

### 追加した Gem

```ruby
# Gemfile
gem 'rack-cors'
```

### 作成したファイル

| ファイル | 役割 |
|---|---|
| `config/initializers/cors.rb` | CORS 設定（許可するオリジン） |
| `app/controllers/api/v1/base_controller.rb` | API キー認証の共通処理 |
| `app/controllers/api/v1/reserves_controller.rb` | 予約の CRUD |
| `app/controllers/api/v1/schedules_controller.rb` | スケジュール閲覧 |
| `app/controllers/api/v1/staffs_controller.rb` | スタッフ閲覧 |
| `app/controllers/api/v1/staff_machine_relations_controller.rb` | スタッフ×マシン閲覧 |
| `app/controllers/api/v1/reserve_algorithms_controller.rb` | 予約アルゴリズム閲覧 |
| `app/controllers/api/v1/machine_schedules_controller.rb` | マシンスケジュール閲覧 |

### API エンドポイント

```
GET    /api/v1/reserves                 # 予約一覧（?date=2026-04-01 でフィルタ可）
GET    /api/v1/reserves/:id             # 予約詳細
POST   /api/v1/reserves                 # 予約作成
PATCH  /api/v1/reserves/:id             # 予約更新

GET    /api/v1/schedules                # スケジュール一覧（?date= でフィルタ可）
GET    /api/v1/staffs                   # スタッフ一覧
GET    /api/v1/staff_machine_relations  # スタッフ×マシン関連
GET    /api/v1/reserve_algorithms       # 予約アルゴリズム設定
GET    /api/v1/machine_schedules        # マシンスケジュール（?date= でフィルタ可）
```

### 認証

リクエストヘッダーに API キーを付与:

```
Authorization: Bearer <API_KEY>
```

認証なし → 401 Unauthorized

### 環境変数（.env）

```
API_KEY="<ランダムな文字列>"
ALLOWED_ORIGINS="http://localhost:3001"
```

---

## 2. medirosa.jp 側 — これから実装

### 開発環境の準備

```bash
# 別ディレクトリに新規 Rails アプリを作成
cd ~/Desktop/kiro/
rails new medirosa
cd medirosa
```

Kiro は別ウィンドウで `~/Desktop/kiro/medirosa/` を開く。

### API クライアントの実装例

medirosa 側に API を呼ぶクラスを作る:

```ruby
# app/services/mstarcosmic_api.rb
class MstarcosmicApi
  BASE_URL = ENV.fetch("MSTARCOSMIC_API_URL", "http://localhost:3000")
  API_KEY  = ENV.fetch("MSTARCOSMIC_API_KEY", "")

  def self.connection
    Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{API_KEY}"
    end
  end

  # 閲覧系
  def self.staffs          = connection.get("/api/v1/staffs").body
  def self.schedules(date: nil)
    params = date ? { date: date } : {}
    connection.get("/api/v1/schedules", params).body
  end
  def self.reserves(date: nil)
    params = date ? { date: date } : {}
    connection.get("/api/v1/reserves", params).body
  end
  def self.staff_machine_relations = connection.get("/api/v1/staff_machine_relations").body
  def self.reserve_algorithms      = connection.get("/api/v1/reserve_algorithms").body
  def self.machine_schedules(date: nil)
    params = date ? { date: date } : {}
    connection.get("/api/v1/machine_schedules", params).body
  end

  # 予約作成
  def self.create_reserve(params)
    connection.post("/api/v1/reserves", { reserve: params })
  end

  # 予約更新
  def self.update_reserve(id, params)
    connection.patch("/api/v1/reserves/#{id}", { reserve: params })
  end
end
```

### medirosa 側の Gemfile に追加

```ruby
gem 'faraday'
```

### medirosa 側の .env

```
MSTARCOSMIC_API_URL="http://localhost:3000"
MSTARCOSMIC_API_KEY="77239f2cbaa030c758b681379adfb8c1b125406ec6da0c9946836eaa5a9050fb"
```

### medirosa 側のコントローラー例

```ruby
class ReservesController < ApplicationController
  def new
    @staffs    = MstarcosmicApi.staffs
    @schedules = MstarcosmicApi.schedules(date: params[:date])
  end

  def create
    response = MstarcosmicApi.create_reserve(reserve_params)

    if response.status == 201
      redirect_to complete_path, notice: "予約が完了しました"
    else
      @errors = response.body["errors"]
      render :new
    end
  end

  private

  def reserve_params
    params.require(:reserve).permit(:user_id, :reserved_date, :reserved_space, :staff_id, :machine, :new_customer, :remarks)
  end
end
```

---

## 3. 開発時の起動手順

ターミナル1（mstarcosmic）:
```bash
cd ~/Desktop/kiro/mstarcosmic_prod_new
bin/rails s -p 3000
```

ターミナル2（medirosa）:
```bash
cd ~/Desktop/kiro/medirosa
bin/rails s -p 3001
```

medirosa（port 3001）から mstarcosmic（port 3000）の API を呼ぶ。

---

## 4. 本番デプロイ時の設定

### mstarcosmic 側（Heroku）

```bash
heroku config:set API_KEY="<本番用のランダムな文字列>" -a mstarcosmic-app
heroku config:set ALLOWED_ORIGINS="https://medirosa.jp" -a mstarcosmic-app
```

### medirosa 側

```bash
# デプロイ先に応じて環境変数を設定
MSTARCOSMIC_API_URL="https://<mstarcosmic-app>.herokuapp.com"
MSTARCOSMIC_API_KEY="<本番用のランダムな文字列>"
```

---

## 5. curl での動作確認コマンド

```bash
# 認証テスト（401 が返ること）
curl -s http://localhost:3000/api/v1/staffs

# スタッフ一覧
curl -s -H "Authorization: Bearer <API_KEY>" http://localhost:3000/api/v1/staffs

# 予約作成
curl -s -X POST http://localhost:3000/api/v1/reserves \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"reserve": {"user_id": 1, "reserved_date": "2026-04-01", "reserved_space": 1.0, "staff_id": 1, "machine": "h"}}'

# 予約更新
curl -s -X PATCH http://localhost:3000/api/v1/reserves/1 \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"reserve": {"remarks": "変更テスト"}}'

# 日付フィルタ
curl -s -H "Authorization: Bearer <API_KEY>" "http://localhost:3000/api/v1/reserves?date=2026-04-01"
```
