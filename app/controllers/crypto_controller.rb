require 'crypto_common'
require 'json'

METRICS_FILE_NAME = "./storage/context_metrics.txt"

class CryptoController < ApplicationController
  include CryptoCommon

  def index
    puts "In crypto controller index"
  end

  def get_model_config
    #TenDayPricePredict.new
    #TwentyDayPricePredict.new
    #SevenDayPricePredict.new
    SevenDayVolumePredict.new
  end 

  def setup
    @train_config = CryptoData.new
    @train_config.volume = 2500
    @data_count = CryptoData.count
  end 

  def enterdata
    @new_data = CryptoData.new
    @most_recent_day = CryptoData.maximum(:day)
  end

  def priceupdate 
    PriceUpdateJob.perform_later
  end

  def savedata
    puts "In controller savedata"
    new_data = CryptoData.new(params.require(:crypto_data).permit(:day, :price, :volume))
    puts new_data.inspect
    # Get the price from yesterday to calculate the delta
    yesterday = Date.parse(new_data.day) - 1
    puts "Yesterday was #{yesterday}"
    yesterday_str = yesterday.strftime("%Y-%m-%d")
    puts "Yesterday_Str was #{yesterday_str}"
    yesterday_price_data = CryptoData.where("day = '#{yesterday_str}'")
    puts "Found #{yesterday_price_data.size} results"
    yesterday_price_data.each do |ypd|
      puts "The yesterday price data is #{ypd.day} -> #{ypd.price}"
      new_data.price_delta = new_data.price - ypd.price
    end
    new_data.save
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
    model_config = get_model_config

    puts "In crypto controller train"
    @train_config = CryptoData.new(params.require(:crypto_data).permit(:volume))
    puts @train_config.inspect
    # TODO we are using an active record so the form is easier.
    #      should change this later
    training_index_cutoff = @train_config.volume

    @price_data = get_price_data_from_database
    persisted_metrics = File.read(METRICS_FILE_NAME)
    metrics = YAML::load(persisted_metrics)

    # Each of these is an array of arrays
    @input_array = []
    @desired_output_array = []

    (0..training_index_cutoff).each do |train_index|
      input = model_config.create_input_set_for_index(@price_data, train_index, model_config.number_of_inputs, metrics)
      desired_output = model_config.get_desired_output_for_index(@price_data, train_index, model_config.number_of_inputs, metrics)
      puts "Input:  #{input}  ->  #{desired_output}"
      @input_array << input 
      @desired_output_array << [desired_output]
    end

    train = RubyFann::TrainData.new(:inputs => @input_array,
                                    :desired_outputs => @desired_output_array)
    fann = RubyFann::Standard.new(:num_inputs => model_config.number_of_inputs, 
                                  :hidden_neurons => model_config.hidden_layers,
                                  :num_outputs => 1)
    #5100 max_epochs, 20 errors between reports and 0.001 desired MSE (mean-squared-error)
    fann.train_on_data(train, 500, 20, 0.001)

    File.delete(model_config.network_filename) if File.exist? model_config.network_filename
    fann.save(model_config.network_filename)
    @network_trained = true

    redirect_to action: "test"
  end 

  def test
    @train_config = CryptoData.new
    @train_config.volume = 2501
    @train_config.price = 100
  end

  def make_prediction(fann, metrics, i, price_data, n)
    model_config = get_model_config

    input = model_config.create_input_set_for_index(price_data, i, model_config.number_of_inputs, metrics)
    output = fann.run(input)
    scaled_output = model_config.transform_output(output, metrics)

    # Convert the predicted percentage change to a daily price
    puts "make prediction  i: #{i}   size: #{price_data.size}"
    day_before_price = price_data[i + n - 1].price
    predicted_price = day_before_price + (scaled_output * day_before_price)
    predicted_price
  end 

  def testrun
    puts "In crypto controller testrun"
    model_config = get_model_config

    @train_config = CryptoData.new(params.require(:crypto_data).permit(:volume, :price))
    puts @train_config.inspect

    puts "Get price data from the database"
    @price_data = get_price_data_from_database

    fann, metrics = load_the_model
    start_index = @train_config.volume 
    number_to_process = @train_config.price.to_i 
    end_index = start_index + number_to_process - 1

    testrun_id = rand(99999)
    puts "Start testing at #{start_index}, run id #{testrun_id}"

    debug = false
    (start_index..end_index).each do |i|
      predicted_price = make_prediction(fann, metrics, i, @price_data, model_config.number_of_inputs)
      actual_price_data = model_config.get_actual_price_data(i, model_config.number_of_inputs, @price_data)
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
    
    lowest_delta_value = 900000
    highest_delta_value = -900000
    
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
    if File.exists? METRICS_FILE_NAME
      # load the metrics
      persisted_metrics = File.read(METRICS_FILE_NAME)
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
      open(METRICS_FILE_NAME, 'w') { |f|
        f.puts str
      }
    end

    price_data_array.each do |pd|
      pd.price_delta_scaled = get_model_config.scale_with_metrics(pd.price_delta_pct, price_pct_metrics)
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
    model_config = get_model_config
    fann = RubyFann::Standard.new(:filename => model_config.network_filename)
    persisted_metrics = File.read(METRICS_FILE_NAME)
    metrics = YAML::load(persisted_metrics)
    [fann, metrics]
  end

  def predict
    puts "In crypto controller predict"
    model_config = get_model_config
    fann, metrics = load_the_model 
    @price_data = get_price_data_from_database

    end_index = @price_data.last.index
    start_index = end_index - model_config.number_of_inputs - 1
    @last_day = @price_data.last.day
    @prediction_day = Date.parse(@last_day) + 1

    @historical_data = []
    (start_index..end_index).each do |index|
      @historical_data << CryptoClosingPrice.new(index,
                                                 @price_data[index].day,
                                                 @price_data[index].price,
                                                 @price_data[index].volume,
                                                 @price_data[index].price_delta.round)
    end

    @predicted_price = make_prediction(fann, metrics, start_index, @price_data, model_config.number_of_inputs)
    @current_time = Time.now.utc 
    @current_btc_price = CryptoCommon::get_current_btc_in_usc
  end

  def predict_api
    puts "In crypto controller predict api"
    model_config = get_model_config
    fann, metrics = load_the_model 
    price_data = get_price_data_from_database

    end_index = price_data.last.index
    start_index = end_index - model_config.number_of_inputs - 1
    last_day = price_data.last.day
    prediction_day = Date.parse(last_day) + 1

    puts "Indexes start-end #{start_index} - #{end_index}"
    puts "Day last #{last_day}  prediction #{prediction_day}"
    puts "Price data size: #{price_data.size}"

    predicted_price = make_prediction(fann, metrics, start_index, price_data, model_config.number_of_inputs)
    output = PricePredictionApiOutput.new(prediction_day, predicted_price)
    render :json => output
  end

end
