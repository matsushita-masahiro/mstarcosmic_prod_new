# config/initializers/karte_storage_key.rb
#
# ActiveStorage のオブジェクトキーに階層を持たせる。
#
# 既定では blob.key がランダム28文字となり、バケット直下にフラットに並ぶ。
# 患者1000名 × 複数回来店 × 手書き7項目 で数万ファイルになるため、
# S3 コンソールから辿れず、ライフサイクルルールも設定しにくい。
#
# 出力例:
#   karte/2026/08/user-001447/consent-a1b2c3d4e5f6.png
#   karte/2026/08/user-001447/q1_purpose-9z8y7x6w5v4u.png
#
# 【注意】既存の blob のキーは変更されない。この初期化子を入れる前に
# 保存されたファイルはフラットな配置のまま残る。
#
# 【前版からの修正】
# class_eval + def key の書き方では、フォールバック側で参照している
# MINIMUM_TOKEN_LENGTH の定数探索が初期化子ファイルのレキシカルスコープで
# 行われるため NameError になる（ActiveStorage::Blob の定数として解決されない）。
# しかもこのフォールバックは karte_context を渡さない全ての添付が通る経路なので、
# カルテ以外の ActiveStorage 利用が全滅する。
# prepend + super に変えて、既定の挙動をそのまま呼ぶようにした。
# 併せて to_prepare のたびにメソッドを再定義する形も解消している
# （prepend は同一モジュールなら二度目以降は無視される）。
module KarteStorageKey
  # 呼び出し側が context を渡すとその情報をキーに反映する。
  # 渡されない場合は ActiveStorage 既定の挙動（ランダムキー）になる。
  attr_accessor :karte_context

  def key
    self[:key] ||= build_karte_key || super
  end

  private

  def build_karte_key
    ctx = karte_context
    return nil if ctx.blank?

    user_id = ctx[:user_id]
    label   = ctx[:label].to_s.gsub(/[^a-zA-Z0-9_\-]/, "")
    return nil if user_id.blank? || label.blank?

    now   = Time.current
    token = ActiveStorage::Blob.generate_unique_secure_token(length: 12)

    format("karte/%04d/%02d/user-%06d/%s-%s",
           now.year, now.month, user_id.to_i, label, token)
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::Blob.prepend(KarteStorageKey)
end
