class CreateCrypto < ActiveRecord::Migration[7.0]
  def change
    create_table :crypto do |t|
      t.string :day
      t.float :close_price
      t.float :price_delta
      t.integer :volume
      t.timestamps
    end
  end
end
