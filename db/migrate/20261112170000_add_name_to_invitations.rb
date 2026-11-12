class AddNameToInvitations < ActiveRecord::Migration[8.1]
  def change
    # The invitee's name as the admin typed it; pre-fills the acceptance form. Nullable for
    # invitations sent before names existed.
    add_column :invitations, :name, :string
  end
end
