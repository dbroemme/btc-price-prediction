require 'yaml'
require 'json'

module CryptoCommon

  def CryptoCommon.get_current_btc_in_usc
    uri = URI("https://blockchain.info/ticker")
    output = Net::HTTP.get(uri)
    parsed = JSON.parse(output)
    price = parsed["USD"]["15m"].to_f
  end 

  def CryptoCommon.pad(m, length, left_align = false)
    str = m.to_s
    if left_align
        return str[0, length].ljust(length, ' ')
    end
    str[0, length].rjust(length, ' ')
  end

  class DataMetrics
    attr_accessor :cnt
    attr_accessor :min
    attr_accessor :max
    attr_accessor :avg
    attr_accessor :med
    attr_accessor :sum
    attr_accessor :range

    def initialize 
      @cnt = 0
      @min = 100000.0
      @max = -100000.0
      @avg = 0.0 
      @med = nil 
      @sum = 0.0 
      @range = 0.0
    end 

    def calc_range 
      @range = @max - @min
    end

    def to_display 
      "Metrics cnt: #{@cnt}  min: #{@min}  max: #{@max}  avg: #{@avg}  med: #{@med}  sum: #{@sum}  range: #{@range}"
    end
  end

  class PricePredictionApiOutput
    attr_accessor :day
    attr_accessor :price
    def initialize(d, p)
      @day = d 
      @price = p 
    end
  end 

  class CryptoClosingPrice
    attr_accessor :index
    attr_accessor :day
    attr_accessor :price
    attr_accessor :volume
    attr_accessor :price_delta

    attr_accessor :price_delta_pct
    attr_accessor :price_delta_scaled

    def initialize(i, d, price, v, delta)
      @index = i
      @day = d 
      @price = price
      @volume = v 
      @price_delta = delta
    end 
  end 

  class BasePredict 
    def scale_array(array, metrics)
      output = [] 
      array.each do |val|
        output << scale_with_metrics(val, metrics)
      end 
      output 
    end

    def transform_output(output, metrics)
      scale_out_with_metrics(output[0], metrics)
    end  

    def scale_with_metrics(val, metrics)
      val_from_bottom = val - metrics.min 
      val_from_bottom.to_f / metrics.range.to_f
    end 
  
    def scale_out_with_metrics(value, metrics)
      point_in_range = metrics.range * value
      metrics.min + point_in_range
    end
  end 

  class SevenDayPricePredict < BasePredict
    attr_accessor :number_of_inputs 
    attr_accessor :hidden_layers 
    attr_accessor :network_filename

    def initialize
      @number_of_inputs = 7
      @hidden_layers = [12] 
      @network_filename = "./storage/btc_seven.net"
    end
  end

  class TenDayPricePredict < BasePredict
    attr_accessor :number_of_inputs 
    attr_accessor :hidden_layers 
    attr_accessor :network_filename

    def initialize
      @number_of_inputs = 10
      @hidden_layers = [16] 
      @network_filename = "./storage/btc_three.net"
    end
  end

  class TwentyDayPricePredict < BasePredict
    attr_accessor :number_of_inputs 
    attr_accessor :hidden_layers 
    attr_accessor :network_filename

    def initialize
      @number_of_inputs = 20
      @hidden_layers = [32,16] 
      @network_filename = "./storage/btc_twenty.net"
    end
  end

  class ThirtyDayPricePredict < BasePredict
    attr_accessor :number_of_inputs 
    attr_accessor :hidden_layers 
    attr_accessor :network_filename

    def initialize
      @number_of_inputs = 30
      @hidden_layers = [24,16] 
      @network_filename = "./storage/btc_thirty.net"
    end
  end

end