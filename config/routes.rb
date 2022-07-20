Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "crypto#index"
  get "/crypto", to: "crypto#index"
  get "/crypto/predict", to: "crypto#predict"
  get "/crypto/load", to: "crypto#load"
  get "/crypto/view", to: "crypto#view"
  get "/crypto/baseline", to: "crypto#baseline"

  get "/crypto/enterdata", to: "crypto#enterdata"
  post "/crypto/savedata", to: "crypto#savedata"

  get "/crypto/setup", to: "crypto#setup"
  post "/crypto/train", to: "crypto#train"
  get "/crypto/test", to: "crypto#test"
  post "/crypto/testrun", to: "crypto#testrun"
  get "/crypto/testresult", to: "crypto#testresult"
  get "/crypto/deleteruns", to: "crypto#deleteruns"
end
