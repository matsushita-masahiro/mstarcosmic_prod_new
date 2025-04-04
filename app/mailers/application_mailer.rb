class ApplicationMailer < ActionMailer::Base
  
  def display_time(x)
      if x-x.to_i == 0
          result = "#{x.to_i}:00"
      else
          result = "#{x.to_i}:#{((x-x.to_i)*60).to_i}"
      end
    return  result 
  end
  
  
  default from: ENV['USER_EMAIL']
  layout 'mailer'
end
