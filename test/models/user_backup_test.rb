require "test_helper"

# users → user_backups の複製。
#
# UsersController#backup_users はカラムを1行ずつ手で写している。users に
# カラムを足したとき、テーブル側と写す処理の両方を直さないと、バックアップから
# 静かに欠ける。落ちも警告も出ないので、気づくのは復元しようとしたときになる。
#
# そこでカラム名を列挙せず、users のカラムを機械的に突き合わせる。
# 列挙すると追加のたびにテストも手で直すことになり、直し忘れれば同じ穴が空く。
class UserBackupTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # user_backups が持たないことを意図しているカラム。
  #
  # registration_status は users にあるが user_backups には無い。今回足した
  # blood_type とは別に、以前から漏れている。直すと復元時の挙動が変わりうるため
  # ここでは既知として記録するに留める（直すかどうかは別途判断すること）。
  KNOWN_MISSING = %w[registration_status].freeze

  setup do
    Rails.application.reload_routes_unless_loaded

    @admin = User.create!(email: "admin-backup@example.com", name: "管理者",
                          password: "password", user_type: "1",
                          name_kana: "かんりしゃ", tel: "0312345678",
                          birthday: Date.new(1990, 1, 1), gender: "f")
  end

  test "users のカラムは user_backups にも存在する" do
    missing = User.column_names - UserBackup.column_names - KNOWN_MISSING

    assert_empty missing,
                 "users に足したカラムが user_backups にありません: #{missing.join(', ')}。" \
                 "テーブルとコピー処理の両方を直してください"
  end

  # 既知の漏れが直ったことに気づけるようにする。
  # 直っているならこのテストではなく KNOWN_MISSING を更新すること。
  test "既知の漏れカラムは今も漏れたままである" do
    still_missing = KNOWN_MISSING & (User.column_names - UserBackup.column_names)

    assert_equal KNOWN_MISSING.sort, still_missing.sort,
                 "既知の漏れが解消されています。KNOWN_MISSING を更新してください"
  end

  # 本丸。カラムがあるだけでは足りず、写す処理が書かれていないと値は入らない。
  test "バックアップに共通カラムの値がすべて写る" do
    user = User.create!(email: "patient-backup@example.com", name: "患者 太郎",
                        name_kana: "かんじゃ たろう", tel: "0312345678",
                        password: "password", birthday: Date.new(1985, 3, 4),
                        gender: "f", blood_type: "unknown", abo: "abo",
                        introducer: "紹介者", remarks: "備考",
                        membership_number: "M-1", user_type: "0")

    sign_in @admin
    get backup_users_path

    backup = UserBackup.find(user.id)
    (UserBackup.column_names & User.column_names).each do |column|
      expected = user.public_send(column)
      message  = "#{column} がバックアップに写っていません"

      # 値が nil のカラムもある（写し漏れと区別が付かないので両方を見る）
      if expected.nil?
        assert_nil backup.public_send(column), message
      else
        assert_equal expected, backup.public_send(column), message
      end
    end
  end

  # 上の突き合わせは共通カラムを回すので、血液型だけを名指しでも押さえておく。
  # 「カラムは足したがコピー処理を書き忘れた」を必ず落とすため。
  test "血液型がバックアップに写る" do
    user = User.create!(email: "blood-backup@example.com", name: "患者 花子",
                        name_kana: "かんじゃ はなこ", tel: "0312345678",
                        password: "password", birthday: Date.new(1985, 3, 4),
                        gender: "f", blood_type: "ab", user_type: "0")

    sign_in @admin
    get backup_users_path

    assert_equal "ab", UserBackup.find(user.id).blood_type,
                 "users に足したらコピー処理も直すこと"
  end
end
