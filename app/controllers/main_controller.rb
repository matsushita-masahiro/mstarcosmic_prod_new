class MainController < ApplicationController
  
  layout 'main/main'
  
  before_action :authenticate_user!, only: [:registration_thanks]
  
  def top
  end
  
  def top_mente
  end 
  
  def about_metatron
    logger.debug("=========== about_metatron")
  end
  
  def price_plan_admin
    logger.debug("=========== price_plan_admin")
  end
  
  def price_plan
    @coupon = params[:coupon]
    logger.debug("=========== price_plan #{@coupon}")
    if @coupon == ENV['ARA_COUPON']
      redirect_to price_plan_coupon_path
    end
  end
  
  def price_plan_coupon
  end
  
  def intestinal
  end
  
  def fasting
  end
  
  def massage 
  end
  
  def metatron_sale
  end
  
  def special_treatment_price
  end
  
  def registration_thanks
    current_user.update(registration_status: true)
  end
  
  def staffs
  end
  
  def price_list_select
        # if user_signed_in?
        #   @user = current_user
        # else
        #   @user = nil
        # end
        
        @coupon = ENV['ARA_COUPON']

        respond_to do |format|
            # format.html
            format.js
        end
    
  end  

end