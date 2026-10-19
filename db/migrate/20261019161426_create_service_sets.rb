class CreateServiceSets < ActiveRecord::Migration[8.1]
  def change
    create_table :service_sets do |t|
      t.references :church, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.date :service_date

      t.timestamps
    end

    add_index :service_sets, [ :church_id, :service_date ]

    # The inline-slide FK deferred from Phase 5 (text_slides.set_id → service_sets); an inline
    # slide is destroyed with its owning set.
    add_foreign_key :text_slides, :service_sets, column: :set_id, on_delete: :cascade
  end
end
