Staff.delete_all

# development環境
Staff.seed(:id,
  {:id => 0, :name => "指名無し", :active_flag => true},
  {:id => 1, :name => "まさこ", :name_kanji => "聖子", :active_flag => true},
  {:id => 2, :name => "ゆうき", :name_kanji => "悠綺", :active_flag => true},
  {:id => 3, :name => "はるか", :name_kanji => "花香", :active_flag => true},
  {:id => 4, :name => "なお", :name_kanji => "奈緒", :active_flag => true},     
  {:id => 5, :name => "なつこ", :name_kanji => "夏子", :active_flag => true},         
  {:id => 6, :name => "ゆか", :name_kanji => "由香",},    
  {:id => 7, :name => "かな", :name_kanji => "可奈",},
  {:id => 8, :name => "さとう", :name_kanji => "佐藤",}
  )
  
# 本番環境
# Staff.seed(:id,
#   {:id => 0, :name => "指名無し", :active_flag => true},
#   {:id => 1, :user_id => 50, :name => "まさこ", :active_flag => true},
#   {:id => 2, :user_id => 633, :name => "ゆうき", :active_flag => true},
#   {:id => 3, :user_id => 449, :name => "はるか", :active_flag => true},
#   {:id => 4, :user_id => 42, :name => "なお", :active_flag => true},     
#   {:id => 5, :user_id => 1205, :name => "なつこ", :active_flag => true},         
#   {:id => 6, :user_id => 324, :name => "ゆか"},    
#   {:id => 7, :user_id => 314, :name => "かな"},
#   {:id => 8, :user_id => 1214, :name => "まさる"}
# )

# [0, nil, "指名無し"], 
# [1, 50, "まさこ"],
# [2, 633, "ゆうき"], 
# [3, 449, "はるか"], 
# [5, 1205, "なつこ"],
# [6, 324, "ゆか"],
# [7, 314, "かな"],
# [8, 1214, "さとう"], 
# [10, 1252, "なるみ"],
# [11, 240, "みつこ"],
# [13, 856, "ともこ"]

  
