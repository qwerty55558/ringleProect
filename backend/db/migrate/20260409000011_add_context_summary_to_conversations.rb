class AddContextSummaryToConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :conversations, :context_summary, :text
  end
end
