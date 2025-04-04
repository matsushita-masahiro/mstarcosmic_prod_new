class RequestContent < ApplicationRecord
    validates :content, uniqueness: true
end
