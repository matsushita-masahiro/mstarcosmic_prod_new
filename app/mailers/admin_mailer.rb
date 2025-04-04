class AdminMailer < ApplicationMailer
  
  def send_when_reserved(reservation,user)
    @reservation = reservation
    @admin = User.find_by(email: ENV['USER_EMAIL'], user_type: "1")
    @user = user
    mail to:      @admin.email,
    subject: 'm☆COSMIC ご予約を受けました'
  end
  
  
  def send_when_reserved_new(root_reserve,user,frames)
    @reserve = root_reserve
    @frames = frames
    @reserved_space = display_time(@reserve.reserved_space)
    @admin = User.find_by(email: ENV['USER_EMAIL'], user_type: "1")
    @user = user
    mail to:      @admin.email,
    subject: 'm☆COSMIC ご予約を受けました'
  end  
  
  def machine_schedule_error(machine, info)
    @machine = machine
    @error_array = info
    @admin = User.find_by(email: ENV['USER_EMAIL'], user_type: "1")
    mail to:      @admin.email,
    subject: 'm☆COSMIC 出張登録エラーです'    
  end
end



