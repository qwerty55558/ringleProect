class AddStudyProfanityOffensesToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :study_profanity_offenses, :integer, null: false, default: 0
  end
end
