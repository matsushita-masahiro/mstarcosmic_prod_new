class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
    allow_browser versions: :modern
  
     protect_from_forgery with: :exception
     
     
     include MachineSchedulesHelper
     
      
      def authenticate_admin_user?
          if user_signed_in?
            if User.find_by(id: current_user.id).user_type == "1"
                return true
            else
                flash[:alert] = "権限がありません"
                redirect_back(fallback_location: root_path)
            end
          else
             flash[:alert] = "権限がありません"
             redirect_back(fallback_location: root_path)
          end
      end
      
      def admin_user?
          if user_signed_in?
            if User.find_by(id: current_user.id).user_type == "1"
                return true
            else
                return false
            end
          else
              return false
          end
      end
      
      def authenticate_staff_user?
          if user_signed_in?
            if current_user.user_type == "1" || current_user.user_type == "10"
                return true
            else
                flash[:alert] = "権限がありません"
                redirect_back(fallback_location: root_path)
            end
          else
             flash[:alert] = "権限がありません"
             redirect_back(fallback_location: root_path)
          end
      end  
  
  
      def basic_auth
          authenticate_or_request_with_http_basic do |username, password|
            username == ENV['BASIC_AUTH_USER'] && password == ENV['BASIC_AUTH_PASSWORD']
          end
      end
      
      
      # カレンダー表示（URL直打ちで日付でない情報が入力されたときにfalseを返す）
      def date_valid?(str)
        !! Date.parse(str) rescue false
      end  
end
