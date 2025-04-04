class MetatronSaleInquiryMailer < ApplicationMailer
  def send_when_inquiry(inquiry)
    @inquiry = inquiry
    mail to:      @inquiry.email,
    subject: 'm☆COSMIC メタトロン購入　お問合せ確認'
  end
  
  def send_when_inquiry_admin(inquiry)
    @inquiry = inquiry
    mail to:      ENV['USER_EMAIL'],
    subject: 'm☆COSMIC メタトロン購入 お問合せ受信'
  end
  
  def send_when_answer(answer,inquiry)
    @inquiry = inquiry
    logger.debug("======----------------------- send_when_answer email = #{inquiry.email}")
    @answer = answer
    mail to:      @inquiry.email,
    subject: 'm☆COSMIC メタトロン購入 お問合せへのご回答'
  end
  
  def send_when_answer_admin(answer,inquiry)
    @inquiry = inquiry
    @answer = answer
    mail to:      ENV['USER_EMAIL'],
    subject: 'm☆COSMIC　メタトロン購入 お問合せへの回答'
  end
  
  
  
end
