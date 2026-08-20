namespace :intake do
  desc "壊れた answers のキーを直す（既定は dry-run。書き込むには APPLY=1）"
  task fix_answer_keys: :environment do
    apply = ENV["APPLY"] == "1"

    puts "=== 問診票の回答キーの修正（#{apply ? 'APPLY' : 'dry-run'}）==="
    puts "問診票 総数: #{MedicalQuestionnaire.count}"

    targets = []
    conflicted = []

    # 件数が少ないので Ruby 側で見る。壊れたキーの形（末尾の "]["）を
    # SQL で書くと、jsonb と sqlite の両方で通る形にするのが面倒なわりに
    # 得るものが無い。
    #
    # 訂正版（previous_id を持つレコード）も対象に含める。除くと、
    # 前版だけが直って差分に「家族歴: 糖尿病 → （未回答）」という
    # 実際には起きていない変更が出る。
    MedicalQuestionnaire.find_each do |record|
      result = AnswerKeyRepair.repair(record.answers)
      next unless result.broken?

      (result.safe_to_apply? ? targets : conflicted) << [ record, result ]
    end

    if targets.empty? && conflicted.empty?
      puts "壊れたキーを持つレコードはありません。"
      next
    end

    tally = Hash.new(0)
    targets.each { |_r, result| result.renames.each { |m| tally[m[:from]] += 1 } }
    puts "壊れたキーの内訳: #{tally.sort_by { |_k, v| -v }.to_h.inspect}"
    puts "対象レコード数: #{targets.size} / 対象患者数: #{targets.map { |r, _| r.user_id }.uniq.size}"

    targets.each do |record, result|
      puts "  [#{record.id}] user=#{record.user_id} status=#{record.status} " \
           "previous_id=#{record.previous_id.inspect} " \
           "#{result.renames.map { |m| "#{m[:from]} → #{m[:to]}" }.join(', ')}"
    end

    # 衝突は自動で直さない。どちらが患者の回答かは中身を見ないと決められない。
    if conflicted.any?
      puts
      puts "!! 正しいキーが既にあり、値が違うレコード（自動では直しません）"
      conflicted.each do |record, result|
        result.conflicts.each do |c|
          puts "  [#{record.id}] user=#{record.user_id} #{c[:correct]}: " \
               "壊れ側=#{c[:broken_value].inspect} / 正しい側=#{c[:correct_value].inspect}"
        end
      end
      puts "   → カルテで中身を確かめてから手で直すこと。"
    end

    unless apply
      puts
      puts "dry-run のため書き込んでいません。実行するには APPLY=1 を付けてください。"
      next
    end

    # update_column を使う。キーの綴りを直すだけで、回答も判定も変わらないため。
    #   - before_save :promote_flags_from_answers を走らせない
    #     （複数選択は禁忌フラグに関係しないので、走らせても値は同じ。
    #       それでも10年ものの提出済みレコードにコールバックを通す理由がない）
    #   - updated_at を動かさない。提出済みの記録の更新日時は患者・スタッフの
    #     操作を表すもので、この修復で動くと履歴が読めなくなる
    # 変更したレコードの id は上のログに残る。
    updated = 0
    MedicalQuestionnaire.transaction do
      targets.each do |record, result|
        record.update_column(:answers, result.answers)
        updated += 1
      end
    end

    puts
    puts "#{updated} 件を更新しました。" \
         "#{conflicted.size} 件は衝突のため触っていません。"
  end
end
