module Api
  module V1
    class UsersController < BaseController
      # POST /api/v1/users/find_or_register
      # medirosaからの予約時にユーザーを検索・登録する
      def find_or_register
        email = params[:email]

        if email.blank?
          render json: { error: "メールアドレスが必要です" }, status: :bad_request
          return
        end

        user = User.find_by(email: email)

        if user.nil?
          # (1) mstarcosmicに未登録 → 新規作成
          # パスワードはmedirosaから渡されたものを使う、なければデフォルト
          pw = params[:password].presence || "medirosa"
          user = User.new(
            email: email,
            password: pw,
            password_confirmation: pw,
            user_type: "12",
            registration_status: false,
            name: params[:name] || "",
            name_kana: params[:name_kana] || "",
            tel: params[:tel] || "",
            gender: params[:gender] || ""
          )

          # Deviseのconfirmableを使っている場合、確認をスキップ
          user.skip_confirmation! if user.respond_to?(:skip_confirmation!)

          if user.save
            render json: { user_id: user.id, status: "created", user_type: user.user_type }, status: :created
          else
            render json: { error: user.errors.full_messages }, status: :unprocessable_entity
          end

        elsif user.user_type == "11" && user.registration_status == false
          # (2) 仮会員 → user_type: 12に変更
          user.update(user_type: "12")
          render json: { user_id: user.id, status: "updated_from_temporary", user_type: user.user_type }

        else
          # (3) それ以外 → user_typeそのまま、registration_status: true
          user.update(registration_status: true) unless user.registration_status
          render json: { user_id: user.id, status: "existing", user_type: user.user_type }
        end
      end
    end
  end
end
