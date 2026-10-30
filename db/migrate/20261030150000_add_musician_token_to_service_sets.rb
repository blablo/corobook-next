class AddMusicianTokenToServiceSets < ActiveRecord::Migration[8.1]
  # A permanent musician link per service (/m/s/:token), so it can be emailed before going live.
  # Separate from the per-run LiveSession#musician_token, which is minted at launch and cleared
  # when the service ends.
  class ServiceSetRow < ActiveRecord::Base
    self.table_name = "service_sets"
  end

  def up
    add_column :service_sets, :musician_token, :string
    ServiceSetRow.reset_column_information
    ServiceSetRow.find_each { |s| s.update_columns(musician_token: SecureRandom.urlsafe_base64(24)) }
    add_index :service_sets, :musician_token, unique: true
  end

  def down
    remove_index :service_sets, :musician_token
    remove_column :service_sets, :musician_token
  end
end
