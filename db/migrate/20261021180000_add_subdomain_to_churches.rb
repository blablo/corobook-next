class AddSubdomainToChurches < ActiveRecord::Migration[8.1]
  def change
    add_column :churches, :subdomain, :citext
    add_index :churches, :subdomain, unique: true, where: "subdomain IS NOT NULL"
  end
end
