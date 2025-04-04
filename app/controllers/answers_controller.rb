class AnswersController < ApplicationController
  
  before_action :spam_check, only: [:create]
  before_action :authenticate_admin_user?, only: [:new, :index, :create]
  
  layout 'main/main'
  def new
    @inquiry = Inquiry.find(params[:inquiry_id])
    @answer = Answer.new(inquiry_id: @inquiry.id)
  end
  
  # def index
  #   @inquiries = Inquiry.all
  # end
    
  
  def create
    @answer = Answer.new(answer_params)
    @inquiry = Inquiry.find(@answer.inquiry_id)
    logger.debug("======================== answer create @inquiry.email = #{@inquiry.email}")
    @answer.user_id = current_user.id
    
        respond_to do |format|
          if @answer.save
            InquiryMailer.send_when_answer(@answer,@inquiry).deliver
            InquiryMailer.send_when_answer_admin(@answer,@inquiry).deliver
            format.html { redirect_to inquiries_path, notice: "回答しました" }
            format.json { render :index, status: :created, location: @answer }
          else
            format.html { render :index, notice: "回答できませんでした"  }
            format.json { render json: @answer.errors, status: :unprocessable_entity }
          end
        end    
    
    
  end
    
  def show
    @answer = Answer.find(params[:id])
    @inquiry = Inquiry.find(@answer.inquiry_id)
  end
    

  
  private 
    def answer_params
        params.require(:answer).permit(:inquiry_id, :comment)
    end
    
    
    def spam_check
      check_flag = false
      spam_words = []
      
      ["Д","б","й","д","ш","ы","л","Г","П","я","</a>"].each do |word|
         if params[:answer][:comment].include?("#{word}")
           spam_words << word
           check_flag = true
         end
       end           
       
       if check_flag
          logger.debug("----------- Check inquiry because spam mail received -> #{spam_words}")
          redirect_to root_path
       end
    end
end
