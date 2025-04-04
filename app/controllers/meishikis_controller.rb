class MeishikisController < ApplicationController
  
  layout 'main/main'
  
  before_action :authenticate_admin_user?
  
  def new
    @meishiki = Meishiki.new
  end
  
  def create
    @meishiki = Meishiki.new(meishiki_params)
    if @meishiki.save
      flash[:notice] = "命式保存しました"
      redirect_to meishikis_path
    else
      flash[:notice] = "命式保存できませんでした"
      render 'new'
    end
  end

  def index

      @meishikis = Meishiki.search(params[:search])

  end

  def show
    @meishiki = Meishiki.find_by(id: params[:id])
  end
  
  def destroy
    @meishiki = Meishiki.find_by(id: params[:id])
    if @meishiki.destroy
    else
    end
  end
  
  private
    def meishiki_params
      params.require(:meishiki).permit(:name, :meishiki, :meishiki_category_id)
    end
    

end
