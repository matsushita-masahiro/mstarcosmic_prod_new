class SignupMailer < ApplicationMailer
  def send_when_signup(user)
    @user = user
    mail to:      @user.email,
    subject: 'm☆COSMIC　無料会員登録・変更'
  end
  
  def send_when_signup_admin(user)
    @user = user
    mail to: ENV['USER_EMAIL'],
    subject: 'm☆COSMIC　無料会員登録・変更報告'
  end  
end
