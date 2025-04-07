class Payment < ApplicationRecord
    has_many :coupons, :dependent => :destroy
    belongs_to :user
end
