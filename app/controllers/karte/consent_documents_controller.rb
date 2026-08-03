module Karte
  # 同意書の管理。
  #
  # 【最重要】署名済みの同意書は編集させない。
  # Consent は consent_document を参照しているだけなので、本文を書き換えると
  # 過去の署名が「いま表示されている文言に同意した」ことになってしまう。
  # 同意書として成立しなくなるため、変更は必ず新しいバージョンを作る。
  # 編集を許すのは署名が0件のときだけ（公開前の下書き、または誤って作ったもの）。
  #
  # ConsentDocument.current は published のうち published_at が最新の1件。
  # 新しいバージョンを公開すると、その瞬間から全員が未署名扱いになり、
  # 次回来店時に再署名が必要になる。公開前に必ず確認を出す。
  class ConsentDocumentsController < BaseController
    before_action :set_document, only: %i[show edit update publish archive destroy]
    before_action :ensure_editable, only: %i[edit update destroy]

    def index
      @documents = ConsentDocument.order(Arel.sql("COALESCE(published_at, created_at) DESC"))
      @signed_counts = Consent.group(:consent_document_id).count
      @current = ConsentDocument.current
    end

    def show
      @signed_count = @document.consents.count
    end

    def new
      # 既存の版から本文を引き継いで新バージョンを作れるようにする。
      # 一から書き直すより、直したい箇所だけ触る方が事故が少ない。
      source = params[:from].present? ? ConsentDocument.find_by(id: params[:from]) : nil
      @document = ConsentDocument.new(
        title: source&.title,
        body: source&.body,
        version: suggested_version
      )
    end

    def create
      @document = ConsentDocument.new(document_params)

      if @document.save
        redirect_to karte_consent_document_path(@document),
                    notice: "下書きとして保存しました。内容を確認してから公開してください。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @document.update(document_params)
        redirect_to karte_consent_document_path(@document), notice: "更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # 公開すると current が切り替わり、全員が未署名扱いになる。
    def publish
      @document.update!(published_at: Time.current, archived_at: nil)
      redirect_to karte_consent_document_path(@document),
                  notice: "公開しました。以降の署名はこのバージョンに紐づきます。"
    end

    def archive
      @document.update!(archived_at: Time.current)

      notice = "アーカイブしました。"
      notice += "　※ 公開中の同意書が無くなりました。患者側の同意書ページが開けません。" \
        if ConsentDocument.current.nil?

      redirect_to karte_consent_documents_path, notice: notice
    end

    def destroy
      # has_many :consents, dependent: :restrict_with_error があるため
      # 署名済みは DB 側でも守られている。ensure_editable と二重の防御。
      if @document.destroy
        redirect_to karte_consent_documents_path, notice: "削除しました。"
      else
        redirect_to karte_consent_document_path(@document),
                    alert: @document.errors.full_messages.join(" / ")
      end
    end

    private

    def set_document
      @document = ConsentDocument.find(params[:id])
    end

    def ensure_editable
      return if @document.consents.empty?

      redirect_to karte_consent_document_path(@document),
                  alert: "署名済みの同意書は変更できません。" \
                         "文言を変える場合は新しいバージョンを作成してください。"
    end

    def document_params
      params.require(:consent_document).permit(:version, :title, :body)
    end

    # 版番号の初期値。日付にしておくと、いつの文言かが署名記録から追える。
    def suggested_version
      base = Date.current.strftime("%Y-%m-%d")
      return base unless ConsentDocument.exists?(version: base)

      2.step do |n|
        candidate = "#{base}-#{n}"
        return candidate unless ConsentDocument.exists?(version: candidate)
      end
    end
  end
end
