class MsInquiryAnswersController < ApplicationController

  before_action :authenticate_admin_user?

  layout 'main/main'
  def new
    @inquiry = MetatronSaleInquiry.find(params[:metatron_sale_inquiry_id])
    @answer = MsInquiryAnswer.new(metatron_sale_inquiry_id: @inquiry.id)
  end
  
  def index
    @inquiries = MetatronSaleInquiry.all
  end
    
  
  def create
    @answer = MsInquiryAnswer.new(answer_params)
    @inquiry = MetatronSaleInquiry.find(@answer.metatron_sale_inquiry_id)
    logger.debug("======================== answer create @inquiry.email = #{@inquiry.email}")

    
        respond_to do |format|
          if @answer.save
            MetatronSaleInquiryMailer.send_when_answer(@answer,@inquiry).deliver
            MetatronSaleInquiryMailer.send_when_answer_admin(@answer,@inquiry).deliver
            format.html { redirect_to metatron_sale_inquiries_path, notice: "回答しました" }
            format.json { render :index, status: :created, location: @answer }
          else
            format.html { render :index, notice: "回答できませんでした"  }
            format.json { render json: @answer.errors, status: :unprocessable_entity }
          end
        end    
    
    
  end
    
  def show
    @answer = MsInquiryAnswer.find(params[:id])
    @inquiry = MetatronSaleInquiry.find(@answer.inquiry_id)
  end
    

  
  private 
    def answer_params
        params.require(:ms_inquiry_answer).permit(:metatron_sale_inquiry_id, :comment)
    end    
    
end
