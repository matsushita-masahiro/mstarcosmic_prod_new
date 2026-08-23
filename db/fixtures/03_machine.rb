Machine.destroy_all

Machine.seed(:id,
  {:id => 1, :name => "holisctic", :number_of_machine => 2, :short_word => "h"},
  {:id => 2, :name => "wellbeing", :number_of_machine => 0, :short_word => "w"},
  {:id => 3, :name => "other", :number_of_machine => 0, :short_word => "o"},
  {:id => 4, :name => "エステ", :number_of_machine => 1, :short_word => "e"},
  {:id => 5, :name => "鍼・整体", :number_of_machine => 1, :short_word => "b"}
  )