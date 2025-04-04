class Inquiry < ApplicationRecord
    has_many :answers, dependent: :destroy
end
