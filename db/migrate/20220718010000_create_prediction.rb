class CreatePrediction < ActiveRecord::Migration[7.0]
  def change
    create_table :crypto_predictions do |t|
      t.integer :run_id
      t.string :day
      t.float :price
      t.float :actual_price
      t.float :error_amount
      t.float :error_pct
      t.timestamps
    end
  end
end
