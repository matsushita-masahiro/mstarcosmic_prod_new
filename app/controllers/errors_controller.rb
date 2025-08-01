class ErrorsController < ApplicationController
  def routing_error
    # 404エラーページを表示するか、適切なページにリダイレクト
    render file: Rails.root.join('public', '404.html'), status: :not_found, layout: false
  rescue ActionView::MissingTemplate
    # 404.htmlが存在しない場合の代替処理
    render plain: "404 Not Found", status: :not_found
  end
end