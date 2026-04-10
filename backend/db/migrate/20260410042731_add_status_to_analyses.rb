class AddStatusToAnalyses < ActiveRecord::Migration[7.2]
  def change
    add_column :analyses, :status, :string, null: false, default: "pending"
  end
end
