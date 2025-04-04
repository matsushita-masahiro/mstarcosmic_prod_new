class HomeController < ApplicationController
  
  layout 'main/main'
  
  def top
  end
  
  def readme
    @user = User.find(current_user.id)
  end
  
  def readmust
    @page_id = params[:id]
    if @page_id == "1"
      redirect_to root_path
    end
    @user = User.find_by(id: current_user.id)
  end
  
end
