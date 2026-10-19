class CreateChurches < ActiveRecord::Migration[8.1]
  def change
    create_table :churches do |t|
      t.string :name, null: false
      t.string :ccli_license_number

      t.timestamps
    end
  end
end
