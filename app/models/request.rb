class Request < ApplicationRecord
    belongs_to :reservation
    belongs_to :request_content
end
