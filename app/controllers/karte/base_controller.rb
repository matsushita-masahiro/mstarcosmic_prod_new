module Karte
  # スタッフ用カルテ画面の基底クラス。
  # 権限判定は既存の authenticate_staff_user?（user_type "1" または "10"）を使う。
  # 将来スタッフの権限範囲を変更する場合も、既存メソッドの変更に自動追従する。
  class BaseController < ApplicationController
    layout "main/main"

    before_action :authenticate_user!
    before_action :authenticate_staff_user?

    private

    # カルテ閲覧は必ず監査ログを残す
    def log_access!(patient:, action:, resource: nil)
      KarteAccessLog.record!(
        actor: current_user, patient: patient,
        action: action, resource: resource, request: request
      )
    end
  end
end
