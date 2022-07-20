class CreateCrypto < ActiveRecord::Migration[7.0]
  def change
    create_table :crypto_data do |t|
      t.string :day
      t.float :price
      t.float :price_delta
      t.integer :volume
      t.timestamps
    end
  end
end
