# test/services/karte_storage_key_test.rb
require "test_helper"

class KarteStorageKeyTest < ActiveSupport::TestCase
  test "患者ごと・年月ごとの階層キーを組み立てる" do
    key = KarteStorageKey.build(user_id: 1447, label: "consent",
                                at: Time.zone.local(2026, 8, 2))
    assert_match %r{\Akarte/2026/08/user-001447/consent-[a-z0-9]{12}\z}, key
  end

  test "ラベルの記号を除去する" do
    key = KarteStorageKey.build(user_id: 1, label: "q1_purpose/../etc",
                                at: Time.zone.local(2026, 8, 2))
    assert_includes key, "/q1_purposeetc-"
    assert_not_includes key, ".."
  end

  test "組み立てられない場合は nil を返す" do
    assert_nil KarteStorageKey.build(user_id: nil, label: "consent")
    assert_nil KarteStorageKey.build(user_id: 1, label: "")
    assert_nil KarteStorageKey.build(user_id: 1, label: "///")
  end

  test "毎回異なるキーになる" do
    a = KarteStorageKey.build(user_id: 1, label: "consent")
    b = KarteStorageKey.build(user_id: 1, label: "consent")
    assert_not_equal a, b
  end
end
