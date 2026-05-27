class MachineSchedule < ApplicationRecord
  # コントローラーのsync_machine_to_service_unavailabilityで一括同期するため
  # モデルレベルのコールバックは無効化
end
