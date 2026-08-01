class KarteAccessLog < ApplicationRecord
  belongs_to :actor,   class_name: "User"
  belongs_to :patient, class_name: "User"

  self.record_timestamps = false

  def self.record!(actor:, patient:, action:, resource: nil, request: nil)
    create!(
      actor: actor, patient: patient, action: action,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent&.truncate(255),
      created_at: Time.current
    )
  end
end
