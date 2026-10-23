# frozen_string_literal: true

# Resolves the UI language for each request and keeps it stable across links.
#
# Precedence (first that yields a supported locale wins):
#   1. an explicit ?locale= on this request (also persisted for a signed-in user),
#   2. the signed-in user's saved locale column,
#   3. geo / browser hint — Accept-Language: a Spanish preference (incl. es-MX) → :es,
#      which is our proxy for "looks like Mexico" until a real GeoIP source is added,
#   4. the app default (:en).
#
# `default_url_options` carries the locale on generated URLs only when it differs from
# the default, so English URLs stay clean and a chosen Spanish sticks as you navigate.
module Localized
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
    helper_method :current_locale
  end

  private

  def switch_locale(&action)
    locale = resolve_locale
    I18n.with_locale(locale, &action)
  end

  def resolve_locale
    from_params || current_user&.locale.presence&.to_sym || from_accept_language || I18n.default_locale
  end

  # ?locale=es — persist it for a signed-in user so it follows them to any device.
  def from_params
    requested = params[:locale].to_s
    return nil unless supported?(requested)

    requested = requested.to_sym
    if current_user && current_user.locale != requested.to_s
      current_user.update_column(:locale, requested.to_s)
    end
    requested
  end

  # Proxy for region: a Spanish-preferring browser (es, es-MX, es-419…) → Spanish.
  def from_accept_language
    header = request.env["HTTP_ACCEPT_LANGUAGE"].to_s
    return nil if header.blank?

    primary = header.split(",").first.to_s.downcase
    return :es if primary.start_with?("es")

    nil
  end

  def supported?(locale)
    I18n.available_locales.map(&:to_s).include?(locale.to_s)
  end

  def current_locale = I18n.locale

  # Keep the locale in generated URLs only when it isn't the default.
  def default_url_options
    I18n.locale == I18n.default_locale ? {} : { locale: I18n.locale }
  end
end
