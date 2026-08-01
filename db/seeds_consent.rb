# 同意書 v1.0 の投入
# 冪等: 既に同じ version があれば何もしない
#
#   bin/rails runner db/seeds_consent.rb
#
# 【重要】文面を変更する場合は、既存レコードを書き換えず新バージョンを作成すること。
# 過去の署名が「どの文面に対するものか」を追跡できなくなるため。
body = File.read(Rails.root.join("db/consent/v1.0.txt"))

doc = ConsentDocument.find_or_initialize_by(version: "v1.0")
if doc.persisted?
  puts "既に存在します: #{doc.version} (#{doc.consents.count} 件の署名)"
else
  doc.assign_attributes(
    title: "メタトロン測定に関する説明・同意書",
    body: body,
    published_at: Time.current
  )
  doc.save!
  puts "作成しました: #{doc.version} / digest=#{doc.body_digest[0, 12]}..."
end
