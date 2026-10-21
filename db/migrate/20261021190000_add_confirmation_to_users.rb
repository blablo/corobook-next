class AddConfirmationToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :confirmed_at, :datetime
    add_column :users, :confirmation_token_digest, :string
    add_column :users, :confirmation_sent_at, :datetime
    add_index :users, :confirmation_token_digest, unique: true, where: "confirmation_token_digest IS NOT NULL"

    # Every pre-existing user predates the confirmation gate (invited members already proved email
    # ownership; seeded/admin users are trusted). Mark them all confirmed so none are locked out.
    execute "UPDATE users SET confirmed_at = NOW() WHERE confirmed_at IS NULL"
  end

  def down
    remove_index :users, :confirmation_token_digest
    remove_column :users, :confirmation_sent_at
    remove_column :users, :confirmation_token_digest
    remove_column :users, :confirmed_at
  end
end
