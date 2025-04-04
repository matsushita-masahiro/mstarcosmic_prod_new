class PageContentsController < ApplicationController
  
  layout 'main/main'
  before_action :admin_user

  def index
    @page_contents = PageContent.all
  end
  
  def show
    if show_error?
      @page_content = PageContent.find_by(id: params[:id])
      redirect_to page_content_path(@page_content.id)
    else
      flash[:alert] = "存在しないページです"
      redirect_to page_contents_path
    end
  end
  
  def new
    @unregister_page_content = unregister_page_content
    logger.debug("--------------------------- unregister_page_content = #{@unregister_page_content}")
    @upc = Hash.new()
    @unregister_page_content.each do |upc|
      @upc[UserType.find_by(id: upc.to_i).type_name] = upc.to_i
    end
    logger.debug("--------------------------- upc = #{@upc}")
    @page_content = PageContent.new
  end
  
  def create
    @page_content = PageContent.new(page_content_params)
      if !PageContent.find_by(user_type_id: @page_content.user_type_id) && @page_content.save
        flash[:notice] = "作成しました"
        redirect_to page_contents_path
      else
        flash[:alert] = "作成できませんでした"
        redirect_back(fallback_location: root_path)
      end
  end
  
  def edit
    @page_content = PageContent.find_by(id: params[:id])
  end
  
  def update
    if PageContent.find_by(id: params[:id]).update(page_content_params)
      flash[:notice]  = "更新しました"
      redirect_to page_contents_path
    else
      flash[:alert] = "更新できませんでした"
      redirect_back(fallback_location: root_path)      
    end
  end
  
  def destroy
  end
  
  #------  private method  --------
  
  private 
  
     def show_error?
       if PageContent.find_by(id: params[:id])
         return true
       else
         return false
       end
     end
  
     def page_content_params
       params.require(:page_content).permit(:user_type_id, :content)
     end
     
     
  
     def admin_user
       if user_signed_in? && User.find_by(id: current_user.id).user_type == "1"
         return true
       else
         flash[:alert] = "閲覧権限がありません"
         redirect_to root_path
       end
     end
     
    #  必ずお読みくださいでまだ登録されていないuser_typeのIDをあげるメソッド
     def unregister_page_content
       
       user_type = []
       register_type = []
      # unregister_type = []
       
       UserType.all.each do |ut|
         user_type.push(ut.id)
       end
       
       PageContent.all.each do |pc|
         register_type.push(pc.user_type_id)
       end
       
       return user_type - register_type
       
     end
  
end
