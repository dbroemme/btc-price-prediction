class PriceUpdateJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Running the price update job"

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
    end
  end
end
