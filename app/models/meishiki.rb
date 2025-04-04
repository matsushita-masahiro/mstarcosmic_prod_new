class Meishiki < ApplicationRecord
    mount_uploader :meishiki, ImageUploader
    
    belongs_to :meishiki_category
    
    
  def self.search(search) #self.でクラスメソッドとしている
    logger.debug("~~~~~~~~~~~~~~~~~~~~~~~search  => #{search}")

    if !search.nil?
        logger.debug("~~~~~~~~~~~~~~~~~~~~~~~search  !=> nil")

        if search[:name].present?
          Meishiki.where("name LIKE ?","%#{search[:name]}%").order(created_at: :desc)
        else
          Meishiki.all.order(created_at: :desc) #全て表示。
        end
    else
        Meishiki.all.order(created_at: :desc) #全て表示。
    end
  end    
    
    
    
    
    
    
end
