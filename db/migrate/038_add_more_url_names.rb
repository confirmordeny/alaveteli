class AddMoreUrlNames < ActiveRecord::Migration[4.2] # 2.0
  def self.up
    add_column :users, :url_name, :text

    User.find_each do |user|
      user.update_url_name
      user.save!
    end
    # MySQL cannot index text blobs like this
    if ActiveRecord::Base.connection.adapter_name != "MySQL"
      add_index :users, :url_name
    end
    change_column :users, :url_name, :text, null: false
  end

  def self.down
    remove_column :users, :url_name
  end
end
