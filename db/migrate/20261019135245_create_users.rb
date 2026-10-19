class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :church, null: false, foreign_key: true, index: false
      t.citext :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "editor"

      t.timestamps
    end

    add_index :users, [ :church_id, :email ], unique: true
    add_check_constraint :users, "role IN ('admin', 'editor')", name: "users_role_check"
  end
end
