class ServiceSetsMailer < ApplicationMailer
  # The planned service sent to one Band member. One message per recipient, so band members
  # never see each other's addresses. Replies go to the editor who sent it.
  #
  # locale is the sender's locale, used when the recipient has none of their own (the job runs
  # outside the request, so I18n.locale is not carried over on its own).
  def band(service_set, recipient, sender, locale = I18n.default_locale)
    @service_set = service_set
    @church      = service_set.church
    @sender      = sender
    @items       = service_set.ordered_items.to_a
    @url         = preview_service_set_url(service_set)
    @musician_url = service_musician_url(token: service_set.musician_token)

    I18n.with_locale(recipient.locale.presence || locale) do
      @date = service_set.service_date&.strftime(t("service_sets_mailer.band.date_format"))
      mail to: recipient.email,
           reply_to: sender.email,
           subject: t("service_sets_mailer.band.subject", church: @church.name, name: service_set.name)
    end
  end
end
