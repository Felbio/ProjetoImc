class CreateImcs < ActiveRecord::Migration[7.0]
  def change
    create_table :imcs do |t|
      t.decimal :weight
      t.decimal :height
     
    end
  end
end
