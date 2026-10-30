class AddBandMemberToUsers < ActiveRecord::Migration[8.1]
  def change
    # One Band group per church: a member is in the band when this flag is set.
    add_column :users, :band_member, :boolean, default: false, null: false
  end
end
