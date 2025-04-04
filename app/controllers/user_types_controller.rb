class UserTypesController < ApplicationController
  
  def new
    @user_type = UserType.new
  end
  
  def create
    @user_type = UserType.new(user_type_params)
    if @user_type.save
      flash[:notice] = "ユーザータイプを追加しました"
      redirect_to user_types_path      
    else
      flash[:notice] = "ユーザータイプを追加できませんでした"
      render "user_types/new"      
    end
  end
  
  def index
    @user_types = UserType.all
  end
  
  def edit
    @user_type = UserType.find(params[:id])
  end
  
  def update
    @user_type = UserType.find(params[:id])
    if @user_type.update(user_type_params)
      flash[:notice] = "ユーザータイプを更新しました"
      redirect_to user_types_path
    else
      flash[:notice] = "ユーザータイプを更新できませんでした"
      render "user_types/edit"
    end
  end
  
  def destroy
    @user_type = UserType.find(params[:id])
    if @user_type.destroy
      flash[:notice] = "ユーザータイプを削除"
      redirect_to user_types_path
    else
      flash[:notice] = "ユーザータイプを削除できませんでした"
      render "edit"
    end
  end
  
  private
    def user_type_params
        params.require(:user_type).permit(:user_type, :type_name)
    end
end
