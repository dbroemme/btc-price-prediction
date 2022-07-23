METRICS_FILE_NAME = "./storage/context_metrics.txt"

class PriceUpdateJob < ApplicationJob
  queue_as :default
  include CryptoCommon
  
  def perform(*args)
    puts "Running the price update job"
    model_config = TenDayPricePredict.new

    most_recent_day = CryptoData.maximum(:day)
    puts "The most recent day in the database is #{most_recent_day}"

    # check if this is today
    now = Time.now
    today_str = now.strftime("%Y-%m-%d")
    if today_str == most_recent_day
      puts "We are up to date!"
    else 
      puts "We are missing data for today #{today_str}"
      current_btc_price = CryptoCommon::get_current_btc_in_usc
      puts "The current price as of #{Time.now} is #{current_btc_price}"

      new_data = CryptoData.new 
      new_data.day = today_str
      new_data.price = current_btc_price 
      new_data.volume = 0
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
      puts new_data.inspect
      # Get the price from yesterday to calculate the delta
      new_data.save

      # Now create the next prediction and save it
      fann = RubyFann::Standard.new(:filename => model_config.network_filename)
      persisted_metrics = File.read(METRICS_FILE_NAME)
      metrics = YAML::load(persisted_metrics)
      price_data = get_price_data_from_database(model_config)
  
      end_index = price_data.last.index
      start_index = end_index - model_config.number_of_days
      last_day = price_data.last.day


      prediction_day = Date.parse(last_day) + 1
      prediction_day_str = prediction_day.strftime("%Y-%m-%d")
      puts "Indexes start-end #{start_index} - #{end_index}"
      puts "Day last #{last_day}  prediction #{prediction_day_str}"
      puts "Price data size: #{price_data.size}"
  
      predicted_price = make_prediction(fann, metrics, start_index, price_data, model_config)
      puts "Predicted price for #{prediction_day} is #{predicted_price}"

      persisted_prediction = CryptoPrediction.new 
      persisted_prediction.run_id = 100000
      persisted_prediction.day = prediction_day_str
      persisted_prediction.price = predicted_price
      persisted_prediction.save
    end
  end

  def make_prediction(fann, metrics, i, price_data, model_config)
    input = model_config.create_input_set_for_index(price_data, i, metrics)
    output = fann.run(input)
    scaled_output = model_config.transform_output(output, metrics)

    # Convert the predicted percentage change to a daily price
    puts "make prediction  i: #{i}   size: #{price_data.size}"
    day_before_price = price_data[i + model_config.number_of_days - 1].price
    predicted_price = day_before_price + (scaled_output * day_before_price)
    predicted_price
  end 

  def get_price_data_from_database(model_config)
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
      pd.price_delta_scaled = model_config.scale_with_metrics(pd.price_delta_pct, price_pct_metrics)
    end

    price_data_array
  end

end
