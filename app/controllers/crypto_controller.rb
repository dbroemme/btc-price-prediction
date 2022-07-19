require 'crypto_common'

class CryptoController < ApplicationController
  include CryptoCommon

  def index
    puts "In crypto controller index"
  end

  def predict
    puts "In crypto controller predict"

    fann = RubyFann::Standard.new(:filename => "./storage/btc.net")
    persisted_metrics = File.read("./storage/context_metrics.txt")
    metrics = YAML::load(persisted_metrics)

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
