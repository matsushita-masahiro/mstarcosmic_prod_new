# 本番環境移行手順書

## 前提
- 本番DBはPostgreSQL
- 旧テーブル（reserves, schedules, machine_schedules等）は残したまま並行稼働
- 新テーブル（reservations, staff_schedules, service_unavailabilities等）を追加
- 旧テーブルへの書き込みは自動的に新テーブルにも同期（コールバック）

## 移行手順

### STEP 1: バックアップ（必須）
```bash
# 本番サーバーで実行
pg_dump -U postgres -d mstarcosmic_production > backup_$(date +%Y%m%d_%H%M%S).sql
```

### STEP 2: コードデプロイ
```bash
git add -A
git commit -m "DB刷新: 新テーブル・AvailabilityService・新UI"
git push origin main
# Kamalでデプロイ
kamal deploy
```

### STEP 3: マイグレーション実行
```bash
# 本番サーバーで実行
RAILS_ENV=production bundle exec rails db:migrate
```
これで以下が作成される:
- staffsテーブルに capacity, nomination_fee, assignment_type 列追加
- services テーブル
- staff_services テーブル
- staff_schedules テーブル
- reservations テーブル
- service_unavailabilities テーブル

**旧テーブルは一切変更されない。**

### STEP 4: CSSビルド
```bash
yarn build:css
```

### STEP 5: データ移行
```bash
RAILS_ENV=production bundle exec rails db:migrate_data:all
```
