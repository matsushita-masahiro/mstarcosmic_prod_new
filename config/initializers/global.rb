class Global
    
    ADMIN_EMAIL = ENV['USER_EMAIL']
    ADMIN_EMAIL_PASS = ENV['EMAIL_PASSWORD']
    WEEKDAY = ["日","月","火","水","木","金","土"].freeze
    GENDER = {"m" => "男性", "f" => "女性"}.freeze
    PAY_DESTROY = "支払情報・残り回数券情報も削除されます。本当に削除しますか？"
    COUPON_TYPE = [4,5,6,8,11].freeze
    Global::PER_PAGE = 3
    
end
