class Coupon < ApplicationRecord
    
    validates :remarks, length: { maximum: 10 } 

    belongs_to :payment
    

    
end
