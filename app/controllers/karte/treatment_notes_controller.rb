module Karte
  # 施術メモ。カルテ詳細から作成・編集・削除する。
  # 一覧は患者ごとにカルテ詳細で表示するため index は持たない。
  class TreatmentNotesController < BaseController
    before_action :set_patient
    before_action :set_note, only: %i[edit update destroy]

    def create
      @note = @patient.treatment_notes.new(note_params)
      @note.author = current_user
      @note.author_name = author_name_param

      if @note.save
        log_access!(patient: @patient, action: "note_create")
        redirect_to karte_user_path(@patient, anchor: "notes"), notice: "施術メモを記録しました。"
      else
        redirect_to karte_user_path(@patient, anchor: "notes"),
                    alert: @note.errors.full_messages.join(" / ")
      end
    end

    def edit
      log_access!(patient: @patient, action: "note_edit")
    end

    def update
      # 担当者は記録時のものを保持する。あとから書き換えると
      # 誰が施術したかの記録として成立しなくなるため、本文と券欄のみ更新する。
      if @note.update(note_params)
        log_access!(patient: @patient, action: "note_update")
        redirect_to karte_user_path(@patient, anchor: "notes"), notice: "施術メモを更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @note.destroy
      log_access!(patient: @patient, action: "note_destroy")
      redirect_to karte_user_path(@patient, anchor: "notes"), notice: "施術メモを削除しました。"
    end

    private

    def set_patient
      @patient = User.find(params[:user_id])
    end

    def set_note
      @note = @patient.treatment_notes.find(params[:id])
    end

    def note_params
      params.require(:treatment_note).permit(:visited_on, :ticket, :body)
    end

    # 代理入力に備えて担当者を選べるようにする。
    # 選択肢はスタッフに限り、指定が無ければログイン中の本人。
    def author_name_param
      requested = params[:treatment_note][:author_name].to_s.strip
      return current_user.name if requested.blank?

      User.karte_staff.exists?(name: requested) ? requested : current_user.name
    end
  end
end
