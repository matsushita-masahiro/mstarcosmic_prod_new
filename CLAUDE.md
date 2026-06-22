# mstarcosmic_prod_new

予約・スケジュール管理サービス。初期ローンチから約10年。
medirosa_app に対して /api/v1/* で API を提供する本体（連携全体は親 CLAUDE.md 参照）。

## 重要な前提

- 10年もので、意図不明なレガシー実装が存在しうる。
  変更前に必ず該当箇所の影響範囲を確認し、不明点は質問すること。
- `/api/v1/*` は medirosa が依存する公開契約。破壊的変更は事前承認必須。

## 技術スタック

- Ruby: 3.2.2 / Rails: ~> 8.0.2
- DB: development/test は sqlite3、**production は pg（PostgreSQL）**
- 認証: devise（+ bcrypt, devise-i18n）
- API/CORS: rack-cors
- ストレージ: carrierwave + fog-aws
- 非同期/キャッシュ: solid_queue, solid_cache, solid_cable
- デプロイ: Heroku（mstarcosmic-prod, mstarcosmic-staging）。
  GitHub への push で staging に自動デプロイ。Kamal は未使用（gem に残るのみ）。
- その他: recaptcha, meta-tags, seed-fu, jp_prefecture, dotenv-rails ほか

## API 構成（config/routes.rb / app/controllers/api/v1/）

- ReservesController … index / show / create / update（予約 CRUD）
- SchedulesController#index
- StaffsController#index
- StaffMachineRelationsController#index
- UsersController#find_or_register
- base_controller … Bearer API_KEY を secure_compare で検証、失敗で 401

### UsersController#find_or_register の業務ロジック（重要）

- email 必須。
- 該当ユーザーなし → user_type "12" で新規作成。
  password 未提供なら "medirosa" をデフォルト。skip_confirmation! があれば実行。
- 既存で user_type "11" かつ registration_status false → user_type を "12" に更新。
- それ以外の既存 → registration_status を true に（未設定時）。
- ※"12" は medirosa 経由ユーザーを表す区分。数値の意味をここで保持しておくこと。

## 触る前にやること

新しい作業に入る前に、関連モデル・コントローラを読んでから着手する。
コード変更前に方針を提示し、特に以下は承認を取る。

- ReservesController#create / #update … 本番予約データに直結
- UsersController#find_or_register … ユーザー作成・状態変更を伴う
- config/initializers/cors.rb（ALLOWED_ORIGINS）… API アクセス制御の要

## 開発

- 起動: bin/rails s -p 3000（Procfile.dev は web + css watch）
- 認証テスト: 未認証で /api/v1/staffs を叩き 401 が返ることを確認

## ブランチ運用・デプロイ

- 個人開発。**ブランチは切らず main に直接修正・コミットする。**
- `git add → git commit → git push` で GitHub に push すると、
  **自動で Heroku の staging にデプロイされる**（GitHub 連携の自動デプロイ）。
- Kamal は Gemfile に残っているが**実際には使っていない**。デプロイは Heroku。
  Kamal 前提のコマンドや設定を提案しないこと。
