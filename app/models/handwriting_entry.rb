class HandwritingEntry < ApplicationRecord
  belongs_to :medical_questionnaire

  has_one_attached :image

  # 要配慮個人情報に該当しうるためカラム単位で暗号化
  encrypts :transcribed_text

  # pen: strokes(JSON) + image(PNG) を保持。将来の手書き認識に備える
  # keyboard: transcribed_text に入力内容が入る
  enum :input_mode, { pen: 0, keyboard: 1 }, prefix: true

  validates :question_key, presence: true,
            uniqueness: { scope: :medical_questionnaire_id }

  def blank_entry?
    if input_mode_keyboard?
      transcribed_text.blank?
    else
      strokes.blank? && !image.attached?
    end
  end

  # スタッフ画面での表示用。キーボード入力ならテキスト、ペンなら nil。
  def display_text
    input_mode_keyboard? ? transcribed_text : nil
  end

  # 前の版から引き継いだストロークの数。ここから後ろが今回書き足したぶん。
  # 引き継ぎが無い（初回提出・前版に同じ欄が無い）なら nil。
  #
  # ── なぜ数で分けられるのか ───────────────────────
  #
  # 訂正では前版の strokes を記入画面に復元してから書き足す。
  # signature_pad の fromData は復元ぶんを配列の先頭にそのまま連結し
  # （_data = _data.concat(渡された配列)）、書き足した線はその後ろに積まれる。
  # 部分消しも undo も無く、消去は「消す」＝全消しだけなので、
  # 配列は追記のみで伸びる。
  #
  # time は使わない。あれは端末（iPad）の時計で、サーバの submitted_at と
  # 突き合わせると別々の時計を比べることになる。数分ずれただけで
  # 全部が「古い」か「新しい」に倒れる。
  #
  # ── 安全弁 ─────────────────────────────────
  #
  # 患者が「消す」で全消ししてから書き直すと、先頭は前版と一致しない。
  # そのときは 0 を返して「全部が今回書かれたもの」に倒す。
  # 実データ（staging 14件）では全件一致しているが、全消しの経路が
  # ある以上、現れていないだけとして扱う。
  def inherited_stroke_count(previous_entry)
    return nil if previous_entry.nil?

    previous = previous_entry.strokes
    current  = strokes
    return nil unless previous.is_a?(Array) && previous.any?
    return nil unless current.is_a?(Array) && current.any?

    return 0 if current.first != previous.first

    # 前版より短くなることは無い想定だが、短ければ引き継ぎはそこまで。
    [ previous.size, current.size ].min
  end
end
