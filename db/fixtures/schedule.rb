Schedule.destroy_all
Schedule.seed(:id,
  {:id => 0, :user_id => 1, :schedule_date => Date.today+1, :schedule_space => 10.0, :schedule_type => "hd"},
  {:id => 1, :user_id => 1, :schedule_date => Date.today+1, :schedule_space => 10.5, :schedule_type => "hd"},
  {:id => 2, :user_id => 1, :schedule_date => Date.today+1, :schedule_space => 11.0, :schedule_type => "hd"},
  {:id => 3, :user_id => 1, :schedule_date => Date.today+1, :schedule_space => 11.5, :schedule_type => "hd"},
  {:id => 4, :user_id => 1, :schedule_date => Date.today+1, :schedule_space => 12.0, :schedule_type => "hd"},
  {:id => 5, :user_id => 19, :schedule_date => Date.today+3, :schedule_space => 11.0, :schedule_type => "hd"},
  {:id => 6, :user_id => 19, :schedule_date => Date.today+3, :schedule_space => 11.5, :schedule_type => "hd"},
  {:id => 7, :user_id => 19, :schedule_date => Date.today+3, :schedule_space => 13.0, :schedule_type => "hd"},
  {:id => 8, :user_id => 19, :schedule_date => Date.today+3, :schedule_space => 14.5, :schedule_type => "hd"},
  {:id => 9, :user_id => 19, :schedule_date => Date.today+3, :schedule_space => 15.0, :schedule_type => "hd"},
  {:id => 10, :user_id => 1, :schedule_date => Date.today+35, :schedule_space => 12.0, :schedule_type => "hd"},

)