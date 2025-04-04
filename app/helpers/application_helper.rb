module ApplicationHelper
    
    def default_meta_tags
      {
        # site: 'mstarcosmic',
        # title: 'mstarcosmic',
        reverse: true,
        charset: 'utf-8',
        description: 'メタトロン',
        keywords: 'メタトロン,mstarcosmic,metatron,鹿田,渋谷,メタトロン購入,メタトロン施術,メタトロン相談,メタトロン体験',
        canonical: request.original_url,
        separator: '|',
        icon: [
          { href: image_url('favicon.ico') }
        #   { href: image_url('icon.jpg'), rel: 'apple-touch-icon', sizes: '180x180', type: 'image/jpg' },
        ],
        og: {
          site_name: 'mstarcosmic', # もしくは site_name: :site
          title: :title, # もしくは title: :title
          description: :description, # もしくは description: :description
          type: 'website',
          url: request.original_url,
          # image: image_url('ogp.png'),
          locale: 'ja_JP',
        }
      #   twitter: {
      #     card: 'summary',
      #     site: '@ツイッターのアカウント名',
      #   }
      }
    end
    
    
    def admin_user?
        if User.find_by(id: current_user.id).user_type == "1"
            return true
        else
            return false
        end
    end
    
    def staff_user?
        if current_user.user_type == "1" || current_user.user_type == "10"
            return true
        else
            return false
        end
    end
    
    
    def display_time(x)
        if x-x.to_i == 0
            result = "#{x.to_i}:00"
        else
            result = "#{x.to_i}:#{((x-x.to_i)*60).to_i}"
        end
      return  result 
    end
    
    def registration_completed?
        error_msg = []
        if user_signed_in?
            if current_user.email.nil?
                error_msg << "メールアドレス"
            end
                
            if current_user.name.nil?
                error_msg << "名前"
            end

            if current_user.name_kana.nil?
                error_msg << "名前かな"
            end
            
            if current_user.tel.nil?
                error_msg << "電話番号"
            end
            
            if current_user.birthday.nil?
                error_msg << "生年月日"
            end
            
            if current_user.introducer.nil?
                error_msg << "紹介者"
            end
            
            if current_user.gender.nil?
                error_msg << "性別"
            end
        end
        
        return error_msg
        
    end
    
    def staff_info
        if user_signed_in? && current_user.user_type == "10"
            if current_user.staff
                return current_user.staff
            else
                return false
            end
        else
            return false
        end
    end
    

end
