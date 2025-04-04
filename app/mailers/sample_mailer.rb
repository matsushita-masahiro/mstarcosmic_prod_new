class SampleMailer < ApplicationMailer
  
  def send_when_create(reservation,user)
    @reservation = reservation
    @user = user
    mail to:      @user.email,
    subject: 'm☆COSMIC ご予約確認'
  end
  
  def send_when_create_new(root_reserve,user,frames)
    @reserve = root_reserve
    @reserved_space = display_time(@reserve.reserved_space)
    @frames = frames
    @user = user
    mail to:      @user.email,
    subject: 'm☆COSMIC ご予約確認'
  end 
 
  
end

