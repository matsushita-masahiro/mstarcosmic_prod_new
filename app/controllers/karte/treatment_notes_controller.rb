module Karte
  # 施術記録。来店ごとのメモを専用画面で管理する。
  #
  # 同意書・問診票と同じページに置いていたが、書く頻度が違うため分離した。
  # 同意書と問診票は初回または改訂時、施術メモは来店のたび。
  # 同じページだとメモを書くだけのときに他をスクロールで通り過ぎることになる。
  class TreatmentNotesController < BaseController
    before_action :set_patient
    before_action :set_note, only: %i[edit update destroy]

    def index
      @note_q = params[:q].to_s.strip

      notes = @patient.treatment_notes.latest_first
      notes = notes.search(@note_q) if @note_q.present?
      @notes = notes.to_a

      @new_note = @patient.treatment_notes.new(visited_on: Date.current)
      @staff_choices = User.karte_staff.pluck(:name).compact_blank

      log_access!(patient: @patient, action: "notes_index")
    end

    def create
      @note = @patient.treatment_notes.new(note_params)
      @note.author = current_user
      @note.author_name = author_name_param

      if @note.save
        log_access!(patient: @patient, action: "note_create")
        redirect_to karte_user_treatment_notes_path(@patient), notice: "施術メモを記録しました。"
      else
        redirect_to karte_user_treatment_notes_path(@patient),
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
        redirect_to karte_user_treatment_notes_path(@patient), notice: "施術メモを更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @note.destroy
      log_access!(patient: @patient, action: "note_destroy")
      redirect_to karte_user_treatment_notes_path(@patient), notice: "施術メモを削除しました。"
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
