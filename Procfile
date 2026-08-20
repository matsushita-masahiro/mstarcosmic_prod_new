# Heroku のプロセス定義。
#
# ── release フェーズ ──────────────────────────
#
# デプロイのたびにマイグレーションを実行する。
# これが無いとスキーマ変更が本番に反映されず、新しいコードだけが動く。
#
# 実際に事故が起きている。2026-08-21、問診票の訂正（版管理）で
# previous_id / revision / purpose を足した版を staging にデプロイしたとき、
# マイグレーションが走らず IntakeSession の enum :purpose がカラムを
# 見つけられず、モデルのロード自体が失敗した
# （Undeclared attribute type for enum 'purpose'）。
# IntakeSession を参照する全画面が 500 になり、手動で
# heroku run bin/rails db:migrate するまで復旧しなかった。
#
# それまで問題にならなかったのは、デプロイがすべてスキーマ無変更だったため。
#
# 【release が失敗するとデプロイは中止される】
# 前のリリースが動き続ける。「マイグレーションは失敗したのに新しいコードが
# 動く」状態にならないので、この挙動は望ましい。
# 裏を返すと、既存データと矛盾するマイグレーション（重複のあるカラムへの
# unique 制約など）を書くとデプロイがブロックされる。
# 制約を足すときは、先に既存データを整えること。
release: bin/rails db:migrate

# ── web ────────────────────────────────────
#
# Procfile が無い間、heroku/ruby buildpack の既定で動いていたコマンドと
# 同一にしてある。既定と違うものを書くと、マイグレーションは走るように
# なってもアプリが起動しない。
#
# 2026-08-21 時点の実測（staging / prod とも同じ）:
#   $ heroku ps --app mstarcosmic-staging
#   === web (Eco): bin/rails server -p ${PORT:-5000} -e $RAILS_ENV (1)
#
# ${PORT:-5000} は既定のままにしている。Heroku は PORT を必ず渡すので
# 実際に 5000 が使われることはないが、既定から変える理由も無い。
web: bin/rails server -p ${PORT:-5000} -e $RAILS_ENV

# worker は置かない。Solid Queue は未整備で、いまは
# config.active_job.queue_adapter = :inline で回避している。
# ワーカーを起こすなら、その設定を外すのが先。
