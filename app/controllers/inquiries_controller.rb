class InquiriesController < ApplicationController
  
  before_action :exist_inquiry, only: [:show]
  before_action :spam_check, only: [:create]
  before_action :authenticate_admin_user?, only: [:index, :destroy]

  layout 'main/main'
  def new
    @inquiry = Inquiry.new
  end
  
def create
  @inquiry = Inquiry.new(inquiry_params)

  # ログ出力
  Rails.logger.debug("📥 g-recaptcha-response = #{params['g-recaptcha-response']}")

  unless verify_recaptcha(model: @inquiry)
    Rails.logger.debug("❌ reCAPTCHA verification failed")
    Rails.logger.debug("📥 g-recaptcha-response = #{params['g-recaptcha-response']}")
    Rails.logger.debug("📛 recaptcha error = #{request.env['recaptcha.error']}")
    flash[:alert] = "reCAPTCHAのチェックをしてください"
    redirect_to new_inquiry_path and return
  end


  if @inquiry.save
    InquiryMailer.send_when_inquiry(@inquiry).deliver
    InquiryMailer.send_when_inquiry_admin(@inquiry).deliver
    respond_to do |format|
      format.html { redirect_to root_path, notice: "お問い合わせを受け付けました" }
      format.json { render :index, status: :created, location: @inquiry }
    end
  else
    respond_to do |format|
      format.html { render :new }
      format.json { render json: @inquiry.errors, status: :unprocessable_entity }
    end
  end
end

  
    
  # def create
  #   @inquiry = Inquiry.new(inquiry_params)
  
  #   respond_to do |format|
  #     unless verify_recaptcha(model: @inquiry, message: "reCAPTCHAのチェックをしてください")
  #       flash[:alert] = "reCAPTCHAのチェックをしてください"  # flash[:alert] に変更
  #       logger.debug("reCAPTCHAのチェック")
  #       format.html { redirect_to new_inquiry_path }  # リダイレクトを使ってメッセージを表示
  #       format.json { render json: { error: "reCAPTCHAエラー" }, status: :unprocessable_entity }
  #       return
  #     end
  
  #     if @inquiry.save
  #       InquiryMailer.send_when_inquiry(@inquiry).deliver
  #       InquiryMailer.send_when_inquiry_admin(@inquiry).deliver
  #       format.html { redirect_to root_path, notice: "お問い合わせを受け付けました" }
  #       format.json { render :index, status: :created, location: @inquiry }
  #     else
  #       format.html { render :new }
  #       format.json { render json: @inquiry.errors, status: :unprocessable_entity }
  #     end
  #   end
  # end



  


  # def create

      
  #       @inquiry = Inquiry.new(inquiry_params)
  #       respond_to do |format|
  #         if @inquiry.save
  #           InquiryMailer.send_when_inquiry(@inquiry).deliver
  #           InquiryMailer.send_when_inquiry_admin(@inquiry).deliver
  #           format.html { redirect_to root_path, notice: "お問い合わせを受け付けました" }
  #           format.json { render :index, status: :created, location: @inquiry }
  #         else
  #           format.html { render :index, notice: "お問い合わせを受け付けできませんでした"  }
  #           format.json { render json: @inquiry.errors, status: :unprocessable_entity }
  #         end
  #       end

  # end
  
  def index
    @inquiries = Inquiry.all.order(created_at: :desc)
  end
  
  def show
    @inquiry = Inquiry.find(params[:id])
  end
  
  def destroy 
    @inquiry = Inquiry.find(params[:id])
    @inquiry.destroy
    redirect_to inquiries_path
  end
  
  private 
    def inquiry_params
        params.require(:inquiry).permit(:user_id, :name, :email, :content)
    end
    
    def exist_inquiry
      if !Inquiry.find_by(id: params[:id])
        flash[:alert] = "お問合せがありません"
        redirect_to inquiries_path
      end
    end
    
    def spam_check
      check_flag = false
      spam_words = []
      
      ["Д","б","й","д","ш","ы","л","Г","П","я","</a>","Hi"].each do |word|
         if params[:inquiry][:content].include?("#{word}")
           spam_words << word
           check_flag = true
         end
       end
       
       if !check_flag
          ["Д","ш","й","д","ш","ы","л","Г","П","я","gacrigrasy"].each do |word|
             if params[:inquiry][:name].include?("#{word}")
               spam_words << word
               check_flag = true
             end
           end
       end
       
       if !check_flag
          ["Д","б","й","д","ш","ы","л","Г","П","я"].each do |word|
             if params[:inquiry][:email].include?("#{word}")
               spam_words << word
               check_flag = true
             end
           end
       end       
       
       
       
       if check_flag
          logger.debug("----------- Check inquiry because spam mail received -> #{spam_words}")
          redirect_to root_path
       end
    end
    
  

  
  
end
