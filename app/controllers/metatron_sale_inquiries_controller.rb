class MetatronSaleInquiriesController < ApplicationController
    
  
  before_action :exist_inquiry, only: [:show]
  before_action :spam_check, only: [:create]
  before_action :authenticate_admin_user?, only: [:index, :destroy]
  
  layout 'main/main'
  
  def new
    logger.debug("================= inquiry controller new")
    @inquiry = MetatronSaleInquiry.new
  end


  def create
      
        @inquiry = MetatronSaleInquiry.new(inquiry_params)
        respond_to do |format|
          if @inquiry.save
            MetatronSaleInquiryMailer.send_when_inquiry(@inquiry).deliver
            MetatronSaleInquiryMailer.send_when_inquiry_admin(@inquiry).deliver
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
    logger.debug("================= metatron_sale_inquiry controller index")
    @inquiries = MetatronSaleInquiry.all.order(created_at: :desc)
  end
  
  def show
    @inquiry = MetatronSaleInquiry.find(params[:id])
  end
  
  def destroy 
    @metatron_sale_inquiry = MetatronSaleInquiry.find(params[:id])
    @metatron_sale_inquiry.destroy
    redirect_to metatron_sale_inquiries_path
  end
  
  private 
    def inquiry_params
        params.require(:metatron_sale_inquiry).permit(:name, :name_kana, :email, :phone, 
                                        :postcode, :prefecture_code, :address_city, :trial_flag, :buy_consult_flag, :hp_consult_flag, :content)
    end
    
    def exist_inquiry
      if !MetatronSaleInquiry.find_by(id: params[:id])
        flash[:alert] = "メタトロン購入のお問合せがありません"
        redirect_to metatron_sale_inquiries_path
      end
    end
    
    def spam_check
      check_flag = false
      spam_words = []
      
      ["Д","б","й","д","ш","ы","л","Г","П","я","</a>"].each do |word|
         if params[:metatron_sale_inquiry][:content].include?("#{word}")
           spam_words << word
           check_flag = true
         end
       end
       
       if !check_flag
          ["Д","ш","й","д","ш","ы","л","Г","П","я"].each do |word|
             if params[:metatron_sale_inquiry][:name].include?("#{word}")
               spam_words << word
               check_flag = true
             end
           end
       end

       if !check_flag
          ["Д","ш","й","д","ш","ы","л","Г","П","я"].each do |word|
             if params[:metatron_sale_inquiry][:name_kana].include?("#{word}")
               spam_words << word
               check_flag = true
             end
           end
       end
       
       if !check_flag
          ["Д","б","й","д","ш","ы","л","Г","П","я"].each do |word|
             if params[:metatron_sale_inquiry][:email].include?("#{word}")
               spam_words << word
               check_flag = true
             end
           end
       end       
       
       if !check_flag
          ["Д","ш","й","д","ш","ы","л","Г","П","я"].each do |word|
             if params[:metatron_sale_inquiry][:address_city].include?("#{word}")
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
