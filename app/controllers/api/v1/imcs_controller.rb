class Api::V1::ImcsController < ApplicationController
  
  def index
    @imcs = Imc.all
    render json: @imcs
  end

  def create
    data_json = JSON.parse request.body.read

    @imc = Imc.new(data_json)
    @imc.imc_value = calculate(@imc.weight, @imc.height).round(2)
    @imc.classification = categorize_weight(@imc.imc_value)
    @imc.obesity = categorize_obesity(@imc.imc_value)      

    if @imc.save
      render json: @imc
    else
      render json: {error: 'imc not saved'}, status: unprocessable_entity
    end
  end

  def calculate(weight, height)
        return weight/(height * height)
  end

  def categorize_weight(value)
    if (value < 17)
        return "Muito abaixo do peso"
    end

    case value
    when 17.1...18.49
        return "Abaixo do peso"
    when 18.5...24.99
        return "Peso normal"
    when 25...29.99
        return "Acima do peso"
    else
        return "Está em Obesidade"
    end
  end
          
  def categorize_obesity(value)    
      if (value < 30)
        return "Não atingiu a obesidade"
      end
      case value
    when 31...34.99
        return "I"
    when 35...39.99
        return "II (severa)"
    else
        return "III (mórbida)"
    end
  end

end
