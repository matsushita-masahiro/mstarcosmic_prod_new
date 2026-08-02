# app/services/karte_storage_key.rb
#
# カルテ関連ファイルの S3 オブジェクトキーを組み立てる。
#
# 出力例:
#   karte/2026/08/user-001447/consent-a1b2c3d4e5f6.png
#   karte/2026/08/user-001447/q1_purpose-9z8y7x6w5v4u.png
#
# 【設計変更の経緯】
# 当初は config/initializers/karte_storage_key.rb で ActiveStorage::Blob の
# key を差し替える方式だったが、Blob のインスタンス内でコードを動かすことに
# 起因する問題が3つ重なったため、Blob の外に出した。
#
#   1. class_eval 内の MINIMUM_TOKEN_LENGTH が初期化子のレキシカルスコープで
#      探索され NameError（前々版）
#   2. prepend + super にしても self[:key] は Blob.new の時点で既に埋まっており、
#      `self[:key] ||=` が短絡して build_karte_key が呼ばれない（前版）
#   3. 強制的に呼んでも format が Kernel#format ではなく
#      ActiveStorage::Blob::Representable#format（引数0個）に解決され ArgumentError
#
# キーを作るのは KarteAttachment だけなので、生成時に key: を明示的に渡せば足りる。
# Blob には触らない。カルテ以外の ActiveStorage 利用への影響もゼロになる。
#
# 【注意】既存の blob のキーは変更されない。
# これを入れる前に保存されたファイルはフラットな配置のまま残る。
module KarteStorageKey
  TOKEN_LENGTH = 12

  class << self
    # 組み立てられない場合は nil を返す。
    # 呼び出し側は nil のとき ActiveStorage 既定のランダムキーに任せる。
    def build(user_id:, label:, at: Time.current)
      label = sanitize(label)
      return nil if user_id.blank? || label.blank?

      Kernel.format(
        "karte/%04d/%02d/user-%06d/%s-%s",
        at.year, at.month, user_id.to_i, label, token
      )
    end

    private

    def sanitize(label)
      label.to_s.gsub(/[^a-zA-Z0-9_\-]/, "")
    end

    def token
      SecureRandom.base36(TOKEN_LENGTH)
    end
  end
end
