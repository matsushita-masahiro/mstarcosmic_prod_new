
UserType.delete_all
UserType.seed(:id,
  {:id => 0, :type_name => "未設定"},
  {:id => 1, :type_name => "管理者"},
  {:id => 2, :type_name => "会員"},
  {:id => 3, :type_name => "紹介会員"},      #元の一般
  {:id => 4, :type_name => "一般"},          #元の代理店A
  {:id => 5, :type_name => "サイト会員"},    #元の代理店B
  {:id => 6, :type_name => "特別会員"},
  {:id => 7, :type_name => "その他"},
  {:id => 10, :type_name => "施術スタッフ"},
  {:id => 11, :type_name => "仮会員"},
  {:id => 99, :type_name => "テスト"}
  
)

# user_type == 11は予約時仮会員にする  2023/7/6

# UserType.create(id: 11, type_name: "仮会員")

