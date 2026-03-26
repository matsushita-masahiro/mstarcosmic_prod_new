Rails.application.routes.draw do
  get "business_trips/index"
  get "calendar/index"
  get "new_staff_schedules/index"
  get "new_schedules/index"
  get "new_reserves/index"
  get "new_reserves/show"
  get "new_reserves/confirm"
  get "new_reserves/new"

  
   #  新レイアウト用
   root "main#top"
   # root "main#top_mente"
   get "about_metatron" => "main#about_metatron"
   get "intestinal" => "main#intestinal"
   get "price_plan" => "main#price_plan"
   get "price_plan_coupon" => "main#price_plan_coupon"
   get "fasting" => "main#fasting"
   get "intestinal" => "main#intestinal"
   get "massage" => "main#massage"
   get "registration_thanks" => "main#registration_thanks"
   get "metatron_sale" => "main#metatron_sale"
   get "staffs" => "main#staffs"
   get 'price_list_select' => 'main#price_list_select'
   get 'price_plan_admin' => 'main#price_plan_admin'

   get "special_treatment_price" => "main#special_treatment_price"

    get 'home/readme' => 'home#readme'
    get 'home/readmust/:id' => 'home#readmust'
    get 'lppage' => 'home#lppage'
    
    
    devise_for :users, :controllers => {
        :registrations => 'users/registrations',
        :sessions => 'users/sessions',
        :passwords => 'users/passwords'
    }
   
#   delete 'users/destroy_user' => 'users#destroy_user'
   resources :users, :only => [:index, :edit, :update, :show, :destroy] do
      get 'schedules/month_select' => 'schedules#month_select'
      # resources :schedules
   end
   # 全userデータバックアップ
   get 'backup_users' => 'users#backup_users'
   get 'users/index/:per' => 'users#index'
   # post 'reservations/make_holiday/:date/:space' => 'reservations#make_holiday'
   # get 'reservations/my_reserved' => 'reservations#my_reserved'
   # get 'reservations/my_reserved_past' => 'reservations#my_reserved_past'
   
   # reservations でアクセスされても新予約画面(reserves#index)へ
   # get 'reservations' => 'reserves#index'
   # resources :reservations
   
   get 'data_conversion' => 'reserves#data_conversion'
   post 'reserves/make_holiday/:date/:start_date/:space' => 'reserves#make_holiday'
   get 'reserves/my_reserved' => 'reserves#my_reserved'
   # 休日の削除
   delete 'reserves/:id/:calender_start_date/holiday' => 'reserves#delete'
   # 予約の削除
   delete 'reserves/:id' => 'reserves#destroy'
   get 'reserves/machine_select' => 'reserves#machine_select'
   get 'reserves/:machine/index' => 'reserves#index'
   get 'reserves/new_cust' => 'reserves#new_cust'
   get 'reserves/new_cust_other' => 'reserves#new_cust_other'
   
   resources :reserves, except: [:show, :destroy]
   
   get 'all_schedules' => 'schedules#all_schedules'
   
   patch "admin/staffs/staff_machine_relations" => "staff_machine_relations#update"

   
   scope :admin do
      post "/staffs/:id" => "staffs#fire"
      resources :staffs do
         resources :schedules
      end
   end
   
   
   scope :admin do
      resources :machines do
         resources :machine_schedules
      end
   end   
   
   patch "staffs/:id/nonactivate" => "staffs#nonactivate"
   patch "staffs/:id/activate" => "staffs#activate"
   
   resources :user_types
   # post 'reservations/confirm' => 'reservations#confirm'
   
   # get 'inquiries/:id/answer' => 'inquiries#answer'
   # get 'inquiries/new' => 'inquiries#new1'
   resources :inquiries do 
      resources :answers, :only => [:new, :create, :show]
   end
   
   resources :metatron_sale_inquiries do 
      resources :ms_inquiry_answers, :only => [:new, :create, :show]
   end   
   
   # get 'answers/:id/new' => 'answers#new'
   # resources :answers, :only => [:create, :show, :index]
   
   resources :pay_types
   

   get 'payments/pay_select' => 'payments#pay_select'
   #　上記工事中にて下記に(2020/2/13)
   # get 'payments/pay_select' => 'payments#construction'

   get 'payments/complete_payment' => 'payments#complete_payment'
   get 'payments/complete_cash_payment' => 'payments#complete_cash_payment'
   get 'payments/:id/new' => 'payments#new'
   delete 'payment_destroy/:id' => 'payments#payment_destroy'
   resources :payments, :only => [:show, :index, :edit, :update, :destroy]
   resources :page_contents
   
#   算命学用
   get 'sanmeis/menu' => 'sanmeis#menu'
   get 'sanmeis/meishiki' => 'sanmeis#meishiki'
   get 'sanmeis/enegry' => 'sanmeis#energy'
   get 'sanmeis/handred_hyou' => 'sanmeis#handred_hyou'
   get 'sanmeis/handred_graph' => 'sanmeis#handred_graph'
   get 'sanmeis/koudo_area' => 'sanmeis#koudo_area' 
   get 'sanmeis/rikushin' => 'sanmeis#rikushin'

   # 新予約システム 2025/08/01
   # ✅ 新予約機能
   resources :new_reserves, except: [:edit, :update] do
      collection do
       post :confirm
      end
   end

   get 'calendar', to: 'calendar#index'
   get 'calendar/availability', to: 'calendar#availability', defaults: { format: :json }

   namespace :admin do
      resources :new_schedules, only: [:index, :create, :update, :destroy]
      resources :new_reserves, only: [:index, :show, :destroy]
      # 出張登録管理
      resources :business_trips, only: [:index, :create, :destroy] do
         collection do
         patch :bulk_update
         end
      end 
   end

     # スタッフスケジュール管理
   resources :new_staff_schedules, only: [:index, :show, :update] do
      collection do
      patch :bulk_update
      end
   end

   # 旧パスから新パスへのリダイレクト
   get 'staff_schedules', to: redirect('/new_staff_schedules')

    

   

   
   
   resources :meishikis, only: [:new, :create, :index, :show, :destroy]

   get '*anything' => 'errors#routing_error'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
