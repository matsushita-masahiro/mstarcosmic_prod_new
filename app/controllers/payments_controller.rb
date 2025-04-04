class PaymentsController < ApplicationController
  
  layout 'main/main'
  
  before_action :authenticate_user!
  before_action :authenticate_admin_user?, only: [:index]
  before_action :access_controll_payment, only: [:show, :edit, :update, :destroy]
  # before_action :payment_valid, only: [:complete_cash_payment, :complete_payment]
  
  def pay_select
    # @user_type = User.find_by(id: current_user.id).user_type
    @payments = current_user.payments
  end 
  
  def construction
  end
  
  # pay_select.html.erb　からくる
  def new
    @number_of_coupons = params[:id]
    session[:number_of_coupons] = @number_of_coupons
    logger.debug("============================= @number_of_coupons = #{@number_of_coupons}")
    @user = User.find_by(id: current_user.id)
    @payment = Payment.new
  end
  
  
  
  def complete_cash_payment
    @number_of_coupons = session[:number_of_coupons]
    logger.debug("============================= complete_cash_payment number_of_coupons = #{@number_of_coupons}")
    @user = User.find(current_user.id)
    # price = PayType.find(@pay_type).price
    # @payment = Payment.new(user_id: current_user.id, price: price, pay_type: @pay_type)
    @payment = Payment.new(user_id: current_user.id)
    if @payment.save
      # 回数券の人のレコード作成
      # coupon_times(@number_of_coupons).times do |i|
      @number_of_coupons.to_i.times do |i|
        Coupon.create(payment_id: @payment.id, status: "new", order_number: i+1)
             logger.debug("============================= coupon no = #{i+1}")
      end
      # if [4,5,6,8,11].include?(@pay_type)
      # 2024/6/19 回数券は5,10回のみにした
      # if [5,10].include?(@number_of_coupons)
        flash[:notice] = "現金支払い処理完了・回数券発行しました"
      # else 
        # flash[:notice] = "現金支払い処理完しました"
      # end        
      session[:pay_type] = nil
      redirect_to payment_path(@payment)
    else
      flash[:notice] = "支払い処理に失敗しました"
      session[:pay_type] = nil
      redirect_back(fallback_location: root_path)
    end
  end
  

  
  def complete_payment
    @pay_type = session[:pay_type]
    @user = User.find(current_user.id)
    price = PayType.find(@pay_type).price
    @payment = Payment.new(user_id: current_user.id, price: price, pay_type: @pay_type)
    if @payment.save
      # 回数券の人のレコード作成
      coupon_times(@pay_type).times do |i|
        Coupon.create(payment_id: @payment.id, status: "new", order_number: i+1)
             logger.debug("============================= credit coupon no = #{i+1}")
      end
      if [4,5,6,8,11].include?(@pay_type)
        flash[:notice] = "クレジット支払い処理完了・回数券発行しました"
      else 
        flash[:notice] = "クレジット支払い処理完了しました"
      end
      session[:pay_type] = nil
      redirect_to payment_path(@payment)
    else
      flash[:notice] = "支払い処理に失敗しました"
      session[:pay_type] = nil
      redirect_back(fallback_location: root_path)
    end
  end
  
  def index
    if current_user.user_type == "1"
      # 全ユーザーの支払い履歴一覧
      @payments = Payment.all.order(created_at: :desc)
    else
      @payments = Payment.where(user_id: current_user.id).order(created_at: :desc)
    end

  end
  
  def show
    @payment = Payment.find(params[:id])
    @user = User.find(@payment.user_id)
  end
  
  def edit
    # あるユーザーのある支払いに対してのedit
    @payment = Payment.find(params[:id])
    @user = User.find(@payment.user_id)
    @used_coupons = Coupon.where(payment_id: @payment.id, status: "used")
    @new_coupons = Coupon.where(payment_id: @payment.id, status: "new")
  end 
  
  def update
    @payment = Payment.find(params[:id])
    if @coupon = Coupon.find_by(payment_id: @payment.id, status: "new") # 未使用のレコード１件取得
          @coupon.status = "used"
          @coupon.remarks = params[:payment][:remarks]
          if @coupon.save
            flash[:notice] = "回数券を１枚使用しました"
            redirect_to "/payments/#{@payment.id}/edit"
          else
            flash[:notice] = "回数券を使用できませんでした"
            redirect_back(fallback_location: root_path)
          end
    else
       flash[:notice] = "未使用の回数券はありません"
       redirect_back(fallback_location: root_path)
    end
  end
  
  # couponを一枚ずつ削除する機能
  def destroy
    @payment = Payment.find(params[:id])
    @coupon = Coupon.where(payment_id: @payment.id, status: "used").order(updated_at: :asc).last
    @coupon.status = "new"
    if @coupon.save
      flash[:notice] = "取消しました"
      redirect_to "/payments/#{@payment.id}/edit"
    else
      flash[:notice] = "取消せませんでした"
      redirect_back(fallback_location: root_path)
    end
  end
  
  # payment.coupon情報削除　管理者のみ実行可能
  def payment_destroy
    @payment = Payment.find(params[:id])
    @payment.destroy
    
    if @payment.destroy
      flash[:notice] = "回数券を削除しました"
      redirect_to payments_path
    else
      flash[:notice] = "支払情報を削除できませんでした"
      render "payments/index"
    end
  end
  
  
  
  
  private 
     def payment_params
        params.require(:payment).permit(:user_id, :price, :remarks, :user_type).merge(user_id: current_user.id, user_type: User.find(current_user.id).user_type)
     end
     
     def coupon_times(pay_type)
        coupon_times = 0
        case pay_type.to_i
        when 5,9,13,17 then   # 病人(5回券/月)
          coupon_times = 5
        when 4,8,12,16,99 then   # 既存＆distributorの回数券(11枚)
          coupon_times = 11
        else
          coupon_times = 0
        end 
      
        return coupon_times
     end
     
     def access_controll_payment
       if !Payment.find_by(id: params[:id])
         flash[:alert] = "指定の支払い情報が存在しません"
         redirect_to payments_path
       end
     end
     
     def payment_valid
       logger.debug("^^^^^^^^^^^^^^^^^^^^^ payment_valid session = #{session[:pay_type]}")
       @user = User.find_by(id: current_user.id)
       
       flag = false
       
       case @user.user_type.to_i
        when 1 then   # 管理者は全てok
            flag = true
        when 2 then   # 会員
          case session[:pay_type].to_i
          when 2,3,4,5 then
            flag = true
          else
            flag = false
          end
        when 3 then   # 一般
          case session[:pay_type].to_i
          when 6,7,8,9 then
            flag = true
          else
            flag = false
          end 
        when 4 then   # 代理店A
          case session[:pay_type].to_i
          when 10,11,12,13 then
            flag = true
          else
            flag = false
          end 
        when 5 then   # 代理店B
          case session[:pay_type].to_i
          when 14,15,16,17 then
            flag = true
          else
            flag = false
          end 
        when 6 then   # 特別会員
          case session[:pay_type].to_i
          when 18 then
            flag = true
          else
            flag = false
          end 
        when 7 then   # その他
          case session[:pay_type].to_i
          when 19 then
            flag = true
          else
            flag = false
          end 
        when 99 then   # テスト
          case session[:pay_type].to_i
          when 99 then
            flag = true
          else
            flag = false
          end          
        else
          flag = false
        end 
        
        logger.debug("~~~~~^^^^^^^^^^^^^ flag = #{flag}")
       
         if !flag
           flash[:alert] = "支払いタイプに不整合が起こりました"
           redirect_to "/payments/pay_select"
         end
     end
     
end
