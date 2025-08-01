module UsersHelper

    # app/helpers/users_helper.rb
    def user_type_label(user)
        {
        "unset" => "未設定",
        "admin" => "管理者",
        "member" => "会員",
        "referral_member" => "紹介会員",
        "general" => "一般",
        "site_member" => "サイト会員",
        "special" => "特別会員",
        "other" => "その他",
        "staff" => "施術スタッフ",
        "provisional" => "仮会員",
        "test" => "テスト"
        }[user.user_type] || "不明"
    end
  
end
