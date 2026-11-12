class AddNameToUsers < ActiveRecord::Migration[8.1]
  def change
    # Nullable: existing members have none yet; signup and invitation acceptance require it.
    add_column :users, :name, :string
  end
end
