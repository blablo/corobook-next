class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Corobook <no-reply@#{ENV.fetch('MAIL_DOMAIN', 'example.com')}>")
  layout "mailer"
end
