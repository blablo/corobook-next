class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    # The user's chosen UI language. NULL = not chosen yet, so fall back to geo/Accept-Language
    # detection at request time. Constrained to the locales the app actually ships.
    add_column :users, :locale, :string
    add_check_constraint :users,
      "locale IS NULL OR locale::text = ANY (ARRAY['en'::character varying, 'es'::character varying]::text[])",
      name: "users_locale_check"
  end
end
