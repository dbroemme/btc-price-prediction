require 'crypto_common'

class CryptoController < ApplicationController
  include CryptoCommon

  def index
    puts "In crypto controller index"
  end

  def setup
    @train_config = CryptoData.new
    @data_count = CryptoData.count
  end 

  def deleteruns 
    CryptoPrediction.delete_all
  end

  def baseline 
    @price_data = get_price_data_from_database

    total_same_change_error_pct = 0.0
    total_no_change_error_pct = 0.0
    total_count = 0
    last_price = nil
    last_change = nil
    @price_data.each do |pd|
      if last_price.nil? 
        last_price = pd.price 
        last_change = pd.price_delta
      else 
        total_count = total_count + 1
        baseline_price_error = (last_price - pd.price).abs
        baseline_price_error_pct = baseline_price_error / pd.price
        total_no_change_error_pct = total_no_change_error_pct + baseline_price_error_pct

        baseline_price_error = ((last_price + last_change) - pd.price).abs
        baseline_price_error_pct = baseline_price_error / pd.price
        total_same_change_error_pct = total_same_change_error_pct + baseline_price_error_pct
        last_price = pd.price 
        last_change = pd.price_delta
      end
    end

    @baseline_same_change = ((total_same_change_error_pct / total_count) * 100).round(2)
    @baseline_no_change = ((total_no_change_error_pct / total_count) * 100).round(2)
  end 

  def train
    puts "In crypto controller train"
    @train_config = CryptoData.new(params.require(:crypto_data).permit(:volume))
    puts @train_config.inspect
    # TODO we are using an active record so the form is easier.
    #      should change this later
    training_index_cutoff = @train_config.volume

    @price_data = get_price_data_from_database
    persisted_metrics = File.read("./storage/context_metrics.txt")
    metrics = YAML::load(persisted_metrics)

    # Each of these is an array of arrays
    @input_array = []
    @desired_output_array = []

    (0..training_index_cutoff).each do |train_index|
      input = create_input_set_for_index(@price_data, train_index, 10, metrics)
      desired_output = get_desired_output_for_index(@price_data, train_index, 10, metrics)
      puts "Input:  #{input}  ->  #{desired_output}"
      @input_array << input 
      @desired_output_array << [desired_output]
    end

    train = RubyFann::TrainData.new(:inputs => @input_array,
                                    :desired_outputs => @desired_output_array)
    fann = RubyFann::Standard.new(:num_inputs => 10, 
                                  :hidden_neurons => [32],
                                  :num_outputs => 1)
    # 100 max_epochs, 20 errors between reports and 0.001 desired MSE (mean-squared-error)
    fann.train_on_data(train, 500, 20, 0.003)

    File.delete("./storage/btc.net") if File.exist? "./storage/btc.net"
    fann.save("./storage/btc.net")
    @network_trained = true

    redirect_to action: "test"
  end 

  def create_input_set_for_index(price_data_array, index, n, metrics)
    input = []
    price_data_array[index..index+n-1].each do |pd|
      input << pd.price_delta_pct
    end
    CryptoCommon::scale_array(input, metrics)
  end 
    
  def get_desired_output_for_index(price_data_array, index, n, metrics)
    delta = price_data_array[index + n].price - price_data_array[index + n - 1].price 
    delta_pct = delta.to_f / price_data_array[index + n].price
    puts "Delta: #{delta}  Pct: #{delta_pct}"
    CryptoCommon::scale_with_metrics(delta_pct, metrics)
  end 

  def test
    @train_config = CryptoData.new
    @train_config.volume = 11
    @train_config.price = 12
  end

  def testrun
    puts "In crypto controller testrun"
    @train_config = CryptoData.new(params.require(:crypto_data).permit(:volume, :price))
    puts @train_config.inspect

    puts "Get price data from the database"
    @price_data = get_price_data_from_database

    fann, metrics = load_the_model
    start_index = @train_config.volume 
    number_to_process = @train_config.price.to_i 
    end_index = start_index + number_to_process - 1

    testrun_id = rand(100)
    puts "Start testing at #{start_index}, run id #{testrun_id}"

    debug = false
    (start_index..end_index).each do |i|
      input = create_input_set_for_index(@price_data, i, 10, metrics)
      output = fann.run(input)
      scaled_output = CryptoCommon.transform_output(output, metrics)

      # Convert the predicted percentage change to a daily price
      day_before_price = @price_data[i + 9].price
      predicted_price = day_before_price + (scaled_output * day_before_price)
      actual_price_data = @price_data[i + 10]
      actual_price = actual_price_data.price

      if debug
        puts "Predict Input: #{input.join(', ')}"
        puts "Output: #{output[0]}"
        puts "Scaled Output: #{scaled_output}"
        puts "Day before price: #{day_before_price}"
        puts "Predicted price: #{predicted_price}"
        puts "Actual price:    #{actual_price}"
      end

      error_amount = predicted_price - actual_price
      error_pct = error_amount / actual_price


      prediction_object = CryptoPrediction.new
      prediction_object.run_id = testrun_id
      prediction_object.day = actual_price_data.day 
      prediction_object.price = predicted_price
      prediction_object.error_amount = error_amount
      prediction_object.error_pct = error_pct
      prediction_object.actual_price = actual_price
      prediction_object.save
    end

    redirect_to action: "testresult", run_id: testrun_id
  end



  
  def get_price_data_from_database
    price_data_array = []
    index = 0
    
    lowest_delta_value = 100000
    highest_delta_value = -100000
    
    data = CryptoData.all 
    data.each do |crypto_data|
      price_data = CryptoClosingPrice.new(index,
                                          crypto_data.day,
                                          crypto_data.price,
                                          crypto_data.volume,
                                          crypto_data.price_delta.round)
      if price_data.price_delta < lowest_delta_value
        lowest_delta_value = price_data.price_delta
      end
      if price_data.price_delta > highest_delta_value
        highest_delta_value = price_data.price_delta
      end
      price_data_array << price_data
      index = index + 1
    end

    price_delta_metrics = DataMetrics.new
    price_delta_metrics.min = lowest_delta_value
    price_delta_metrics.max = highest_delta_value
    price_delta_metrics.range = highest_delta_value - lowest_delta_value
    puts price_delta_metrics.to_display

    # If the metrics already exist, use those
    # otherwise, writ them here
    price_pct_metrics = nil
    if File.exists? "./storage/context_metrics.txt"
      # load the metrics
      persisted_metrics = File.read("./storage/context_metrics.txt")
      price_pct_metrics = YAML::load(persisted_metrics)
      puts "Loaded metrics from file"
      puts price_pct_metrics.to_display
      price_data_array.each do |pd|
        pd.price_delta_pct = pd.price_delta / pd.price
      end
    else
      price_pct_metrics = DataMetrics.new
      price_data_array.each do |pd|
        pd.price_delta_pct = pd.price_delta / pd.price
        if pd.price_delta_pct < price_pct_metrics.min
          price_pct_metrics.min = pd.price_delta_pct
        end
        if pd.price_delta_pct > price_pct_metrics.max
          price_pct_metrics.max = pd.price_delta_pct
        end
      end
      price_pct_metrics.calc_range
      puts price_pct_metrics.to_display

      str = YAML::dump(price_pct_metrics)
      puts "Yaml: #{str}"
      open("./storage/context_metrics.txt", 'w') { |f|
        f.puts str
      }
    end

    price_data_array.each do |pd|
      pd.price_delta_scaled = CryptoCommon::scale_with_metrics(pd.price_delta_pct, price_pct_metrics)
    end

    price_data_array
  end

  def view 
    @price_data = get_price_data_from_database
  end 

  def load
    temp_count = 0
    last_price = nil
    File.readlines("./storage/BTC-USD.csv").each do |line|
      line = line.chomp
      parts = line.split(",")
      day = parts[0]
      if day == "Date"
        next
      end
      price = parts[1].to_f
      vol = parts[6].to_i
      puts "[#{temp_count}]  #{day} => #{price}  (#{vol})"

      temp_object = CryptoData.new
      temp_object.day = day
      temp_object.price = price
      temp_object.volume = vol
      if last_price.nil?
        last_price = price
      else 
        temp_object.price_delta = price - last_price
        temp_object.save
        last_price = price
      end
    
      temp_count = temp_count + 1
    end
  end

  def load_the_model
    fann = RubyFann::Standard.new(:filename => "./storage/btc.net")
    persisted_metrics = File.read("./storage/context_metrics.txt")
    metrics = YAML::load(persisted_metrics)
    [fann, metrics]
  end

  def predict
    puts "In crypto controller predict"

    fann, metrics = load_the_model 

    @context = ModelContext.new
    load_data_in_context("./storage/new_BTC_updated.csv", @context)
    @context.calc_metrics

    end_index = @context.day_array.size - 1
    # indexes are inclusive, so subtract 8 to get a range of 10
    start_index = end_index - 9
    @last_day = @context.day_array[end_index]
    @prediction_day = Date.parse(@last_day) + 1

    @price_data = []
    (start_index..end_index).each do |index|
      @price_data << CryptoClosingPrice.new(index,
                                            @context.day_array[index],
                                            @context.close_array[index],
                                            @context.volume_array[index],
                                            @context.close_delta_array[index].round)
    end

    # Predict the price
    input_subset = @context.close_delta_array[start_index..end_index]
    puts "Input subset: #{input_subset.join(', ')}"
    scaled_input = CryptoCommon::scale_array(input_subset, metrics)
    puts "Scaled input: #{scaled_input.join(', ')}"

    output = fann.run(scaled_input)
    puts "Output:       #{output.join(', ')}"
    @scaled_output = CryptoCommon::transform_output(output, metrics)
    puts "Scale Output: #{@scaled_output}"
    @predicted_price = @price_data.last.close + @scaled_output

    @current_time = Time.now.utc 
    @current_btc_price = CryptoCommon::get_current_btc_in_usc
  end
end
