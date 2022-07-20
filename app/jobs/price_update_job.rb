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
    end
  end
end
