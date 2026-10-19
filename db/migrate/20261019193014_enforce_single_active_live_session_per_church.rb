class EnforceSingleActiveLiveSessionPerChurch < ActiveRecord::Migration[8.1]
  def up
    # Resolve any pre-existing duplicates so the unique index can be created: for each church,
    # keep the most recent active session and end the older ones.
    execute(<<~SQL)
      UPDATE live_sessions l
      SET status = 'ended', ended_at = COALESCE(ended_at, now())
      WHERE status = 'active'
        AND id NOT IN (
          SELECT DISTINCT ON (church_id) id
          FROM live_sessions
          WHERE status = 'active'
          ORDER BY church_id, created_at DESC, id DESC
        );
    SQL

    add_index :live_sessions, :church_id, unique: true,
      where: "status = 'active'", name: "index_one_active_live_session_per_church"
  end

  def down
    remove_index :live_sessions, name: "index_one_active_live_session_per_church"
  end
end
