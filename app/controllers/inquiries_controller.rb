class InquiriesController < ApplicationController
  
  before_action :exist_inquiry, only: [:show]
  before_action :spam_check, only: [:create]
  before_action :authenticate_admin_user?, only: [:index, :destroy]
  prepend_before_action :check_captcha, only: [:create]
  
  layout 'main/main'
  def new
    logger.debug("================= inquiry controller new")
    @inquiry = Inquiry.new
  end


  def create

      
        @inquiry = Inquiry.new(inquiry_params)
        respond_to do |format|
          if @inquiry.save
            InquiryMailer.send_when_inquiry(@inquiry).deliver
            InquiryMailer.send_when_inquiry_admin(@inquiry).deliver
            format.html { redirect_to root_path, notice: "お問い合わせを受け付けました" }
            format.json { render :index, status: :created, location: @inquiry }
          else
            format.html { render :index, notice: "お問い合わせを受け付けできませんでした"  }
            format.json { render json: @inquiry.errors, status: :unprocessable_entity }
          end
        end

  
    # if @inquiry.save 
    #   flash[:notice] = "下記内容でお問い合わせを受け付けました"
    #   redirect_to inquiry_path(@inquiry)
    # else
    #   flash[:notice] = "お問い合わせを受け付けできませんでした"
    #   render "inquiries/new"
    # end
  end
  
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
    
    # add 2024/2/4 
    def check_captcha
      unless verify_recaptcha(message: "reCAPTCHAのチェックをしてください")
        logger.debug("~~~~~~~~~~~~~~~~~~~~~ verify_recaptcha error #{message}")
        flash[:notice] = message
        redirect_to new_inquiry_path
      end 
    end
  
  
end
