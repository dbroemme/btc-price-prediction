class PriceUpdateJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "Running the price update job"
  end
end
