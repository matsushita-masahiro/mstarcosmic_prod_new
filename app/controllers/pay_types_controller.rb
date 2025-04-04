class PayTypesController < ApplicationController
  
  before_action :authenticate_admin_user?
    
  before_action :basic_auth  
    
  def new
    @pay_type = PayType.new
  end
  
  def create
    @pay_type = PayType.new(pay_type_params)
    if @pay_type.save
      flash[:notice] = "PayType新規追加しました"
      redirect_to pay_types_path
    else
      flash[:alert] = "PayType新規追加できませんでした"
      render 'new'
    end
  end
  
  def index
    @pay_types = PayType.where.not(id: 1).order(:id)
  end
  
  def show
    @pay_type = PayType.find_by(id: params[:id])
  end 
  
  def edit
    if exist_pay_type(params[:id])
       @pay_type = PayType.find_by(id: params[:id])
    else
       flash[:alert] = "存在しないPayTypeです"
       redirect_to pay_types_path
    end
  end
  
  def update
    @pay_type = PayType.find(params[:id])
    if @pay_type.update_attributes(pay_type_params)
      flash[:notice] = "PayType修正できました"
      redirect_to pay_types_path
    else
      flash[:alert] = "PayType修正できませんでした"
      render 'edit'
    end
  end
  
  def destroy
    @pay_type = PayType.find(params[:id])
    if @pay_type.destroy
      flash[:notice] = "PayTypeを削除しました"
      redirect_to pay_types_path
    else
      flash[:alert] = "PayTypeを削除出来ませんでした"
      render "pay_types/edit"
    end
  end
  
  
  private
  
     def pay_type_params
        params.require(:pay_type).permit(:id, :user_type_id, :pay_name, :price, :paypal_form)
     end
     
     def exist_pay_type(pay_type_id)
         if PayType.find_by(id: pay_type_id)
             return true
         else
             return false
         end
     end
     
     
  
end
