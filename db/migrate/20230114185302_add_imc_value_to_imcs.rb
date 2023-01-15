class AddImcValueToImcs < ActiveRecord::Migration[7.0]
  def change
    add_column :imcs, :imc_value, :decimal
    add_column :imcs, :classification, :string
    add_column :imcs, :obesity, :string
    
  end
end
