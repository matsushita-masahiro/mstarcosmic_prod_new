# Pin npm packages by running ./bin/importmap
pin "jquery", to: "https://ga.jspm.io/npm:jquery@3.6.0/dist/jquery.js"

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# config/importmap.rb にこれがあるか確認

pin "modal"
pin "fadein"
pin "price_banner"
pin "scroll_top"




pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
