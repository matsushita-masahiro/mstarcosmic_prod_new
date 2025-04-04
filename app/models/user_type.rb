class UserType < ApplicationRecord
    has_many :pay_types, :dependent => :destroy
end
