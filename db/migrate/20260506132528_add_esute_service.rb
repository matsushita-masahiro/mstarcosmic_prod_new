class AddEsuteService < ActiveRecord::Migration[8.0]
  def up
    # 既存のseitaiを整体専用に修正
    execute <<-SQL
      UPDATE services SET display_name = '整体', max_duration = 60 WHERE name = 'seitai';
    SQL

    # エステサービスを追加
    execute <<-SQL
      INSERT INTO services (name, display_name, max_concurrent, min_duration, max_duration, active, created_at, updated_at)
      VALUES ('esute', 'エステ', 1, 60, 150, 1, datetime('now'), datetime('now'));
    SQL
  end

  def down
    execute <<-SQL
      UPDATE services SET display_name = '整体・エステ', max_duration = 60 WHERE name = 'seitai';
    SQL
    execute <<-SQL
      DELETE FROM services WHERE name = 'esute';
    SQL
  end
end
