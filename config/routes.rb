Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "crypto#index"
  get "/crypto", to: "crypto#index"
  get "/crypto/predict", to: "crypto#predict"
end
