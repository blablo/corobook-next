class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations do |t|
      t.references :church, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.citext   :email,        null: false
      t.string   :role,         null: false, default: "editor"
      t.string   :token_digest, null: false
      t.datetime :expires_at,   null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    # At most one PENDING (not-yet-accepted) invite per (church, email); accepted rows may accumulate.
    add_index :invitations, [ :church_id, :email ],
              unique: true, where: "accepted_at IS NULL", name: "index_pending_invitations"
    add_check_constraint :invitations,
                         "role::text = ANY (ARRAY['admin'::text, 'editor'::text])",
                         name: "invitations_role_check"
  end
end
