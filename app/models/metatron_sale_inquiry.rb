class MetatronSaleInquiry < ApplicationRecord
    
     validates :name, presence: true
     validates :name_kana, presence: true
     validates :phone, presence: true
     validates :email, presence: true
    # validates :postcode, presence: true
     validates :prefecture_code, presence: true
     validates :address_city, presence: true
     
     has_many :ms_inquiry_answers, :dependent => :destroy
     
    # jp_prefecture
     include JpPrefecture
     jp_prefecture :prefecture_code
      
     def prefecture_name
         JpPrefecture::Prefecture.find(code: prefecture_code).try(:name)
     end   
      
     def prefecture_name=(prefecture_name)
         self.prefecture_code = JpPrefecture::Prefecture.find(name: prefecture_name).code
     end     
    
end
