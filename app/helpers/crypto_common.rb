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

  def CryptoCommon.scale_with_metrics(val, metrics)
    val_from_bottom = val - metrics.min 
    val_from_bottom.to_f / metrics.range.to_f
  end 

  # This will scale from zero to one
  def CryptoCommon.scale_array(array, metrics)
    output = [] 
    array.each do |val|
      output << CryptoCommon::scale_with_metrics(val, metrics)
    end 
    output 
  end

  def CryptoCommon.scale_out_with_metrics(value, metrics)
    point_in_range = metrics.range * value
    metrics.min + point_in_range
  end

  def CryptoCommon.transform_output(output, metrics)
    scale_out_with_metrics(output[0], metrics)
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

  class ModelContext
    attr_accessor :day_array
    attr_accessor :close_array
    attr_accessor :volume_array

    attr_accessor :close_delta_array
    attr_accessor :volume_delta_array

    attr_accessor :scaled_close_array
    attr_accessor :scaled_volume_array

    attr_accessor :close_metrics
    attr_accessor :volume_metrics

    attr_accessor :predictions_raw
    attr_accessor :predictions_scaled
    attr_accessor :predictions_price
    attr_accessor :predictions_price_error
    attr_accessor :predictions_price_error_pct

    attr_accessor :baseline_error
    attr_accessor :baseline_error_pct

    def initialize
      @day_array = []
      @close_array = []
      @volume_array = []
      @close_delta_array = [0.0]
      @volume_delta_array = [0.0]
      @baseline_error = [0.0]
      @baseline_error_pct = [0.0]
      clear_predictions
    end

    def number_of_data_points
      @close_array.size
    end

    def clear_predictions 
      @predictions_raw = [0.0]
      @predictions_scaled = [0.0]
      @predictions_price = [0.0]
      @predictions_price_error = [0.0]
      @predictions_price_error_pct = [0.0]
    end

    def calc_metrics 
      # TODO calc the deltas, then use the metrics for the deltas
      # because those will be your data points
      @close_delta_array = [0.0]
      @volume_delta_array = [0.0]
      (1..number_of_data_points - 1).each do |i|
        #puts i
        @close_delta_array << @close_array[i] - @close_array[i - 1]
        @volume_delta_array << @volume_array[i] - @volume_array[i - 1]
      end

      @close_metrics = get_metrics(@close_delta_array)
      puts "Close metrics:  #{@close_metrics.to_display}"
      @scaled_close_array = CryptoCommon::scale_array(@close_delta_array, @close_metrics)

      @volume_metrics = get_metrics(@volume_delta_array)
      puts "Volume metrics: #{@volume_metrics.to_display}"
      @scaled_volume_array = CryptoCommon::scale_array(@volume_delta_array, @volume_metrics)
    end 

    # The error rate if we had just predicted the same as yesterday
    def calc_baseline_error_pct 
      last_price = nil 
      index = 0
      count = 0
      total_error_pct = 0.0
      @close_array.each do |price|
        if last_price.nil?
          last_price = price 
        else 
          baseline_price_error = (last_price - price).abs
          baseline_price_error_pct = baseline_price_error / price
          @baseline_error << baseline_price_error
          @baseline_error_pct << baseline_price_error_pct
          total_error_pct = total_error_pct + baseline_price_error_pct
          count = count + 1
          last_price = price
        end 
        index = index + 1
      end

      total_error_pct / count
    end

    def get_metrics(array)
      metrics = DataMetrics.new 
      array.each do |val|
        if not val.nil?
          metrics.sum = metrics.sum + val 
          metrics.cnt = metrics.cnt + 1
          if metrics.min.nil? 
            metrics.min = val 
          elsif val < metrics.min 
            metrics.min = val 
          end
          if metrics.max.nil? 
            metrics.max = val 
          elsif val > metrics.max
            metrics.max = val 
          end
        end
      end
      metrics.avg = metrics.sum.to_f / metrics.cnt.to_f
      metrics.med = array[metrics.cnt / 2]
      metrics 
    end

    def to_display
      "Day array:    #{day_array.size}\nClose array:  #{close_array.size}\nVolume array: #{volume_array.size}"
    end

    def debug_at_index(start_index, number_to_display)
      col_width = 12
      label_str = ""
      day_str = ""
      price_str = ""
      vol_str = ""
      delta_price_str = ""
      delta_vol_str = ""
      scaled_price_str = ""
      scaled_vol_str = ""

      pred_raw_str = ""
      pred_scaled_str = ""
      pred_price_str = ""
      pred_price_error_str = ""
      pred_price_error_pct_str = ""

      baseline_error_str = ""
      baseline_error_pct_str = ""

      (start_index..start_index + number_to_display - 1).each do |i|
        label_str = label_str + pad(i, col_width)
        day_str = day_str + pad(@day_array[i], col_width)
        price_str = price_str + pad(@close_array[i].round(2), col_width)
        vol_str = vol_str + pad(@volume_array[i].round, col_width)
        delta_price_str = delta_price_str + pad(@close_delta_array[i].round(3), col_width)
        delta_vol_str = delta_vol_str + pad(@volume_delta_array[i].round(3), col_width)
        scaled_price_str = scaled_price_str + pad(@scaled_close_array[i].round(3), col_width)
        scaled_vol_str = scaled_vol_str + pad(@scaled_volume_array[i].round(3), col_width)

        if @predictions_raw[i]
          pred_raw_str = pred_raw_str + pad(@predictions_raw[i].round(3), col_width)
          pred_scaled_str = pred_scaled_str + pad(@predictions_scaled[i].round(3), col_width)
          pred_price_str = pred_price_str + pad(@predictions_price[i].round(3), col_width)
          pred_price_error_str = pred_price_error_str + pad(@predictions_price_error[i].round(3), col_width)
          pred_price_error_pct_str = pred_price_error_pct_str + pad(@predictions_price_error_pct[i].round(3), col_width)
        else 
          pred_raw_str = pred_raw_str + pad('', col_width)
          pred_scaled_str = pred_scaled_str + pad('', col_width)
          pred_price_str = pred_price_str + pad('', col_width)
          pred_price_error_str = pred_price_error_str + pad('', col_width)
          pred_price_error_pct_str = pred_price_error_pct_str + pad('', col_width)

        end

        baseline_error_str = baseline_error_str + pad(@baseline_error[i].round(3), col_width)
        baseline_error_pct_str = baseline_error_pct_str + pad(@baseline_error_pct[i].round(3), col_width)
      end 

      puts "Index:      #{label_str}"
      puts "Day:        #{day_str}" 
      puts " "
      puts "Close:      #{price_str}"
      puts "Delta:      #{delta_price_str}" 
      puts "Scaled:     #{scaled_price_str}" 
      puts "Predicted:  #{pred_raw_str}" 
      puts "PredScale:  #{pred_scaled_str}" 
      puts "PredPrice:  #{pred_price_str}" 
      puts "PredError:  #{pred_price_error_str}"
      puts "PredErrPct: #{pred_price_error_pct_str}"
      puts "BaseError:  #{baseline_error_str}"
      puts "BaseErrPct: #{baseline_error_pct_str}"
      puts " "
      puts "Vol:        #{vol_str}" 
      puts "Delta:      #{delta_vol_str}" 
      puts "Scale:      #{scaled_vol_str}"
    end
  end

  def load_data_in_context(filename, context)
    temp_count = 0
    File.readlines(filename).each do |line|
      line = line.chomp
      parts = line.split(",")
      day = parts[1]
      close = parts[2].to_f
      vol = parts[3].to_f
      #puts "[#{temp_count}]  #{day} => #{close}  (#{vol})"
      context.day_array << day
      context.close_array << close
      context.volume_array << vol
    
      temp_count = temp_count + 1
    end
  end

  def assess_results(context, n, output_lines, start_assess_index = 0)
    baseline_error_pct = context.calc_baseline_error_pct
    m = context.get_metrics(context.predictions_price_error_pct[start_assess_index+n..-1]) 
    improvement = baseline_error_pct.abs - m.avg.abs 
    improvement_str = "%.5f" % improvement
    output_lines << "Average Percent Error (saved model n = #{n})"
    assessment = "MEH"
    if improvement > 0
      assessment = "GOOD !!!    #{m.avg.round(5)} < #{baseline_error_pct.round(5)}"
    end
    output_lines << "Improvement: #{improvement_str}   #{assessment}"
    output_lines << m.to_display
    output_lines << " "
  end

  def save_predicted_prices(filename, context)
    open(filename, 'w') { |f|
      index = 0
      context.predictions_price.each do |pred_price|
        if index == 0
          # skip
        elsif pred_price.nil?
          # skip
        else
          f.puts "#{index},#{context.day_array[index]},#{pred_price.round(5)}"
        end
        index = index + 1
      end
    }
  end
end


